// V-047 + V-012 frame-bounds tests for the desktop BLE transport parser.
//
// The parser is the one part of the BLE receive path that faces bytes from an
// unauthenticated-distance peer, so its bounds are security behavior: a
// hostile declared length must be rejected before any payload is buffered,
// invalid name bytes must not escape as raw FormatExceptions, and the default
// cap must stay mirrored to the mobile BleFrameAssembler.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_desktop/src/services/ble_share_transport.dart';

void main() {
  List<int> header({required int payloadLength, required int nameLength}) => [
        (payloadLength >> 24) & 0xFF,
        (payloadLength >> 16) & 0xFF,
        (payloadLength >> 8) & 0xFF,
        payloadLength & 0xFF,
        (nameLength >> 8) & 0xFF,
        nameLength & 0xFF,
      ];

  group('BleShareTransport.tryParseFrame', () {
    test('default cap mirrors the mobile BleFrameAssembler (8 MB)', () {
      expect(BleShareTransport.maxFrameBytes, 8 * 1024 * 1024);
    });

    test('parses a complete frame (name + payload)', () {
      final name = utf8.encode('vault.firewood');
      final payload = [1, 2, 3, 4, 5];
      final buffer = <int>[
        ...header(payloadLength: payload.length, nameLength: name.length),
        ...name,
        ...payload,
      ];

      final parsed = BleShareTransport.tryParseFrame(buffer);
      expect(parsed, isNotNull);
      expect(parsed!.fileName, 'vault.firewood');
      expect(parsed.bytes, payload);
    });

    test('returns null while header or body is incomplete', () {
      expect(BleShareTransport.tryParseFrame([]), isNull);
      expect(BleShareTransport.tryParseFrame([0, 0, 0]), isNull);
      // Header declares 100 payload bytes but only 20 have arrived.
      expect(
        BleShareTransport.tryParseFrame(
            header(payloadLength: 100, nameLength: 5)),
        isNull,
      );
      // Complete header, partial name.
      expect(
        BleShareTransport.tryParseFrame([
          ...header(payloadLength: 10, nameLength: 20),
          0x61,
        ]),
        isNull,
      );
    });

    test('rejects a declared length beyond the cap before buffering', () {
      // Only the 6-byte header exists — the hostile u32 (9 MB) must be
      // refused without waiting for (or accumulating) a single payload byte.
      final headerOnly = header(payloadLength: 9 * 1024 * 1024, nameLength: 0);
      expect(
        () => BleShareTransport.tryParseFrame(headerOnly),
        throwsA(isA<ShareException>()),
      );
    });

    test('honors a custom limit at the exact boundary', () {
      // total = 6 + 5 + 10 = 21 bytes → exactly at limit parses.
      final name = utf8.encode('a.txt');
      final payload = List<int>.generate(10, (i) => i);
      final buffer = <int>[
        ...header(payloadLength: 10, nameLength: name.length),
        ...name,
        ...payload,
      ];
      expect(BleShareTransport.tryParseFrame(buffer, limit: 21), isNotNull);

      // One byte more than the limit → hostile, rejected.
      final overLimit = header(payloadLength: 11, nameLength: 5);
      expect(
        () => BleShareTransport.tryParseFrame(overLimit, limit: 21),
        throwsA(isA<ShareException>()),
      );
    });

    test('throws ShareException (not FormatException) for non-UTF-8 name', () {
      final buffer = <int>[
        ...header(payloadLength: 1, nameLength: 2),
        0xFF,
        0xFE, // invalid UTF-8 lead bytes
        0x41,
      ];
      expect(
        () => BleShareTransport.tryParseFrame(buffer),
        throwsA(isA<ShareException>()),
      );
    });

    test('zero-length payload and empty name still parse (no hang)', () {
      final buffer = header(payloadLength: 0, nameLength: 0);
      final parsed = BleShareTransport.tryParseFrame(buffer);
      expect(parsed, isNotNull);
      expect(parsed!.fileName, isEmpty);
      expect(parsed.bytes, isEmpty);
    });
  });
}
