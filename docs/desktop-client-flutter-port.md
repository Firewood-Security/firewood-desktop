# Desktop Client → Flutter Port Plan

The Tauri desktop client (Rust + Svelte) is **parked, not deleted**: it lives on
`origin/main` under `tauri-app/` and was deliberately excluded from `main`/`dev`.
This document records **what it does** and **how to build the same product as a
Flutter desktop app** so no feature knowledge is lost.

Reference implementation (read-only):
`git show origin/main:tauri-app/src-tauri/src/<file>` and
`git ls-tree -r --name-only origin/main -- tauri-app/src`.

## 1. Feature inventory (from the Tauri tree)

| Area | Files | What it does |
|---|---|---|
| Transport abstraction | `transport/mod.rs` | `trait Transport { connect, listen, send, receive, disconnect }` over `async_trait` |
| Bluetooth LE | `transport/ble.rs`, `ble.rs` | BLE peer discovery + GATT byte pipe |
| LAN | `transport/lan.rs` | Local-network socket channel between peers |
| QR | `transport/qr.rs` | Payload transfer via QR encode/scan (air-gapped) |
| RFCOMM | `transport/rfcomm.rs` | Bluetooth serial (SPP) channel |
| USB | `transport/usb.rs` | USB serial channel |
| P2P session | `p2p.rs` | Handshake + **SAS** (short authentication string) so both users compare a code before trusting the link |
| Crypto | `crypto.rs` | Key agreement + authenticated encryption for the session |
| Vault/DB/Items | `vault.rs`, `database.rs`, `item.rs`, `models.rs` | Local vault storage and item model |
| Backup | `backup.rs` | `.firewood` container incl. a **magic header** for format detection |
| UI (Svelte) | `src/components/molecules/*` | `CategoryFilterChips`, `ConfirmModal`, `CopyableField`, `EmptyState`, `PasswordStrengthMeter`, `SearchInput`, `TotpDisplay` |

## 2. Target architecture: one Dart core, two shells

Do **not** port the Rust DB/crypto. The mobile app already implements the
compatible core in Dart; the desktop app must reuse it byte-for-byte so vaults,
backups and the update manifest stay interchangeable.

```
packages/firewood_core/        ← extract from lib/ (shared, pure Dart)
  security/crypto_service.dart     Argon2id + XChaCha20-Poly1305  (UNCHANGED)
  database/{schemas,isar_service}  Isar schemas + access           (UNCHANGED)
  services/{vault,item,backup,generator,lock}_service.dart         (UNCHANGED)
  services/peer/                   NEW: P2P + transports (below)
apps/
  mobile/   (current lib/) platform channels: FLAG_SECURE, Keystore, biometrics
  desktop/  new Flutter desktop shell + tray/hotkeys/autotype
```

Rationale: `crypto_service` and `backup_service` define the on-disk and
on-the-wire formats. Extracting them into a shared package makes a format
drift impossible; both shells then differ only in platform glue and UI.

## 3. Feature-by-feature port map

| Tauri piece | Flutter desktop equivalent | Notes |
|---|---|---|
| `Transport` trait | `abstract class PeerTransport { Future<void> connect(String peerId); Future<void> listen(); Future<void> send(List<int> d); Future<Uint8List> receive(); Future<void> disconnect(); }` | Keep the 1:1 shape so transport selection stays data-driven |
| `transport/lan.rs` | `RawDatagramSocket` (UDP multicast/broadcast) + `multicast_dns` for discovery | Same protocol as the Tauri version; reuse the LAN payload framing |
| `transport/ble.rs` | `flutter_blue_plus` | Windows/macOS support BLE; **Linux needs BlueZ** and is flaky — treat BLE as best-effort on desktop |
| `transport/qr.rs` | `qr_flutter` (render) + `zxing2`/`image` (decode from file/screen) or `mobile_scanner` with a webcam | Keep exactly the same chunking/framing as the Rust implementation so an old desktop client can still interop |
| `transport/rfcomm.rs` | Platform serial via `flutter_libserialport` (SPP over `/dev/rfcomm*` on Linux, COM ports on Windows) | RFCOMM is Android-centric; prefer BLE + LAN on desktop |
| `transport/usb.rs` | `flutter_libserialport` (USB-serial bridges) or `usb_serial` | Enumerate + open with the same baud/framing rules |
| `p2p.rs` handshake + SAS | Dart port: X25519 ECDH (`package:cryptography`), HKDF-SHA256, transcript hash → derive a 5-digit SAS from `HMAC(transcript, "firewood-sas")` | **Must be specified and implemented on both sides together.** SAS displayed on both devices; user confirms before any vault payload is accepted. Test vectors required (see §5) |
| `crypto.rs` | Reuse `lib/security/crypto_service.dart` (XChaCha20-Poly1305, Argon2id) | Do not introduce a second crypto stack |
| `vault.rs`/`database.rs`/`item.rs`/`models.rs` | Reuse Isar schemas/services from the shared package | Desktop picks its own Isar path; no schema change |
| `backup.rs` magic header | Implement the magic header in the **Dart** backup service first, then bump the container version on all platforms in one release | Format changes must be versioned + tested for backwards compatibility (see the existing `backup_negative_test.dart`) |
| Svelte molecules | Flutter widgets: `FilterChips`, `AlertDialog`, `CopyableField`, `EmptyState`, `PasswordStrengthMeter` (already exists), `SearchField`, `TotpDisplay` (already exists in mobile) | Prefer reusing the mobile widgets directly |

