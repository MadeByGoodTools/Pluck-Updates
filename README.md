# Pluck

Pluck is a focused app uninstaller and storage-reclaim utility by Good Tools.

- **macOS:** lives in the menu bar, lists installed apps and related files, and shows concrete safe reclaim candidates alongside macOS purgeable space.
- **Windows:** lives in the taskbar tray, lists installed apps, uses guarded direct removal where it is safe, and falls back to registered uninstallers for complex apps.
- **Careful cleanup:** ordinary cleanup excludes passwords, browser profiles, documents, application settings, and credential stores.

## Downloads

Use the latest GitHub release for the Good Tools installer packages.

The current public beta installers are unsigned. macOS and Windows may show a security warning until release signing is added.

## Source layout

- `macOS/` — native Swift and AppKit menu-bar app
- `Windows/` — Electron taskbar app

Pluck is an original Good Tools implementation. It does not include AppCleaner source code.
