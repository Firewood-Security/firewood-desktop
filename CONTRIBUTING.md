# Contributing to Firewood Desktop

Thank you for your interest in contributing to **Firewood Desktop**! We welcome bug fixes, desktop UX improvements, platform enhancements, and documentation updates.

---

## Code of Conduct

Please maintain a respectful, welcoming, and constructive environment in all issues, pull requests, and discussions.

---

## Architectural Principles

1. **Zero Knowledge & Local Security**:
   - Master passwords and decrypted keys must **never** be persisted to disk, printed to console logs, or leaked outside memory.
   - All credential fields must be encrypted using `CryptoService` before being written to Isar.
2. **Design System Separation**:
   - `packages/firewood_design` is a pure Dart package containing color tokens, typography, and spacing. Do not add Flutter widget imports to it.
   - `packages/firewood_ui_desktop` contains reusable desktop widgets. Widgets should not import application services directly; pass data and callbacks via constructors.
3. **KISS & Simplicity**:
   - Keep widget trees readable, avoid deep nesting, and favor clean modular code.
4. **No Telemetry**:
   - Do not introduce analytics SDKs, trackers, or remote telemetry.

---

## Development Workflow

### 1. Prerequisites
- [Flutter SDK](https://flutter.dev) `3.47.5+`
- Desktop development tools:
  - Linux: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `libsecret-1-dev`
  - Windows: Visual Studio 2022 with C++ desktop workload
  - macOS: Xcode

### 2. Local Setup
```bash
git clone https://github.com/Firewood-Security/firewood-desktop.git
cd firewood-desktop
flutter pub get
```

### 3. Code Standards & Style
- **Format check**:
  ```bash
  dart format lib test packages
  ```
- **Static analysis**:
  ```bash
  flutter analyze lib/ --fatal-warnings --no-fatal-infos
  ```
- **Tests**:
  ```bash
  flutter test test/ --reporter compact
  ```

### 4. Submitting a Pull Request
1. Fork the repository and create a branch from `main`:
   ```bash
   git checkout -b fix/window-drag-region
   ```
2. Commit your changes with clear, descriptive messages.
3. Push to your fork and submit a PR against `main`.
4. Ensure all CI verification checks are green.

---

## Reporting Issues

- **Bug Reports**: Open an issue on GitHub describing the platform (Linux distro / Windows version / macOS), steps to reproduce, and logs. Redact any private credentials.
- **Security Vulnerabilities**: Do **not** disclose security vulnerabilities publicly. Follow the instructions in [`SECURITY.md`](SECURITY.md).
