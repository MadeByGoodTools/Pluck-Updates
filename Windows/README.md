# Pluck for Windows

Pluck lives in the Windows system tray and offers a single Uninstall button. Eligible per-user apps installed beneath the user's Local AppData Programs folder use Pluck's guarded fast-removal path. MSI, service, driver, and system-level applications retain their registered Windows uninstaller because deleting their folder alone would leave Windows in a broken state. Its Reclaim view measures a conservative set of temporary, diagnostic, graphics, web, and developer caches; a single Purgeable Space checkbox selects that safe set.

Cleanup items go to the Recycle Bin. Passwords, browser profiles, documents, application settings, and credential stores are outside the scan roots.

The packaged Windows executable requests administrator access once at launch so actions do not repeatedly prompt. This uses the normal Windows UAC boundary and does not install a hidden privileged service.

Uninstall reliability is layered: Pluck recognizes MSI, Inno Setup, NSIS, Squirrel/Electron, MSIX, and ordinary registered uninstall commands; runs quiet removal first when supported; falls back to the vendor UI; closes processes from the app folder; processes selections sequentially; and verifies both the Windows registration and install location afterward. Diagnostic logs are written beneath `%LOCALAPPDATA%\\Pluck\\Logs`.

`pnpm test` covers uninstall-plan parsing and framework detection. The Windows release-check workflow runs those tests and produces the installer on a Windows-hosted runner before release.
