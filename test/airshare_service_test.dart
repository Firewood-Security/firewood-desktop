import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:firewood_desktop/src/services/airshare_service.dart';

void main() {
  late AirShareService service;

  setUp(() {
    service = AirShareService();
  });

  test('Spark URI creation and parsing roundtrip', () async {
    final keyPair = await service.generateKeyPair();
    final pk = await keyPair.extractPublicKey();
    final nonce = service.generateNonce();
    final deviceName = 'Galaxy S24 Ultra';

    final uri = service.createSparkUri(
      publicKey: pk,
      nonce: nonce,
      deviceName: deviceName,
    );

    expect(uri.startsWith('firewood://spark?'), isTrue);

    final parsed = service.parseSparkUri(uri);
    expect(parsed.publicKey.bytes, equals(pk.bytes));
    expect(parsed.nonce, equals(nonce));
    expect(parsed.deviceName, equals(deviceName));
  });

  test('Flame Code derivation generates matching 4-digit code on both peers', () async {
    final aliceKp = await service.generateKeyPair();
    final alicePk = await aliceKp.extractPublicKey();

    final bobKp = await service.generateKeyPair();
    final bobPk = await bobKp.extractPublicKey();

    final salt = service.generateNonce();

    final aliceSecret = await service.computeSharedSecret(
      localKeyPair: aliceKp,
      remotePublicKey: bobPk,
    );

    final bobSecret = await service.computeSharedSecret(
      localKeyPair: bobKp,
      remotePublicKey: alicePk,
    );

    final aliceCode = await service.deriveFlameCode(
      sharedSecret: aliceSecret,
      salt: salt,
    );

    final bobCode = await service.deriveFlameCode(
      sharedSecret: bobSecret,
      salt: salt,
    );

    expect(aliceCode, equals(bobCode));
    expect(aliceCode.length, equals(4));
    expect(int.tryParse(aliceCode), isNotNull);
    expect(int.parse(aliceCode), inInclusiveRange(1000, 9999));
  });

  test('AirSharePayload encryption and decryption with derived session key', () async {
    final aliceKp = await service.generateKeyPair();
    final alicePk = await aliceKp.extractPublicKey();

    final bobKp = await service.generateKeyPair();
    final bobPk = await bobKp.extractPublicKey();

    final salt = service.generateNonce();

    final aliceSecret = await service.computeSharedSecret(
      localKeyPair: aliceKp,
      remotePublicKey: bobPk,
    );
    final aliceSessionKey = await service.deriveSessionKey(
      sharedSecret: aliceSecret,
      salt: salt,
    );

    final bobSecret = await service.computeSharedSecret(
      localKeyPair: bobKp,
      remotePublicKey: alicePk,
    );
    final bobSessionKey = await service.deriveSessionKey(
      sharedSecret: bobSecret,
      salt: salt,
    );

    final originalPayload = AirSharePayload(
      kind: AirShareKind.credential,
      title: 'GitHub Admin Token',
      data: {
        'username': 'octocat',
        'password': 'ghp_secret_token_12345',
        'url': 'https://github.com',
      },
      rawBytes: utf8.encode('metadata'),
    );

    final encrypted = await service.encryptPayload(
      payload: originalPayload,
      sessionKey: aliceSessionKey,
    );

    final decrypted = await service.decryptPayload(
      encryptedBytes: encrypted,
      sessionKey: bobSessionKey,
    );

    expect(decrypted.kind, equals(AirShareKind.credential));
    expect(decrypted.title, equals('GitHub Admin Token'));
    expect(decrypted.data['username'], equals('octocat'));
    expect(decrypted.data['password'], equals('ghp_secret_token_12345'));
    expect(decrypted.data['url'], equals('https://github.com'));
    expect(decrypted.rawBytes, equals(utf8.encode('metadata')));
  });
}
