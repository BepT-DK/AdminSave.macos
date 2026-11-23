# vendor/

Third-party files, kept byte for byte. Do not edit them.

- `NppPluginInterfaceMac.h` — the plugin interface header of
  [Nextpad++](https://github.com/nextpad-plus-plus/nextpad-plus-plus-macos),
  copied from `src/NppPluginInterfaceMac.h` at commit `1577e97` (v1.1.3).
  Copyright (C) 2026 Andrey Letov, GPL-3.0.
  SHA-256 `14bacfbb091cc3e96ff6c4b2a45edd5472e4cde80a2c06eab685f5cb716a09c4`.
- `LICENSE` — that project's `LICENSE` file, shipped because the GPL requires
  its text to accompany the header.

The header is copied so the plugin builds on its own, without the editor's
source tree next to it. When the host header changes, replace both files and
update the commit and checksum above.
