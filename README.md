<div align="center">

# Firewood Desktop

**Offline-first, zero-knowledge password manager for Linux, Windows, and macOS.**  
Native Flutter desktop shell. No cloud accounts. No remote servers. No telemetry.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Windows%20%7C%20macOS-2ea44f.svg)](#supported-platforms)
[![Framework](https://img.shields.io/badge/Framework-Flutter%20Desktop-02569B.svg)](https://flutter.dev)
[![Crypto](https://img.shields.io/badge/Crypto-Argon2id%20%2B%20XChaCha20--Poly1305-orange.svg)](#security-and-crypto-architecture)
[![Download](https://img.shields.io/badge/Download-Release%20Binaries-brightgreen.svg)](https://firewoodsec.yahyaoncloud.com/download/)

</div>

---

## Overview

**Firewood Desktop** brings the same zero-knowledge, local-first security model of the Firewood vault to desktop operating systems. Packaged in a native desktop shell with a custom frameless window title bar and an accessible sidebar navigation rail, Firewood Desktop ensures your credentials never leave your physical workstation.

Your master password is never stored on disk. All credential fields are individually encrypted in RAM using **Argon2id** key derivation and **XChaCha20-Poly1305** AEAD before touching the local database.

---

## Key Features

- **Local Zero-Knowledge Storage**: Argon2id master key derivation (64 MiB RAM, 3 passes, 4 lanes). Field-level XChaCha20-Poly1305 encryption with fresh 24-byte CSPRNG nonces.
- **Native Frameless Desktop Shell**: Custom draggable title bar, window minimizing/maximizing/closing controls, and system tray integration via `window_manager`.
- **Collapsible Navigation Rail**: Fast keyboard-navigable switching between Logins, Payment Cards, Identities, Secure Notes, and API Keys.
- **P2P AirShare Sync**: Peer-to-peer encrypted vault payload transfer over Bluetooth Low Energy (BLE) without intermediate cloud brokers.
- **Password & Passphrase Generator**: Generate high-entropy randomized passwords, EFF diceware phrases, and PINs with visual strength analysis.
- **Encrypted Backups**: Export and import self-contained encrypted `.firewood` backups protected by an independent backup password.
- **Clipboard Safety**: Automatically cleanses copied credentials from the clipboard buffer after a short timeout.
- **In-App Updater**: Cryptographically verified HTTPS update checks against Ed25519-signed manifests.

---

## Supported Platforms & Downloads

Official pre-built releases are signed and published with verifiable SHA-256 checksums:

| Platform | Format | Architecture | Download |
|---|---|---|---|
| **Linux** | `.tar.gz` / Snap | `x86_64` | [Download Linux](https://firewoodsec.yahyaoncloud.com/download/#desktop) |
| **Windows** | `.zip` (Portable) | `x86_64` | [Download Windows](https://firewoodsec.yahyaoncloud.com/download/#desktop) |
| **macOS** | Native app | `Universal` | Build from source |

All official release binaries can also be found at the [Firewood Distribution Portal](https://firewoodsec.yahyaoncloud.com/download/).

### Verifying Checksums
After downloading an archive, verify its integrity:

```bash
# Linux
sha256sum firewood-latest-linux-x64.tar.gz

# Windows (PowerShell)
Get-FileHash firewood-latest-windows-x64.zip -Algorithm SHA256
```

---

## Repository Architecture & Packages

```
firewood-desktop/
├── lib/
│   └── src/                     Screens (unlock, setup, vault home, settings),
│                                providers (Riverpod), models, and local services
├── packages/
│   ├── firewood_design/         Design tokens: Dark Zinc palette, typography scale,
│   │                            spacing, strings, and AppTheme (pure Dart package)
│   └── firewood_ui_desktop/     Desktop widget primitives: custom FwTitleBar,
│                                FwNavigationRail, FwButton, FwDropdown, AuthScaffold
├── assets/                      Vector icons, brand graphics, and typography
├── linux/                       Linux GTK runner embedding
├── windows/                     Windows Win32 runner embedding
├── macos/                       macOS Cocoa runner embedding
├── test/                        Unit, widget, and layout tests
├── CONTRIBUTING.md               Contribution guidelines
├── SECURITY.md                   Vulnerability reporting and security model
└── snapcraft.yaml               Canonical Snap packaging manifest
```

### Design System Modularity
- **`packages/firewood_design`**: Contains design system primitives, color tokens, typography scales, and theme configuration. It has zero dependency on Flutter widgets and can be tested in pure Dart.
- **`packages/firewood_ui_desktop`**: Reusable desktop UI components built on top of `firewood_design`. Widgets do not import backend services directly; they receive state and callbacks via constructor parameters.

---

## Development & Building

### Prerequisites
- [Flutter SDK](https://flutter.dev) `3.47.5+` (pinned stable)
- [Dart SDK](https://dart.dev) matching Flutter
- Platform-specific build tools:
  - **Linux**: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `libsecret-1-dev`
  - **Windows**: Visual Studio 2022 with "Desktop development with C++"
  - **macOS**: Xcode with Command Line Tools

### Quickstart

1. **Install dependencies**:
   ```bash
   flutter pub get
   ```

2. **Run static analysis & format check**:
   ```bash
   dart format --output=none --set-exit-if-changed lib test packages
   flutter analyze lib/ --fatal-warnings --no-fatal-infos
   ```

3. **Run unit & widget tests**:
   ```bash
   flutter test test/ --reporter compact
   ```

4. **Run the desktop app locally**:
   ```bash
   # Linux
   flutter run -d linux

   # Windows
   flutter run -d windows

   # macOS
   flutter run -d macos
   ```

### Building Release Packages

#### Linux Tarball & Snap
```bash
# Build Linux release bundle
flutter build linux --release

# Build Snap package
snapcraft
sudo snap install firewood_*.snap --dangerous
```

#### Windows Release Zip
```bash
# Build Windows release runner
flutter build windows --release

# Output binary located at:
# build/windows/x64/runner/Release/
```

---

## Security & Threat Model

1. **Zero Knowledge**: Master keys exist strictly in volatile RAM and are never written to disk.
2. **Field-Level Isolation**: Each secret is individually encrypted with an Argon2id-derived 256-bit key and XChaCha20-Poly1305.
3. **No Cloud Dependency**: No telemetry, no remote databases, and no cloud synchronization services exist in the binary.
4. **AirShare P2P Transport**: Device-to-device credential sharing occurs over local BLE with payload encryption, ensuring credentials are never exposed in transit.

For full details or to report vulnerabilities, see [`SECURITY.md`](SECURITY.md).

---

## Contributing

We welcome contributions from the open-source community! Please review [`CONTRIBUTING.md`](CONTRIBUTING.md) for pull request guidelines, coding standards, and development workflows.

---

## License

This project is licensed under the [MIT License](LICENSE).
