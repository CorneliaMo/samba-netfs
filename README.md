# SambaNetFS

`SambaNetFS` is a macOS command-line tool for mounting SMB/Samba shares through Apple's user-space NetFS APIs.

The executable is named `mount-samba`. It has no GUI, reads one JSON config file per share, can mount all configured shares once, can keep polling and remounting shares, and can report current mount status.

## Features

- Mount SMB/Samba shares with `NetFS.framework`
- Store passwords in the macOS Keychain
- Keep share configs as simple JSON files
- Mount every configured share in a single command
- Run a foreground polling loop for automatic mounting
- Start, stop, and inspect a lightweight background daemon
- Show mount status as a table or JSON

## Requirements

- macOS 13 or later
- Swift 5.9 or later

Real mounting and Keychain access are macOS-only because the project links `NetFS.framework` and `Security.framework`.

## Build

```sh
swift build
swift test
```

Run from source:

```sh
swift run mount-samba show
```

Install the release build somewhere on your `PATH`:

```sh
swift build -c release
cp .build/release/mount-samba /usr/local/bin/mount-samba
```

## Configuration

By default, configs are read from:

```text
~/.config/mount-samba-swift
```

Commands that read configs accept `--config-dir`:

```sh
mount-samba show --config-dir /path/to/configs
mount-samba mount --config-dir /path/to/configs
mount-samba run --config-dir /path/to/configs
```

Create one `.json` file per Samba share:

```json
{
  "$schema": "https://raw.githubusercontent.com/CorneliaMo/samba-netfs/master/schemas/samba-config.schema.json",
  "name": "Media NAS",
  "host": "nas.local",
  "share": "media",
  "path": "optional/subdir",
  "pollIntervalSeconds": 60,
  "mountPoint": "/Volumes/MediaNAS",
  "account": "alice"
}
```

Required fields:

- `name`: friendly display name
- `host`: SMB server host name or IP address
- `share`: SMB share name
- `pollIntervalSeconds`: per-share polling interval for `run` and `start`
- `mountPoint`: local directory used as the mount point

Optional fields:

- `path`: subdirectory inside the share
- `account`: Keychain account name

If `account` is omitted, `mount-samba` does not pass credentials to NetFS and relies on guest or anonymous SMB behavior.

An example config is available at [`examples/media-nas.json`](examples/media-nas.json).

The JSON Schema is available at [`schemas/samba-config.schema.json`](schemas/samba-config.schema.json). Use the schema URL in your configs if your editor supports JSON Schema validation:

```json
{
  "$schema": "https://raw.githubusercontent.com/CorneliaMo/samba-netfs/master/schemas/samba-config.schema.json"
}
```

## Credentials

Passwords are stored in the macOS Keychain, never in config files.

```sh
mount-samba set-credential --host nas.local --share media --account alice
```

The Keychain service key is:

```text
mount-samba-swift:<host>/<share>
```

The Keychain account is the `account` value from the config file.

## Commands

Show all configs and mount status:

```sh
mount-samba show
mount-samba show --json
```

Mount every configured share once:

```sh
mount-samba mount
```

Run a foreground polling loop:

```sh
mount-samba run
```

Start, stop, and inspect the built-in background daemon:

```sh
mount-samba start
mount-samba status
mount-samba stop
```

Daemon files are stored under:

```text
~/Library/Caches/mount-samba-swift/
```

The daemon writes:

- `mount-samba.pid`
- `mount-samba.log`

## Behavior

- Missing mount point directories are created automatically.
- Already mounted mount points are skipped.
- A failed share does not stop other shares from being checked or mounted.
- In polling mode, each config is retried according to its own `pollIntervalSeconds`.
- NetFS UI prompts are disabled so the tool can run unattended.

## Development Notes

The test target uses fakes for Keychain, NetFS, and mount status checks. Real SMB mounting still needs manual verification on macOS with a reachable SMB server.

Useful checks:

```sh
swift test
swift build
```
