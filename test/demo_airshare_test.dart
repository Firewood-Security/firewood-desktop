import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:firewood_desktop/src/services/airshare_service.dart';

void main() {
  test('DEMO: Full AirShare Spark & Flame Code 4-Digit Handshake', () async {
    final airShare = AirShareService();

    print('\n============================================================');
    print('  FIREWOOD AIRSHARE PROTOCOL DEMONSTRATION');
    print('============================================================\n');

    // -------------------------------------------------------------
    // DEMO 1: SPARK MODE (QR Bootstrap + X25519 + ChaCha20-Poly1305)
    // -------------------------------------------------------------
    print('[MODE 1: SPARK (QR BOOTSTRAP)]');

    // 1. Receiver generates ephemeral keypair and session nonce
    final receiverKp = await airShare.generateKeyPair();
    final receiverPk = await receiverKp.extractPublicKey();
    final nonce = airShare.generateNonce(12);

    // 2. Receiver generates Spark URI for the QR code
    final sparkUri = airShare.createSparkUri(
      publicKey: receiverPk,
      nonce: nonce,
      deviceName: 'Alice-Desktop-Linux',
    );

    print('  1. Receiver generates Spark QR URI:');
    print('     $sparkUri');

    // 3. Sender scans/parses the Spark URI
    final parsed = airShare.parseSparkUri(sparkUri);
    print('  2. Sender scans QR and parses parameters:');
    print('     - Device Name: ${parsed.deviceName}');
    print('     - Session Nonce: ${parsed.nonce}');
    print('     - Receiver Ephemeral PK: ${base64Url.encode(parsed.publicKey.bytes)}');

    // 4. Sender generates ephemeral keypair & performs ECDH
    final senderKp = await airShare.generateKeyPair();
    final senderSecret = await airShare.computeSharedSecret(
      localKeyPair: senderKp,
      remotePublicKey: parsed.publicKey,
    );
    final senderSessionKey = await airShare.deriveSessionKey(
      sharedSecret: senderSecret,
      salt: parsed.nonce,
    );

    // 5. Sender encrypts credential payload with ChaCha20-Poly1305
    final secretPayload = AirSharePayload(
      kind: AirShareKind.credential,
      title: 'Production Database Root',
      data: {
        'username': 'postgres_admin',
        'password': 'Firewood#DbSuperSecret2026!',
        'url': 'postgresql://db.corp.internal:5432/main',
      },
      rawBytes: utf8.encode('attachment: ssl-cert-fingerprint'),
    );

    final cipherBytes = await airShare.encryptPayload(
      payload: secretPayload,
      sessionKey: senderSessionKey,
    );

    print('  3. Sender derives 256-bit session key via HKDF-SHA256');
    print('  4. Sender encrypts payload via ChaCha20-Poly1305:');
    print('     - Ciphertext size: ${cipherBytes.length} bytes (incl. 12B nonce + 16B MAC)');

    // 6. Receiver derives matching session key
    final senderPk = await senderKp.extractPublicKey();
    final receiverSecret = await airShare.computeSharedSecret(
      localKeyPair: receiverKp,
      remotePublicKey: senderPk,
    );
    final receiverSessionKey = await airShare.deriveSessionKey(
      sharedSecret: receiverSecret,
      salt: nonce,
    );

    // 7. Receiver decrypts in memory
    final decryptedPayload = await airShare.decryptPayload(
      encryptedBytes: cipherBytes,
      sessionKey: receiverSessionKey,
    );

    print('  5. Receiver decrypts payload in volatile RAM:');
    print('     - Title: ${decryptedPayload.title}');
    print('     - Username: ${decryptedPayload.data['username']}');
    print('     - Password: ${decryptedPayload.data['password']}');

    expect(decryptedPayload.title, equals(secretPayload.title));
    expect(decryptedPayload.data['password'], equals('Firewood#DbSuperSecret2026!'));
    print('  => SPARK MODE COMPLETED WITH ZERO LEAKS!\n');

    // -------------------------------------------------------------
    // DEMO 2: FLAME CODE MODE (4-Digit SAS Proximity Verification)
    // -------------------------------------------------------------
    print('[MODE 2: FLAME CODE (4-DIGIT SAS VERIFICATION)]');

    // 1. Both devices discover each other over BLE & exchange ephemeral PKs
    final peerA_Kp = await airShare.generateKeyPair();
    final peerA_Pk = await peerA_Kp.extractPublicKey();

    final peerB_Kp = await airShare.generateKeyPair();
    final peerB_Pk = await peerB_Kp.extractPublicKey();

    final bleSalt = airShare.generateNonce(12);

    // 2. Both compute Diffie-Hellman shared secret
    final secretA = await airShare.computeSharedSecret(
      localKeyPair: peerA_Kp,
      remotePublicKey: peerB_Pk,
    );
    final secretB = await airShare.computeSharedSecret(
      localKeyPair: peerB_Kp,
      remotePublicKey: peerA_Pk,
    );

    // 3. Both derive the 4-digit numeric Flame Code
    final flameCodeA = await airShare.deriveFlameCode(
      sharedSecret: secretA,
      salt: bleSalt,
    );
    final flameCodeB = await airShare.deriveFlameCode(
      sharedSecret: secretB,
      salt: bleSalt,
    );

    print('  1. Peer A computes Flame Code: [ $flameCodeA ]');
    print('  2. Peer B computes Flame Code: [ $flameCodeB ]');

    expect(flameCodeA, equals(flameCodeB));
    expect(flameCodeA.length, equals(4));
    expect(int.tryParse(flameCodeA), isNotNull);

    print('  3. Visual match verified by users: "$flameCodeA" == "$flameCodeB"');
    print('     => Both users confirm 4-digit code matches on their screens.');

    // 4. Transmission after confirmation
    final sessionKeyA = await airShare.deriveSessionKey(sharedSecret: secretA, salt: bleSalt);
    final sessionKeyB = await airShare.deriveSessionKey(sharedSecret: secretB, salt: bleSalt);

    final flameEncrypted = await airShare.encryptPayload(
      payload: secretPayload,
      sessionKey: sessionKeyA,
    );

    final flameDecrypted = await airShare.decryptPayload(
      encryptedBytes: flameEncrypted,
      sessionKey: sessionKeyB,
    );

    print('  4. Encrypted stream transmitted over BLE characteristic.');
    print('  5. Receiver decrypts in RAM:');
    print('     - Decrypted item: "${flameDecrypted.title}"');

    expect(flameDecrypted.title, equals(secretPayload.title));
    print('  => FLAME CODE MODE 4-DIGIT VERIFICATION SUCCESSFUL!');
    print('\n============================================================\n');
  });
}
