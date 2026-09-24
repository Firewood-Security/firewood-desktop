// Desktop app providers: services are thin wirings over firewood_core.

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_design/firewood_design.dart';

import 'data/isar_secret_store.dart';
import 'services/ble_share_transport.dart';

final secretStoreProvider = Provider<SecretStore>((ref) => IsarSecretStore());

final vaultServiceProvider = Provider<VaultService>(
  (ref) => VaultService(ref.watch(secretStoreProvider)),
);

final itemServiceProvider = Provider<ItemService>(
  (ref) => ItemService(ref.watch(secretStoreProvider)),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(secretStoreProvider)),
);

final fileCryptoServiceProvider = Provider<FileCryptoService>(
  (ref) => FileCryptoService(),
);

/// In-memory session key. null = locked. Never persisted.
final authProvider = StateProvider<SecretKey?>((ref) => null);

/// Active desktop section: 0 dashboard, 1 vault, 2 generator, 3 settings.
final desktopTabProvider = StateProvider<int>((ref) => 0);

/// Command palette visibility.
final commandPaletteOpenProvider = StateProvider<bool>((ref) => false);

/// Currently selected vault item (master-detail detail pane).
final selectedItemIdProvider = StateProvider<String?>((ref) => null);

/// Auto-lock settings (desktop).
final autoLockEnabledProvider = StateProvider<bool>((ref) => true);
final autoLockMinutesProvider = StateProvider<int>((ref) => 5);

/// Clipboard auto-clear on lock.
final clipboardClearProvider = StateProvider<bool>((ref) => true);

/// App accent colour (desktop).
final accentColorProvider = StateProvider<Color>((ref) => AppColors.orangeAccent);

/// Burner / duress passwords.
final burnerServiceProvider = Provider<BurnerService>(
  (ref) => BurnerService(ref.watch(secretStoreProvider), ref.watch(vaultServiceProvider)),
);

/// Bluetooth sharing.
final sharingServiceProvider = Provider<SharingService>((ref) => SharingService());
final bluetoothTransportProvider =
    Provider<ShareTransport>((ref) => BleShareTransport());
final bluetoothEnabledProvider = StateProvider<bool>((ref) => false);
