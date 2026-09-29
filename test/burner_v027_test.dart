// Adversarial tests for V-027 — per-entry burner salts (core/desktop).
//
// The legacy fixture (test/fixtures/v027_legacy/) was generated with the
// PRE-change schema (no `salt` column) and a hash under the old fixed
// application salt. Opening it with the current code proves:
//   * Isar's additive schema migration opens the old DB cleanly;
//   * legacy rows read as salt-less and still verify against the static
//     salt (regression anchor: `_legacyHash` for `_legacyPassword`);
//   * a successful legacy verify migrates the row to a fresh per-entry
//     salt, and the migration survives a reopen.
// MemorySecretStore tests cover the service logic itself.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:firewood_core/firewood_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:firewood_desktop/src/data/isar_secret_store.dart';

class _MockPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _MockPathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

Future<void> _initIsarCore() async {
  final env = Platform.environment;
  final candidates = <String>[
    if (env['FIREWOOD_ISAR_LIB'] != null &&
        env['FIREWOOD_ISAR_LIB']!.isNotEmpty)
      env['FIREWOOD_ISAR_LIB']!,
    '${env['HOME']}/.pub-cache/hosted/pub.dev/isar_flutter_libs-3.1.0+1/linux/libisar.so',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) {
      await Isar.initializeIsarCore(libraries: {Abi.current(): path});
      return;
    }
  }
  throw StateError('libisar.so not found. Tried: $candidates');
}

/// Copies the pristine legacy fixture into a fresh temp dir (the test
/// migrates what it opens, so every run must start from the original).
Directory _copyFixture() {
  final src = Directory('test/fixtures/v027_legacy');
  final dst = Directory.systemTemp.createTempSync('v027_');
  for (final entity in src.listSync()) {
    final name = entity.uri.pathSegments.last;
    (entity as File).copySync('${dst.path}/$name');
  }
  return dst;
}

Future<void> _closeIsarIfOpen() async {
  try {
    final isar = Isar.getInstance('firewood_desktop');
    if (isar != null) await isar.close();
  } catch (_) {}
}

const _legacyPassword = 'legacy-duress-42';

