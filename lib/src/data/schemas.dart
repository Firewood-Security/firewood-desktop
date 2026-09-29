// Isar collections for the desktop store. Ciphertext only for secrets.
// V-009: `ItemRecord.title`/`type` are legacy read-fallback columns — core
// writers always store '' and keep metadata inside `encryptedData`; vault
// bootstrap material (salt/verifier/wrappedMEK) must stay readable pre-unlock.

import 'package:isar/isar.dart';

part 'schemas.g.dart';

@collection
class VaultRecord {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String vaultId;

  late String name;
  late List<int> salt;
  List<int>? verifierToken;
  List<int>? verifierNonce;
  List<int>? wrappedMekToken;
  List<int>? wrappedMekNonce;
  int version = 1;
  late bool isDefault;
  late DateTime createdAt;
}

@collection
class ItemRecord {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String itemId;

  @Index()
  late String vaultId;

  late List<int> encryptedData;
  late List<int> nonce;
  late String type;
  late String title;
  late DateTime updatedAt;
}

@collection
class BurnerRecord {
  Id id = Isar.autoIncrement;
  late String passwordHash;

  /// V-027: per-entry Argon2id salt. Null/absent on legacy rows, which were
  /// hashed under the old fixed application salt (verify-only fallback).
  List<int>? salt;

  late String label;
  late DateTime createdAt;
}
