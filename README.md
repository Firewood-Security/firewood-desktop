# firewood-desktop

Firewood desktop client (Linux, Windows, macOS) built on `firewood_core`.

## Layout

- app at the repository root (`lib/`, `linux/`, `macos/`, `windows/`)
- `packages/firewood_design` - design tokens, colours, strings, theme
- `packages/firewood_ui_desktop` - desktop widgets (rail, title bar, buttons)

`firewood_core` is consumed as a **pinned git dependency** (`v0.1.0`). For local
development, create `pubspec_overrides.yaml` (git-ignored) to point at a sibling
checkout:

```yaml
dependency_overrides:
  firewood_core:
    path: ../firewood-core
```

## Run

```bash
flutter pub get
flutter run -d linux     # or -d windows / -d macos
flutter test
```