/// base64(Argon2id(_legacyPassword, staticSalt)) — hash baked into the
/// fixture before the salt column existed. Anchors both the legacy
/// verification path and the value of `legacyStaticSalt`.
const _legacyHash = 'g2XtYpCZI+pMpAnANTctzAIh3ghQyHzyhDnIcsv2HGw=';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('V-027 legacy fixture (real Isar DB, pre-salt schema)', () {
    late Directory dir;

    setUp(() async {
      await _initIsarCore();
      await _closeIsarIfOpen();
      dir = _copyFixture();
      PathProviderPlatform.instance = _MockPathProvider(dir.path);
    });

    tearDown(() async {
      await _closeIsarIfOpen();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('legacy static salt formula is regression-anchored', () {
      expect(
        BurnerService.legacyStaticSalt,
        List<int>.generate(16, (i) => (i * 7 + 3) % 256),
        reason: 'changing this formula bricks verification of legacy rows',
      );
    });

    test('old DB opens under the new schema; legacy row reads salt-less',
        () async {
      await IsarSecretStore.initialize();
      final burners = await IsarSecretStore().getBurners();
      expect(burners, hasLength(1));
      expect(burners.first.passwordHash, _legacyHash);
      expect(burners.first.salt, isEmpty,
          reason: 'no salt column → static-salt fallback semantics');
      expect(burners.first.label, 'Legacy Burner');
      expect(burners.first.createdAt.toUtc(), DateTime.utc(2025, 6, 1),
          reason: 'Isar returns local-flagged DateTimes — compare instants');
    });

    test('legacy hash verifies once, migrates to per-entry salt, persists',
        () async {
      await IsarSecretStore.initialize();
      final store = IsarSecretStore();
      final service = BurnerService(store, VaultService(store));

      expect(await service.isBurnerPassword('wrong-password'), isFalse);
      expect(await service.isBurnerPassword(_legacyPassword), isTrue,
          reason: 'legacy static-salt rows must keep verifying');

      final migrated = (await store.getBurners()).first;
      expect(migrated.salt, hasLength(16),
          reason: 'first successful verify must assign a per-entry salt');
      expect(migrated.passwordHash, isNot(_legacyHash),
          reason: 're-hashed under the new salt — static-salt verifier gone');
      expect(migrated.label, 'Legacy Burner', reason: 'label preserved');

      // Re-open the same DB file: migration must be on disk, not in memory.
      final isar = Isar.getInstance('firewood_desktop');
      expect(isar, isNotNull);
      await isar!.close();
      await IsarSecretStore.initialize();

      final reopened = (await store.getBurners()).first;
      expect(reopened.salt, hasLength(16));
      expect(reopened.passwordHash, migrated.passwordHash);
      final service2 = BurnerService(store, VaultService(store));
      expect(await service2.isBurnerPassword(_legacyPassword), isTrue);
      expect(await service2.isBurnerPassword('wrong-password'), isFalse);
    });
  });

  group('V-027 per-entry salts (MemorySecretStore)', () {
    late MemorySecretStore store;
    late BurnerService service;

    setUp(() {
      store = MemorySecretStore();
      service = BurnerService(store, VaultService(store));
    });

    test('add → 16-byte salt; verify accepts right and rejects wrong',
        () async {
      expect(await service.addBurnerPassword('panic-code-one'), isTrue);
      final row = (await store.getBurners()).single;
      expect(row.salt, hasLength(16));
      expect(row.salt, isNot(BurnerService.legacyStaticSalt),
          reason: 'new rows must never use the fixed application salt');
      expect(await service.isBurnerPassword('panic-code-one'), isTrue);
      expect(await service.isBurnerPassword('panic-code-0ne'), isFalse);
    });

    test(
        'identical passwords hash differently across installs (no rainbow '
        'tables)', () async {
      await service.addBurnerPassword('shared-panic-code');

      // Second "installation": fresh store/service, same password.
      final otherStore = MemorySecretStore();
      final otherService = BurnerService(otherStore, VaultService(otherStore));
      await otherService.addBurnerPassword('shared-panic-code');

      final a = (await store.getBurners()).single;
      final b = (await otherStore.getBurners()).single;
      expect(a.salt, isNot(equals(b.salt)),
          reason: 'per-install salts differ — cross-target precomputation '
              'against the old fixed salt is impossible');
      expect(a.passwordHash, isNot(b.passwordHash));
      expect(await service.isBurnerPassword('shared-panic-code'), isTrue);
      expect(await otherService.isBurnerPassword('shared-panic-code'), isTrue);
    });

    test('salt-aware duplicate detection still rejects re-registration',
        () async {
      await service.addBurnerPassword('duplicate-code');
      expect(
        () => service.addBurnerPassword('duplicate-code'),
        throwsA(isA<BurnerException>()),
        reason: 'random salts make hash equality useless — duplicates must '
            'be detected by re-deriving under each row salt',
      );
    });

    test('legacy static-hash row verifies and migrates (memory path)',
        () async {
      final legacyHash = base64Encode(
        await (await CryptoService()
                .deriveKey('old-duress', BurnerService.legacyStaticSalt))
            .extractBytes(),
      );
      await store.putBurner(StoredBurner(
        id: 0,
        passwordHash: legacyHash,
        salt: const [],
        label: 'Legacy',
        createdAt: DateTime.utc(2025, 1, 1),
      ));

      expect(await service.isBurnerPassword('wrong'), isFalse);
      expect(await service.isBurnerPassword('old-duress'), isTrue);

      final migrated = (await store.getBurners()).single;
      expect(migrated.salt, hasLength(16));
      expect(migrated.passwordHash, isNot(legacyHash));
      expect(migrated.label, 'Legacy');
      expect(await service.isBurnerPassword('old-duress'), isTrue,
          reason: 'migrated row verifies under its own salt');
    });

    test('executeBurn/removeBurner surface unchanged', () async {
      await service.addBurnerPassword('removable-code');
      final row = (await store.getBurners()).single;
      await service.removeBurner(row.id);
      expect(await store.getBurners(), isEmpty);
      expect(await service.isBurnerPassword('removable-code'), isFalse);
    });
  });
}
