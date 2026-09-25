import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Payload type for an AirShare transfer.
enum AirShareKind { vault, credential, file }

/// Information about a payload to be shared or received.
class AirSharePayload {
  final AirShareKind kind;
  final String title;
  final Map<String, dynamic> data;
  final List<int> rawBytes;

  const AirSharePayload({
    required this.kind,
    required this.title,
    required this.data,
    required this.rawBytes,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'title': title,
        'data': data,
        'rawBytes': base64Encode(rawBytes),
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

  factory AirSharePayload.fromJson(Map<String, dynamic> json) {
    final kindStr = json['kind'] as String? ?? 'credential';
    final kind = AirShareKind.values.firstWhere(
      (k) => k.name == kindStr,
      orElse: () => AirShareKind.credential,
    );
    final rawBytesStr = json['rawBytes'] as String? ?? '';
    return AirSharePayload(
      kind: kind,
      title: json['title'] as String? ?? 'Shared Item',
      data: Map<String, dynamic>.from(json['data'] as Map? ?? {}),
      rawBytes: rawBytesStr.isNotEmpty ? base64Decode(rawBytesStr) : [],
    );
  }
}

/// Core cryptographic engine for Firewood AirShare:
/// - Mode 1: Spark (QR Bootstrap + X25519 + ChaCha20-Poly1305)
/// - Mode 2: Flame Code (Proximity BLE + 4-Digit SAS + ChaCha20-Poly1305)
class AirShareService {
  final X25519 _x25519 = X25519();
  final Cipher _cipher = Chacha20.poly1305Aead();

  /// Generates a cryptographically random salt or session nonce.
  String generateNonce([int length = 16]) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Generates an ephemeral X25519 keypair for a single session.
  Future<SimpleKeyPair> generateKeyPair() async {
    return _x25519.newKeyPair();
  }

  /// Computes shared secret between local keypair and remote public key.
  Future<SecretKey> computeSharedSecret({
    required SimpleKeyPair localKeyPair,
    required SimplePublicKey remotePublicKey,
  }) async {
    return _x25519.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: remotePublicKey,
    );
  }

  /// Derives symmetric session encryption key using HKDF-SHA256.
  Future<SecretKey> deriveSessionKey({
    required SecretKey sharedSecret,
    required String salt,
  }) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode(salt),
      info: utf8.encode('firewood-spark-v1'),
    );
  }

  /// Derives a 4-digit Flame Code (1000..9999) from the shared secret.
  /// Simple 4-digit code for human verification (no complex emojis).
  Future<String> deriveFlameCode({
    required SecretKey sharedSecret,
    required String salt,
  }) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derived = await hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode(salt),
      info: utf8.encode('firewood-flame-code-v1'),
    );
    final bytes = await derived.extractBytes();
    final val = ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]).abs();
    final code = (val % 9000 + 1000).toString();
    return code;
  }

  /// Encrypts an [AirSharePayload] using the derived [sessionKey].
  /// Output format: [12-byte nonce] + [16-byte Poly1305 MAC] + [ciphertext].
  Future<List<int>> encryptPayload({
    required AirSharePayload payload,
    required SecretKey sessionKey,
  }) async {
    final plaintext = utf8.encode(jsonEncode(payload.toJson()));
    final nonce = _cipher.newNonce();
    final secretBox = await _cipher.encrypt(
      plaintext,
      secretKey: sessionKey,
      nonce: nonce,
    );

    return [
      ...secretBox.nonce,
      ...secretBox.mac.bytes,
      ...secretBox.cipherText,
    ];
  }

  /// Decrypts encrypted bytes using the derived [sessionKey].
  Future<AirSharePayload> decryptPayload({
    required List<int> encryptedBytes,
    required SecretKey sessionKey,
  }) async {
    if (encryptedBytes.length < 28) {
      throw const FormatException('Corrupt AirShare payload: too short');
    }

    final nonce = encryptedBytes.sublist(0, 12);
    final macBytes = encryptedBytes.sublist(12, 28);
    final cipherText = encryptedBytes.sublist(28);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final decryptedBytes = await _cipher.decrypt(
      secretBox,
      secretKey: sessionKey,
    );

    final decodedJson = jsonDecode(utf8.decode(decryptedBytes)) as Map<String, dynamic>;
    return AirSharePayload.fromJson(decodedJson);
  }

  /// Creates a Spark URI for QR code generation.
  /// Format: firewood://spark?pk=[b64]&nonce=[nonce]&name=[name]
  String createSparkUri({
    required SimplePublicKey publicKey,
    required String nonce,
    required String deviceName,
  }) {
    final pkBase64 = base64UrlEncode(publicKey.bytes);
    final query = Uri(queryParameters: {
      'pk': pkBase64,
      'nonce': nonce,
      'name': deviceName,
    }).query;
    return 'firewood://spark?$query';
  }

  /// Parses a Spark URI from a QR scan or manual input.
  ({SimplePublicKey publicKey, String nonce, String deviceName}) parseSparkUri(
      String rawUri) {
    final trimmed = rawUri.trim();
    final uri = Uri.parse(trimmed);
    if (uri.scheme != 'firewood' || uri.host != 'spark') {
      throw const FormatException('Invalid Spark URI format. Expected firewood://spark?...');
    }

    final pkStr = uri.queryParameters['pk'];
    final nonce = uri.queryParameters['nonce'] ?? '';
    final name = uri.queryParameters['name'] ?? 'Firewood Peer';

    if (pkStr == null || pkStr.isEmpty) {
      throw const FormatException('Spark URI missing public key parameter');
    }

    final pkBytes = base64Url.decode(pkStr);
    final publicKey = SimplePublicKey(pkBytes, type: KeyPairType.x25519);

    return (publicKey: publicKey, nonce: nonce, deviceName: name);
  }
}
