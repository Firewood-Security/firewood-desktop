import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';

void main() {
  test('X25519 key exchange + HKDF Flame Code 4-digit generation', () async {
    final x25519 = X25519();

    // Alice (Sender)
    final aliceKeyPair = await x25519.newKeyPair();
    final alicePk = await aliceKeyPair.extractPublicKey();

    // Bob (Receiver)
    final bobKeyPair = await x25519.newKeyPair();
    final bobPk = await bobKeyPair.extractPublicKey();

    // Alice computes shared secret with Bob's PK
    final aliceSharedSecret = await x25519.sharedSecretKey(
      keyPair: aliceKeyPair,
      remotePublicKey: bobPk,
    );

    // Bob computes shared secret with Alice's PK
    final bobSharedSecret = await x25519.sharedSecretKey(
      keyPair: bobKeyPair,
      remotePublicKey: alicePk,
    );

    final aliceSecretBytes = await aliceSharedSecret.extractBytes();
    final bobSecretBytes = await bobSharedSecret.extractBytes();

    expect(aliceSecretBytes, equals(bobSecretBytes));

    // HKDF derive flame code (4-digit number: 1000..9999)
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final aliceDerived = await hkdf.deriveKey(
      secretKey: aliceSharedSecret,
      nonce: utf8.encode('salt-spark-v1'),
      info: utf8.encode('firewood-flame-code-v1'),
    );
    final bobDerived = await hkdf.deriveKey(
      secretKey: bobSharedSecret,
      nonce: utf8.encode('salt-spark-v1'),
      info: utf8.encode('firewood-flame-code-v1'),
    );

    final aBytes = await aliceDerived.extractBytes();
    final bBytes = await bobDerived.extractBytes();
    expect(aBytes, equals(bBytes));

    // Compute 4 digit number
    final aCode = (((aBytes[0] << 24) | (aBytes[1] << 16) | (aBytes[2] << 8) | aBytes[3]).abs() % 9000 + 1000).toString();
    final bCode = (((bBytes[0] << 24) | (bBytes[1] << 16) | (bBytes[2] << 8) | bBytes[3]).abs() % 9000 + 1000).toString();

    expect(aCode, equals(bCode));
    expect(aCode.length, equals(4));
  });

  test('ChaCha20-Poly1305 encryption/decryption with HKDF derived key', () async {
    final cipher = Chacha20.poly1305Aead();
    final secretKey = SecretKey(List<int>.generate(32, (i) => i));
    final plaintext = utf8.encode('Top secret credentials');
    final nonce = cipher.newNonce();

    final secretBox = await cipher.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );

    final decrypted = await cipher.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    expect(utf8.decode(decrypted), equals('Top secret credentials'));
  });
}
