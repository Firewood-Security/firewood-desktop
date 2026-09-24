# firewood-desktop

Firewood desktop client for Linux, Windows and macOS.

## Layout

- the application lives at the repository root (`lib/`, `linux/`, `macos/`, `windows/`, `assets/`)
- `packages/firewood_design` — design tokens, colours, strings, theme
- `packages/firewood_ui_desktop` — desktop widgets (rail, title bar, buttons, dropdown, auth scaffold)
- `test/` — widget/layout tests

## Dependencies

- `firewood_core` (pinned git dependency, `ref: v0.1.0`) — encrypted container, vault and sharing services
- `window_manager` — window/tray management
- `flutter_blue_plus` — BLE share transport
- `hugeicons`, `isar`, `flutter_riverpod`, `cryptography`, `file_picker`

To develop against an unreleased core, add a git-ignored `pubspec_overrides.yaml`
with a `dependency_overrides` entry that points `firewood_core` at a local
checkout.

## Run

```bash
flutter pub get
flutter run -d linux      # or -d windows / -d macos
flutter test
```

## Package

Linux `snapcraft.yaml` is included; the desktop build targets `linux`, `windows`
and `macos`.
