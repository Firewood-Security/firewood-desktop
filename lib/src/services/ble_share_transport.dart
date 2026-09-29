// Real Bluetooth Low Energy transport for the desktop app (central role).
//
// The Firewood peer (e.g. the Android app) advertises the Firewood GATT service
// and exposes a single file characteristic. This transport scans for it,
// connects, and streams the encrypted `.firewood` payload in MTU-sized chunks
// using a tiny framing protocol (4-byte total length + 2-byte name length +
// name bytes + payload). Receiving subscribes to characteristic notifications.
//
// On Linux the plugin talks to BlueZ; on macOS/iOS to CoreBluetooth; on
// Windows the winrt implementation is used. When no adapter/backend is present
// isAvailable() returns false and the UI reports the transport as unavailable.
//
// Security (V-012/V-047):
//  * The transport never picks a peer by itself. Every advertiser of the
//    service UUID is collected for a short window and handed to
//    [peerConfirmer]; with no confirmer registered the connection fails
//    closed. This closes the rogue-advertiser MITM window.
//  * Incoming frames are bounded by [maxFrameBytes] — a hostile header
//    declaring an impossible length is rejected before a single payload byte
//    is buffered for it, and the buffer is cleared on timeout/error.
//  * Writes wait (bounded) for the Android peer's bonding handshake, because
//    the Firewood characteristic only accepts writes on an encrypted link.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:firewood_core/firewood_core.dart';

class BleShareTransport implements ShareTransport {
  /// GATT service advertised by a Firewood peer (matches Android native UUIDs).
  static final Guid serviceUuid = Guid('0000ff00-0000-1000-8000-00805f9b34fb');

  /// Characteristic carrying the framed file (write + notify).
  static final Guid fileCharUuid = Guid('0000ff01-0000-1000-8000-00805f9b34fb');

  /// V-047/V-012: hard bound for a single framed transfer — mirrors the
  /// mobile `BleFrameAssembler.DEFAULT_MAX_FRAME_BYTES`. Anything declaring
  /// more than this is a hostile peer, not a file.
  static const int maxFrameBytes = 8 * 1024 * 1024;

  /// V-012: how long advertisers are collected before the user is asked
  /// which peer is the real one.
  static const Duration discoveryWindow = Duration(seconds: 5);

  /// V-012: bounded wait for the remote peer's bonding handshake (the Android
  /// side enforces `PERMISSION_WRITE_ENCRYPTED` and starts pairing on connect).
  static const Duration bondWait = Duration(seconds: 15);

  /// V-012: the UI registers a confirmer that presents the collected
  /// candidates and returns the device the user picked (null = cancel).
  /// The transport refuses to connect without one.
  Future<BluetoothDevice?> Function(List<BlePeerCandidate> candidates)?
      peerConfirmer;

  final List<int> _incoming = [];
  ShareException? _frameError;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _char;
  StreamSubscription<List<int>>? _sub;
  bool _listening = false;

  @override
  String get name => 'Bluetooth LE';

  @override
  Future<bool> isAvailable() async {
    try {
      if (!await FlutterBluePlus.isSupported) return false;
      final state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isListening() async => _listening;

  Future<BluetoothDevice> _findPeer() async {
    // V-012: "first advertiser wins" is the rogue-advertiser hole — collect
    // every peer advertising the Firewood service for a short window, then
    // require the user to confirm which one to trust. With no confirmer
    // registered we never connect at all (fail closed).
    final candidates = <String, BlePeerCandidate>{};
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final key = r.device.remoteId.toString();
        final name = r.device.advName.isNotEmpty
            ? r.device.advName
            : r.device.platformName;
        final prev = candidates[key];
        if (prev == null || r.rssi > prev.rssi) {
          candidates[key] = BlePeerCandidate(
            device: r.device,
            name: name.isEmpty ? 'Firewood peer' : name,
            rssi: r.rssi,
          );
        }
      }
    });
    try {
      await FlutterBluePlus.startScan(withServices: [serviceUuid]);
      await Future.delayed(discoveryWindow);
    } finally {
      await FlutterBluePlus.stopScan();
      await sub.cancel();
    }

