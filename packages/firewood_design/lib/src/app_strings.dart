// Every user-facing string in one place. Start here for all copy; a later
// migration to ARB/flutter_localizations can wrap these keys.

class AppStrings {
  AppStrings._();

  // App
  static const String appName = 'Firewood';
  static const String hearthBadge = 'HEARTH';

  // Auth
  static const String createVault = 'Create Vault';
  static const String unlockVault = 'Unlock Vault';
  static const String masterPassword = 'Master Password';
  static const String confirmPassword = 'Confirm Master Password';
  static const String enterMasterPassword = 'Enter your master password';
  static const String setupSubtitle =
      'Choose a strong master password. It is never stored.';
  static const String unlockSubtitle =
      'Your vault is locked. Enter your master password.';
  static const String passwordRequired = 'Password required';
  static const String passwordsDoNotMatch = 'Passwords do not match';
  static const String passwordTooShort = 'Use at least 8 characters';
  static const String incorrectPassword = 'Invalid master password';
  static const String unlock = 'Unlock';
  static const String create = 'Create';

  // Navigation
  static const String dashboard = 'Dashboard';
  static const String vault = 'Vault';
  static const String generator = 'Generator';
  static const String settings = 'Settings';
  static const String sharing = 'Sharing';

  // Vault actions
  static const String newItem = 'New Item';
  static const String searchVault = 'Search vault items...';
  static const String noMatchingItems = 'No matching items';
  static const String vaultEmpty = 'Vault is Empty';
  static const String vaultEmptyHint =
      'Add your first password, card, key or note';
  static const String selectItem = 'Select an item';
  static const String selectItemHint =
      'Pick something from the list, or press Ctrl+K';
  static const String lockVault = 'Lock Vault';
  static const String deleteItem = 'Delete Item';
  static const String deleteItemConfirm = 'This action cannot be undone.';
  static const String cancel = 'Cancel';
  static const String delete = 'Delete';
  static const String save = 'Save';
  static const String edit = 'Edit';
  static const String copy = 'Copy';
  static const String copied = 'Copied to clipboard';

  // Filters / sorting
  static const String allCategories = 'All Categories';
  static const String newest = 'Newest';
  static const String oldest = 'Oldest';
  static const String list = 'List';
  static const String grid = 'Grid';

  // Item kinds
  static const String login = 'Login';
  static const String card = 'Card';
  static const String note = 'Note';
  static const String identity = 'Identity';
  static const String apiKey = 'API Key';

  // Command palette
  static const String commandHint = 'Search vault or run a command…';
  static const String noMatches = 'No matches';
  static const String goToDashboard = 'Go to Dashboard';
  static const String goToVault = 'Go to Vault';
  static const String goToGenerator = 'Go to Generator';
  static const String goToSettings = 'Go to Settings';
  static const String enterFocusMode = 'Enter focus mode';
  static const String exitFocusMode = 'Exit focus mode';

  // View options
  static const String densityComfortable = 'Comfortable';
  static const String densityCompact = 'Compact';

  // Cabinet / security
  static const String autoLock = 'Auto-Lock';
  static const String clipboardClear = 'Clipboard Auto-Clear';
  static const String biometricUnlock = 'Biometric Unlock';
  static const String burnerPassword = 'Burner Password';
  static const String exportVault = 'Export Encrypted Vault Backup';
  static const String importVault = 'Import Vault Backup File';
  static const String encryptFile = 'Encrypt File / Media';
  static const String openEncryptedFile = 'Open Encrypted File';

  // Generator
  static const String generatePassword = 'Generate Password';
  static const String passphrase = 'Passphrase';
  static const String password = 'Password';
  static const String regenerate = 'Regenerate';
  static const String strength = 'Strength';
  static const String totpSecret = 'TOTP Secret';

  // Errors / status
  static const String unexpectedError = 'An unexpected error occurred.';
  static const String unlockFirst = 'Unlock the vault first';
  static const String storagePermissionDenied =
      'Storage permission is required.';
}