## 4. Desktop shell features (new, not in the Tauri app)

| Feature | Package | Notes |
|---|---|---|
| System tray + quick lock | `tray_manager` | Menu: Open / Lock now / Quit; lock clears the in-memory key like mobile |
| Global hotkey (lock, autotype) | `hotkey_manager` | e.g. `Ctrl+Shift+L` = lock; `Ctrl+Shift+A` = autotype |
| AutoType into other apps | `flutter_libserialport`-style FFI is **not** right here — use `autotype`-style key injection via `keyboard`-level FFI (`xdotool` on Linux/Wayland caveats, Win32 `SendInput`, macOS `CGEvent`) | Highest-risk feature; keep behind an opt-in setting and never type secrets without an explicit user action |
| Window/state | `window_manager`, `windows_single_instance` | Single instance + restore focus |
| Secure storage | `flutter_secure_storage` (Windows Credential Manager, macOS Keychain, libsecret) | Same wrapping-key pattern as Android Keystore (ADR-003) |
| Auto-update | Same `/update` manifest contract as mobile (`/v1/<platform>/update`) | Publish per-platform manifests from `tool/pipeline` |

## 5. Compatibility & security requirements (non-negotiable)

1. **One crypto stack**: all platforms use the shared Dart `crypto_service`
   (Argon2id, XChaCha20-Poly1305). No reimplementation.
2. **SAS before payload**: the P2P session must display a 5-digit SAS on both
   devices and require confirmation; reject mismatches. Publish test vectors so
   the mobile and desktop implementations can be checked against each other.
3. **No secrets on the wire in plaintext**; metadata-only exposure follows
   ADR-005 (accepted, documented). QR transfers are treated as public — encrypt
   before encoding.
4. **Backup format**: magic header + version, with a strict rejection path and
   cross-platform round-trip tests (mobile↔desktop).
5. **No telemetry**, offline-first, same as mobile.

## 6. Delivery plan (phases)

1. **Extract `packages/firewood_core`** from `lib/` (no behaviour change;
   mobile keeps building). Gate: `flutter test` green on both shells.
2. **Desktop shell**: window, vault unlock, item list/detail, generator, settings
   — reuse `lib/screens` where platform-neutral.
3. **LAN transport + SAS** (simplest transport first), with interop tests
   against a scripted peer.
4. **BLE / QR / USB-serial**, each behind the `PeerTransport` interface, adding
   platform capability detection and graceful degradation.
5. **Tray, hotkeys, AutoType, updates**, then packaging: Windows MSIX/Inno,
   macOS DMG (notarised), Linux AppImage + `.deb`/`.rpm` (reuse the patterns in
   `origin/main:.github/workflows/release.yml`, rewritten for Flutter desktop).

## 7. Where the original work lives

```bash
# browse the parked implementation
git show origin/main:tauri-app/src-tauri/src/p2p.rs
git show origin/main:tauri-app/src-tauri/src/transport/mod.rs
git ls-tree -r --name-only origin/main -- tauri-app/src/components/molecules
# the Tauri desktop release workflow (build matrix for linux/windows/macos)
git show origin/main:.github/workflows/release.yml
```

If the desktop client is dropped permanently, remove `tauri-app` from
`origin/main` history in a dedicated commit and delete this document’s reference
section — but keep §2–§5: they are the compatibility contract for future
platforms (iOS share extension, browser bridge).
