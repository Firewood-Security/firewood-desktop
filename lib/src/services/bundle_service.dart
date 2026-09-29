import 'package:shared_preferences/shared_preferences.dart';

class BundleService {
  static const String _key = 'registered_credential_bundles_desktop';

  /// Loads all registered bundle names stored locally.
  static Future<List<String>> getRegisteredBundles() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  /// Registers a new bundle name.
  static Future<void> registerBundle(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = (prefs.getStringList(_key) ?? []).toList();
    if (!list.any((b) => b.trim().toLowerCase() == clean.toLowerCase())) {
      list.add(clean);
      await prefs.setStringList(_key, list);
    }
  }

  /// Renames an existing bundle.
  static Future<void> renameBundle(String oldName, String newName) async {
    final cleanOld = oldName.trim();
    final cleanNew = newName.trim();
    if (cleanNew.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = (prefs.getStringList(_key) ?? []).toList();
    final idx = list
        .indexWhere((b) => b.trim().toLowerCase() == cleanOld.toLowerCase());
    if (idx != -1) {
      list[idx] = cleanNew;
      await prefs.setStringList(_key, list);
    } else if (!list
        .any((b) => b.trim().toLowerCase() == cleanNew.toLowerCase())) {
      list.add(cleanNew);
      await prefs.setStringList(_key, list);
    }
  }

  /// Deletes a bundle registration.
  static Future<void> deleteBundle(String name) async {
    final clean = name.trim();
    final prefs = await SharedPreferences.getInstance();
    final list = (prefs.getStringList(_key) ?? []).toList();
    list.removeWhere((b) => b.trim().toLowerCase() == clean.toLowerCase());
    await prefs.setStringList(_key, list);
  }
}
