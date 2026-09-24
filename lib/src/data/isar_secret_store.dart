// Isar-backed [SecretStore] for desktop. Only ciphertext records are stored;
// the decrypted key lives in memory for the session.

import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'package:firewood_core/firewood_core.dart';

import 'schemas.dart';

class IsarSecretStore implements SecretStore {
  static late Isar _isar;

  static Future<void> initialize() async {
    final dir = await getApplicationSupportDirectory();
    _isar = await Isar.open(
      [VaultRecordSchema, ItemRecordSchema, BurnerRecordSchema],
      directory: dir.path,
      name: 'firewood_desktop',
    );
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
      isDefault: row.isDefault,
      createdAt: row.createdAt,
    );
  }

  @override
  Future<void> putVault(StoredVault vault) async {
    final row = VaultRecord()
      ..vaultId = vault.vaultId
      ..name = vault.name
      ..salt = vault.salt
      ..verifierToken = vault.verifierToken
      ..verifierNonce = vault.verifierNonce
      ..isDefault = vault.isDefault
      ..createdAt = vault.createdAt;
    await _isar.writeTxn(() => _isar.vaultRecords.put(row));
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
    final row = await _isar.itemRecords.filter().itemIdEqualTo(itemId).findFirst();
    return row == null ? null : _toItem(row);
  }

  @override
  Future<void> putItem(StoredItem item) async {
    final row = ItemRecord()
      ..itemId = item.itemId
      ..vaultId = item.vaultId
      ..encryptedData = item.encryptedData
      ..nonce = item.nonce
      ..type = item.type
      ..title = item.title
      ..updatedAt = item.updatedAt;
    await _isar.writeTxn(() => _isar.itemRecords.put(row));
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
              label: r.label,
              createdAt: r.createdAt,
            ))
        .toList();
  }

  @override
  Future<void> putBurner(StoredBurner burner) async {
    final row = BurnerRecord()
      ..passwordHash = burner.passwordHash
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
    await _isar.writeTxn(() async {
      await _isar.vaultRecords.clear();
      await _isar.itemRecords.clear();
      await _isar.burnerRecords.clear();
    });
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
