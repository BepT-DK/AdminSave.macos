# AdminSave — Nextpad++ plugin (macOS)

Saves files as administrator, with a Touch ID or password prompt.

Nextpad++ saves with your own rights, so a file owned by the system ends in a
save error and the job has to be finished with `sudo` in Terminal. With
AdminSave you just press Save.

## Features

- Works on the normal Save, Save As and Save All: no extra commands
- Asks only when a save is refused for lack of permission
- Touch ID when it is enabled for `sudo`, admin password otherwise
- Keeps the file's owner and permissions
- Asks again on every protected save: nothing is remembered

## Requirements

- Nextpad++ 1.1.3
- macOS 11 or later, Apple Silicon or Intel (tested on macOS 27.2, Apple Silicon)

### Touch ID

The fingerprint prompt appears only if Touch ID is enabled for `sudo`, which
macOS does not do by default. It needs this line in the PAM configuration:

```
auth       sufficient     pam_tid.so
```

- **macOS 14 and later:** put it in `/etc/pam.d/sudo_local`. The file does not
  exist at first; copy `/etc/pam.d/sudo_local.template` to that name and
  uncomment the line in it.
- **macOS 11 to 13:** add it as the first line of `/etc/pam.d/sudo`. System
  updates reset that file, so the line has to be added again after them.

Without it the plugin shows the system password dialog instead.

If you cancel the Touch ID prompt, the password dialog follows. Cancel that
too and the file is left unsaved; the editor shows its usual save error.

## Install

1. Quit Nextpad++.
2. Copy the `AdminSave` folder from the release archive to
   `~/Library/Application Support/Nextpad++/plugins/`, so that the plugin is at
   `plugins/AdminSave/AdminSave.dylib`.
3. Start Nextpad++. The plugin adds **Plugins → AdminSave → About**.

## Build from source

Needs the Xcode command line tools and CMake 3.20 or later. The build uses no
network.

```
cmake -S . -B build && cmake --build build
```

That produces `build/AdminSave.dylib`: universal (Apple Silicon and Intel),
macOS 11 or later, with the version recorded in the file.

```
ctest --test-dir build                    # self-check, no prompts
cmake --build build --target test-auth    # self-check of the admin save; three prompts (Touch ID or password)
cmake --install build                     # copy into the Nextpad++ plugins folder; quit Nextpad++ first
cmake --build build --target zip          # release archive in build/zip/
```

Layout: the plugin is `src/AdminSave.mm`, the self-check is `test/test.mm`,
and `vendor/` holds the Nextpad++ plugin interface header.

## How it works

Nextpad++ does not tell plugins that a save failed, so AdminSave wraps the
editor's own write method. The editor saves as usual; only when that fails for
lack of permission does the plugin write the document to a temporary file and
copy it over the target as root, in place, then compare the bytes.

Root access comes from `sudo` (Touch ID through `pam_tid`), with the system
password dialog as a fallback.

[SECURITY.md](SECURITY.md) lists everything the plugin executes, reads, writes
and stores. It makes no network connections.

## Known limitations

- The wrapped method is internal to Nextpad++ 1.1.3. If an update renames it,
  the plugin does nothing and saving behaves as it does without the plugin.
  A request for an official notification is open:
  [nextpad-plus-plus-macos#480](https://github.com/nextpad-plus-plus/nextpad-plus-plus-macos/issues/480).
- Files that even root cannot write (locked or protected by the system) are
  not saved; the editor shows its usual error.
- Save As into a protected folder creates a file owned by root.
- The file is rewritten in place, not replaced atomically as the editor's own
  save does. If the copy is interrupted (full disk, power loss), the file can
  be left incomplete.
- The root copy resolves the target path again, following symlinks. Do not use
  the plugin on files in folders that other users can write to.
- A file your account cannot read is written but then reported as failed,
  because the result is verified with your own rights.

## License

The plugin's own source code is under the MIT license, see [LICENSE](LICENSE).

`vendor/NppPluginInterfaceMac.h` is an unmodified copy of the plugin interface
header from [Nextpad++](https://github.com/nextpad-plus-plus/nextpad-plus-plus-macos),
Copyright (C) 2026 Andrey Letov. It remains under that project's license,
GPL-3.0; the full text is in [vendor/LICENSE](vendor/LICENSE).

Binary releases are built with that header, so they are distributed under the
terms of the GPL-3.0. The complete source is in this repository.
