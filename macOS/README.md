# Pluck

Pluck is a native macOS menu-bar utility from Good Tools. It has two focused jobs:

1. Uninstall an app together with related files that the user reviews first.
2. Reclaim real storage from Trash, caches, logs, and developer build data while showing how much additional space macOS can reclaim automatically.

Nothing is removed during a scan. App removal and cleanup items are moved to Trash so they remain recoverable. Emptying Trash is always a separate, explicitly confirmed action.

## Build

Run `./build.sh`. The locally signed application ZIP is written to the `dist` directory.

The project intentionally uses only Apple frameworks and has no network access or analytics.
