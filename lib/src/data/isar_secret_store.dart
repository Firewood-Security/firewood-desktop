// Isar-backed [SecretStore] for desktop. Only ciphertext records are stored;
// the decrypted key lives in memory for the session.
//
// V-009: the data directory is locked to 0700 and every file in it to 0600 at
// startup (and after every reopen) — Isar files are created umask-derived
// (0644 on default homes) and would otherwise be readable by other local
// users. Item titles/types are never written to plaintext columns by any
// core writer (the columns exist only as a read-fallback for legacy rows;
// core re-blanks them via migrateVaultToZeroKnowledge on every unlock).

import 'dart:io';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'package:firewood_core/firewood_core.dart';

import 'schemas.dart';

class IsarSecretStore implements SecretStore {
  static late Isar _isar;

  static Future<void> initialize() async {
    final existing = Isar.getInstance('firewood_desktop');
    if (existing != null) {
      _isar = existing;
      return;
    }
    final dir = await getApplicationSupportDirectory();
    _isar = await Isar.open(
      [VaultRecordSchema, ItemRecordSchema, BurnerRecordSchema],
      directory: dir.path,
      name: 'firewood_desktop',
    );
    await _securePermissions(dir);
  }

  /// V-009: chmod 700 on the data directory, 600 on every file inside it.
  static Future<void> _securePermissions(Directory dir) async {
    if (!Platform.isLinux && !Platform.isMacOS) return;
    try {
      final dirRes = Process.runSync('chmod', ['700', dir.path]);
      if (dirRes.exitCode != 0) return;
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is File) {
          Process.runSync('chmod', ['600', entity.path]);
        }
      }
    } catch (_) {
      // Best effort — never block startup on a permission pass.
    }
  }

  @override
  Future<StoredVault?> getVault() async {
    final row = await _isar.vaultRecords.where().findFirst();
    if (row == null) return null;
    return StoredVault(
      vaultId: row.vaultId,
      name: row.name,
      salt: row.salt,
      verifierToken: row.verifierToken,
      verifierNonce: row.verifierNonce,
      wrappedMekToken: row.wrappedMekToken,
      wrappedMekNonce: row.wrappedMekNonce,
      version: row.version,
      isDefault: row.isDefault,
      createdAt: row.createdAt,
    );
  }

  @override
  Future<void> putVault(StoredVault vault) async {
    final existing = await _isar.vaultRecords
        .filter()
        .vaultIdEqualTo(vault.vaultId)
        .findFirst();
    final row = VaultRecord()
      ..id = existing?.id ?? Isar.autoIncrement
      ..vaultId = vault.vaultId
      ..name = vault.name
      ..salt = vault.salt
      ..verifierToken = vault.verifierToken
      ..verifierNonce = vault.verifierNonce
      ..wrappedMekToken = vault.wrappedMekToken
      ..wrappedMekNonce = vault.wrappedMekNonce
      ..version = vault.version
      ..isDefault = vault.isDefault
      ..createdAt = vault.createdAt;
    await _isar.writeTxn(() => _isar.vaultRecords.putByVaultId(row));
  }

  @override
  Future<void> deleteVault() async {
    await _isar.writeTxn(() => _isar.vaultRecords.clear());
  }

  @override
  Future<List<StoredItem>> getItems() async {
    final rows = await _isar.itemRecords.where().findAll();
    return rows.map(_toItem).toList();
  }

  @override
  Future<StoredItem?> getItem(String itemId) async {
    final row =
        await _isar.itemRecords.filter().itemIdEqualTo(itemId).findFirst();
    return row == null ? null : _toItem(row);
  }

  @override
  Future<void> putItem(StoredItem item) async {
    final existing =
        await _isar.itemRecords.filter().itemIdEqualTo(item.itemId).findFirst();
    final row = ItemRecord()
      ..id = existing?.id ?? Isar.autoIncrement
      ..itemId = item.itemId
      ..vaultId = item.vaultId
      ..encryptedData = item.encryptedData
      ..nonce = item.nonce
      ..type = item.type
      ..title = item.title
      ..updatedAt = item.updatedAt;
    await _isar.writeTxn(() => _isar.itemRecords.putByItemId(row));
  }

  @override
  Future<void> deleteItem(String itemId) async {
    await _isar.writeTxn(
      () => _isar.itemRecords.filter().itemIdEqualTo(itemId).deleteAll(),
    );
  }

  @override
  Future<List<StoredBurner>> getBurners() async {
    final rows = await _isar.burnerRecords.where().findAll();
    return rows
        .map((r) => StoredBurner(
              id: r.id,
              passwordHash: r.passwordHash,
              // V-027: null on legacy rows (pre-per-entry-salt schema).
              salt: r.salt ?? const [],
              label: r.label,
              createdAt: r.createdAt,
            ))
        .toList();
  }

  @override
  Future<void> putBurner(StoredBurner burner) async {
    final row = BurnerRecord()
      ..id = burner.id == 0 ? Isar.autoIncrement : burner.id
      ..passwordHash = burner.passwordHash
      ..salt = burner.salt.isEmpty ? null : burner.salt
      ..label = burner.label
      ..createdAt = burner.createdAt;
    await _isar.writeTxn(() => _isar.burnerRecords.put(row));
  }

  @override
  Future<void> deleteBurner(int id) async {
    await _isar.writeTxn(() => _isar.burnerRecords.delete(id));
  }

  @override
  Future<void> clearAll() async {
    // V-009: delete the database FILES — a row-level clear() leaves page slack
    // behind (old titles/hashes stay recoverable in freed pages). Close first
    // so the open handle cannot resurrect content, then reopen an empty DB so
    // the store stays usable for the subsequent re-setup.
    final dir = await getApplicationSupportDirectory();
    await _isar.close();
    try {
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.endsWith('.isar') || name.endsWith('.isar.lock')) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    _isar = await Isar.open(
      [VaultRecordSchema, ItemRecordSchema, BurnerRecordSchema],
      directory: dir.path,
      name: 'firewood_desktop',
    );
    await _securePermissions(dir);
  }

  StoredItem _toItem(ItemRecord r) => StoredItem(
        itemId: r.itemId,
        vaultId: r.vaultId,
        encryptedData: r.encryptedData,
        nonce: r.nonce,
        type: r.type,
        title: r.title,
        updatedAt: r.updatedAt,
      );
}
