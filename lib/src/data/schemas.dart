// Isar collections for the desktop store. Ciphertext only for secrets.

import 'package:isar/isar.dart';

part 'schemas.g.dart';

@collection
class VaultRecord {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String vaultId;

  late String name;
  late List<int> salt;
  List<int>? verifierToken;
  List<int>? verifierNonce;
  late bool isDefault;
  late DateTime createdAt;
}

@collection
class ItemRecord {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
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
  late String label;
  late DateTime createdAt;
}
