# firewood-desktop

Flutter desktop password manager for **Linux**, **Windows**, and **macOS** —
the same offline-first, zero-knowledge vault model as the mobile product,
packaged in a native desktop shell with a dedicated design system.

---

## Repository layout

```
firewood-desktop/
├── lib/                         Application source (Flutter)
│   └── src/                     Screens, services, providers, models
├── packages/
│   ├── firewood_design/         Design tokens: colours, typography, spacing, strings, theme
│   └── firewood_ui_desktop/     Desktop widget library: rail, title bar, buttons,
│                                dropdown, auth scaffold
├── assets/                      Icons, images, fonts
├── linux/                       Linux platform embedding (GTK)
├── macos/                       macOS platform embedding
├── windows/                     Windows platform embedding
├── test/                        Widget and layout tests
└── snapcraft.yaml               Snap packaging manifest (Linux)
```

---

## Packages

### `packages/firewood_design`

Design-system primitives shared across the desktop UI. Contains colour palette,
typography scale, spacing constants, localised strings, and `AppTheme` —
the single entry point for theming.

Nothing in `firewood_design` imports Flutter widgets; it is a pure Dart package
so it can be unit-tested without a widget environment.

### `packages/firewood_ui_desktop`

Desktop-specific widget library built on top of `firewood_design`. Provides:

| Widget | Purpose |
|---|---|
| `FwNavigationRail` | Collapsible sidebar rail with icon + label items |
| `FwTitleBar` | Custom window title bar with drag region and window controls |
| `FwButton` / variants | Primary, secondary, destructive, ghost, icon button styles |
| `FwDropdown` | Accessible, keyboard-navigable dropdown |
| `AuthScaffold` | Unlock / setup page scaffold with centred card layout |

---

## Key dependencies

| Package | Purpose |
|---|---|
| `firewood_core` | Encrypted container, vault service, item service, backup, sharing — pinned at `ref: v0.1.0` |
| `flutter_riverpod` | State management (mirrors the mobile state model) |
| `isar` | Local encrypted-field storage |
| `cryptography` | Argon2id, XChaCha20-Poly1305, HKDF — no custom primitives |
| `window_manager` | Window title, size, tray icon, always-on-top |
| `flutter_blue_plus` | BLE share transport (desktop where supported) |
| `file_picker` | Cross-platform file open/save dialogs |
| `hugeicons` | Icon set |

### Developing against an unreleased core

Add a git-ignored `pubspec_overrides.yaml` at the repository root:

```yaml
dependency_overrides:
  firewood_core:
    path: /path/to/local/firewood-core/framework-dart
```

This overrides the pinned `ref: v0.1.0` without touching `pubspec.yaml`.

---

## Getting started

```bash
flutter pub get
flutter analyze
flutter test
```

### Run on a specific platform

```bash
flutter run -d linux
flutter run -d windows
flutter run -d macos
```

### Run tests

```bash
flutter test
```

---

## Packaging

### Linux — Snap

```bash
snapcraft                    # builds the snap from snapcraft.yaml
sudo snap install firewood_*.snap --dangerous
```

The `snapcraft.yaml` at the repository root targets `linux`; it sets
`confinement: strict` and declares only the permissions the app requires.

### Windows

```bash
flutter build windows --release
```

The output under `build/windows/runner/Release/` can be wrapped with MSIX or
any Windows installer toolchain.

### macOS

```bash
flutter build macos --release
```

Notarisation and code-signing are handled separately via Xcode or `altool`.

---

## Platform notes

- **Linux:** downloads go to `~/Downloads/Firewood/`; the update endpoint uses
  the `linux` platform key. No platform-specific Dart code beyond the download
  directory selection.
- **Windows / macOS:** follow the same Dart code paths as Linux; platform
  embedding differences are isolated to the `linux/`, `windows/`, and `macos/`
  directories.
- **No iOS / Android code** lives in this repository.

---

## Design system conventions

- All colours and typography are consumed from `firewood_design` tokens.
  Hard-coded colour literals in widget code are a bug.
- `firewood_ui_desktop` widgets must not import application services. They
  receive data and callbacks as constructor parameters.
- `firewood_design` must not import Flutter widgets — keep it a plain Dart
  package so it can be tested without a widget environment.

