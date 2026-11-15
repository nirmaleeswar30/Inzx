# Shorebird OTA Setup

This project is configured for Shorebird Code Push across Android, Windows, and Linux (AppImage).

## What's Already Wired

- `shorebird_code_push: ^2.0.5` dependency in `pubspec.yaml`.
- `shorebird.yaml` exists (`app_id: caa5ffab-1c24-46a8-ba27-e2bca026e45d`) and is bundled in assets.
- App startup runs a background OTA check via `ShorebirdUpdateService.instance.checkForUpdates()`.
- Settings screen includes **Check for App Updates** for manual OTA + GitHub release checks.
- Build scripts support both standard Flutter releases and OTA-enabled Shorebird releases:
  - **Windows Installer**: `scripts/package_windows_installer.ps1` (with `-BuildType shorebird` or interactive selection)
  - **Linux AppImage**: `scripts/build_appimage.sh` (with `shorebird` or interactive selection)
  - **Android APK / AAB**: `shorebird release android` + `build_universal_apk.ps1` / `build_universal_apk.sh`

---

## Release Workflows (Base Builds)

Base releases create the initial binary containing the Shorebird updater runtime engine and register the release with Shorebird.

### 1. Android
```powershell
# Create release bundle and register release on Shorebird
shorebird release android

# Package universal & architecture-specific APKs
.\build_universal_apk.ps1
```

### 2. Windows Installer
```powershell
# Interactive (prompts choice):
.\scripts\package_windows_installer.ps1

# Or specify Shorebird release directly:
.\scripts\package_windows_installer.ps1 -BuildType shorebird

# Skip build if already compiled:
.\scripts\package_windows_installer.ps1 -SkipBuild
```
This produces `dist\windows\Inzx-Setup-<version>.exe` (and a copy `Inzx-Setup-<version>-Shorebird.exe`).

### 3. Linux AppImage
```bash
# Interactive (prompts choice):
bash scripts/build_appimage.sh

# Or specify Shorebird release directly:
bash scripts/build_appimage.sh shorebird
```
This produces `dist/Inzx-Linux-Shorebird-<version>-x86_64.AppImage` and standard `dist/Inzx-<version>-x86_64.AppImage`.

---

## Patch Workflows (OTA Updates)

After code changes, publish an instant Over-the-Air patch without rebuilding full installers:

### Android
```powershell
shorebird patch android
```

### Windows
```powershell
shorebird patch windows
```

### Linux
```bash
shorebird patch linux
```

---

## Important Notes

1. **Shorebird Release Requirement**: Shorebird patches are only delivered to apps installed from a Shorebird release build (`shorebird release <platform>`). Standard `flutter build` builds will report OTA as unavailable (`_updater.isAvailable == false`).
2. **Flutter Revision Parity**: All platforms for a given release version (e.g. `1.5.7+1`) must use the same Flutter engine revision. The scripts automatically query `shorebird releases list` to match the Flutter version used when the first platform was released.
3. **CI / Automation**: For automated Shorebird builds in GitHub Actions, define `SHOREBIRD_TOKEN` in repository secrets.