    if (candidates.isEmpty) {
      throw const ShareException('No Firewood peer found nearby');
    }
    final confirm = peerConfirmer;
    if (confirm == null) {
      throw const ShareException(
          'BLE peer confirmation is unavailable — refusing to connect to an unconfirmed peer');
    }
    final sorted = candidates.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    final chosen = await confirm(sorted);
    if (chosen == null) {
      throw const ShareException('Transfer cancelled — no peer was confirmed');
    }
    return chosen;
  }

  Future<BluetoothCharacteristic> _connectAndDiscover(
      BluetoothDevice device) async {
    // flutter_blue_plus requires a license declaration. `nonprofit` covers
    // personal/nonprofit use; a commercial license is required for for-profit use.
    await device.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 15),
    );
    final services = await device.discoverServices();
    for (final service in services) {
      if (service.uuid == serviceUuid) {
        for (final c in service.characteristics) {
          if (c.uuid == fileCharUuid) return c;
        }
      }
    }
    throw const ShareException('Firewood BLE service not found on the peer');
  }

  /// V-012: the Android peer only accepts writes on an encrypted (bonded)
  /// link and starts pairing when we connect. Give that handshake a bounded
  /// window to complete before failing closed — writes are sent with response,
  /// so a rejected one was never applied and is safe to retry.
  Future<void> _writeWithBondWait(
      BluetoothCharacteristic characteristic, List<int> data) async {
    final deadline = DateTime.now().add(bondWait);
    while (true) {
      try {
        await characteristic.write(data, withoutResponse: false);
        return;
      } catch (_) {
        if (DateTime.now().isAfter(deadline)) rethrow;
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  @override
  Future<void> send(
      {required String fileName, required List<int> bytes}) async {
    if (!await isAvailable()) {
      throw const ShareException('Bluetooth is turned off or unavailable');
    }
    final device = await _findPeer();
    final characteristic = await _connectAndDiscover(device);

    final nameBytes = utf8.encode(fileName);
    final header = <int>[
      ..._u32(bytes.length),
      ..._u16(nameBytes.length),
      ...nameBytes,
    ];

    final mtu = device.mtuNow > 23 ? device.mtuNow : 23;
    final chunk = mtu - 3;

    await _writeWithBondWait(characteristic, header);
    for (var i = 0; i < bytes.length; i += chunk) {
      final end = (i + chunk < bytes.length) ? i + chunk : bytes.length;
      await _writeWithBondWait(characteristic, bytes.sublist(i, end));
    }

    await device.disconnect();
  }

  @override
  Future<void> startListening() async {
    if (_listening) return;
    if (!await isAvailable()) {
      throw const ShareException('Bluetooth is turned off or unavailable');
    }
    final device = await _findPeer();
    final characteristic = await _connectAndDiscover(device);
    _incoming.clear();
    _frameError = null;
    _sub = characteristic.onValueReceived.listen(_append);
    await characteristic.setNotifyValue(true);
    _device = device;
    _char = characteristic;
    _listening = true;
  }

  @override
  Future<void> stopListening() async {
    _listening = false;
    await _sub?.cancel();
    _sub = null;
    try {
      await _char?.setNotifyValue(false);
    } catch (_) {}
    try {
      await _device?.disconnect();
    } catch (_) {}
    _char = null;
    _device = null;
    // V-047: never keep partial bytes around after the session ends.
    _incoming.clear();
    _frameError = null;
  }

  /// V-047: bounded buffering — a peer that streams without ever completing
  /// a header must not be able to grow this buffer without limit.
  void _append(List<int> chunk) {
    if (_incoming.length + chunk.length > maxFrameBytes) {
      _incoming.clear();
      _frameError ??= const ShareException(
          'Incoming BLE transfer exceeded the frame size limit');
      return;
    }
    _incoming.addAll(chunk);
  }

  @override
  Future<SentFile?> receive() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final err = _frameError;
      if (err != null) {
        _frameError = null;
        _incoming.clear();
        throw err;
      }
      final SentFile? parsed;
      try {
        parsed = tryParseFrame(_incoming);
      } on ShareException {
        _incoming.clear();
        rethrow;
      }
      if (parsed != null) return parsed;
      await Future.delayed(const Duration(milliseconds: 150));
    }
    // V-047: a timed-out attempt must not leave a partial frame behind for
    // the next one — stale bytes would corrupt whatever arrives next.
    _incoming.clear();
    return null;
  }

  /// Parses one complete framed transfer out of [buffer].
  ///
  /// Returns null while the frame is incomplete, throws [ShareException] when
  /// the header declares something that cannot be a Firewood frame (V-047),
  /// and returns the frame once every declared byte has arrived. [limit]
  /// overrides the default [maxFrameBytes] cap (tests).
  static SentFile? tryParseFrame(List<int> buffer, {int? limit}) {
    final max = limit ?? maxFrameBytes;
    if (buffer.length < 6) return null;
    final payloadLength =
        (buffer[0] << 24) | (buffer[1] << 16) | (buffer[2] << 8) | buffer[3];
    final nameLength = (buffer[4] << 8) | buffer[5];
    final total = 6 + nameLength + payloadLength;

    // V-047: hostile header — reject the declared length before buffering a
    // single payload byte for it (the old code would have waited forever,
    // growing the buffer toward the 4 GiB a u32 can declare).
    if (total > max) {
      throw ShareException(
          'Declared BLE frame of $total bytes exceeds the $max byte limit');
    }
    if (buffer.length < total) return null;

    final String name;
    try {
      name = utf8.decode(buffer.sublist(6, 6 + nameLength));
    } on FormatException {
      throw const ShareException('Incoming BLE frame has an invalid file name');
    }
    final data = buffer.sublist(6 + nameLength, total);
    return SentFile(fileName: name, bytes: data);
  }

  @override
  Future<void> dispose() => stopListening();

  List<int> _u32(int v) =>
      [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
  List<int> _u16(int v) => [(v >> 8) & 0xFF, v & 0xFF];
}

/// A discovered Firewood peer, offered to `BleShareTransport.peerConfirmer`
/// so the user can confirm which device is the real one before any
/// connection is made (V-012).
class BlePeerCandidate {
  const BlePeerCandidate(
      {required this.device, required this.name, required this.rssi});

  final BluetoothDevice device;

  /// Broadcast name (falls back to the platform name; 'Firewood peer' when
  /// the advertiser did not announce one).
  final String name;

  /// Strongest signal seen during the discovery window.
  final int rssi;
}
