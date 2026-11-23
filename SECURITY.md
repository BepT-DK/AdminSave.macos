# Security

AdminSave runs a command as root on your behalf. This file lists everything
the plugin executes, reads, writes, stores and connects to.

## Network

None. The plugin opens no network connections and contains no networking code.

## When it acts

Only when a save in Nextpad++ has already failed and `access()` reports
`EACCES` for the file or its folder. A save that succeeds, or fails for any
other reason, is left to the editor. The editor's autosave and backups do not
go through the plugin, so it never acts on its own: every prompt follows a
save the user started.

## What it executes

Two programs, both by absolute path, never looked up through `PATH`:

1. **`sudo`**, for the Touch ID route:

   ```
   /usr/bin/sudo -k -S -p '' -- /bin/sh -c '/bin/cp "$1" "$2" || exit 3' sh <temporary file> <target file>
   ```

   - The two paths are positional arguments of a fixed script. No document
     text and no path ever becomes part of the script.
   - `-k`: sudo neither uses nor updates cached credentials, so each protected
     save asks again.
   - `-S` with stdin, stdout and stderr on `/dev/null`: when Touch ID is not
     enabled for sudo, or is cancelled, sudo cannot read a password and exits.
   - The editor's environment is passed to sudo, which resets it under its
     default policy (`env_reset`).

2. **`/bin/cp <temporary file> <target file>`** as root through
   `AuthorizationExecuteWithPrivileges`, only when sudo did not authenticate.
   macOS shows its own password dialog. The authorization is created for that
   one copy and destroyed right after it
   (`AuthorizationFree(…, kAuthorizationFlagDestroyRights)`), so it is not
   reused by a later save.

Nothing else is executed.

## What it reads and writes

- **Temporary file.** The document is written to a file with a random UUID name
  in the user's temporary directory (`NSTemporaryDirectory()`, mode 0700),
  read back, copied over the target as root and then deleted.
- **Target file.** Overwritten in place by `cp`; its owner and permissions are
  kept. The plugin then reads it back with the user's own rights and compares
  it with the bytes it meant to write.
- **System log.** Through `NSLog`, for each protected save: the file path with
  the outcome, and a line when the password dialog replaces Touch ID. One more
  line at start-up if the editor's save method was not found.

## What it stores

Nothing. No settings, no cache, no credentials. The password and the
fingerprint are handled by macOS (`sudo`, PAM, the system password dialog);
the plugin never sees them.

## How it hooks into the editor

Nextpad++ 1.1.3 sends plugins no notification for a failed save, so the plugin
replaces, at run time, the implementation of the editor's private method
`-[EditorView _writeContentsToPath:error:]`. The replacement calls the original
first. No file of the editor is modified; the original implementation is put
back when the plugin is unloaded; if the method is not found the plugin does
nothing. A request for an official notification is open:
[nextpad-plus-plus-macos#480](https://github.com/nextpad-plus-plus/nextpad-plus-plus-macos/issues/480).

## Known limits

- A process running as the same user can change the temporary file while the
  prompt is up. The save is then reported as failed, because the bytes are
  compared, but root has already copied the changed file. Such a process can
  equally replace the plugin itself, which lives in a user-writable folder.
- The root copy resolves the target path again and follows symlinks. Do not
  use the plugin on files in folders that other users can write to.
- The rewrite is not atomic: an interrupted copy can leave the file incomplete.

## Reporting a problem

Please open an issue in this repository.
