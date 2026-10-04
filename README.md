# filedirs

filedirs scans a directory tree and adds each folder that holds media files to EleBBS as a file area. It's useful for putting a big media library, such as a Jellyfin or Plex share, on your BBS without setting up hundreds of areas by hand.

It writes EleBBS 0.11b1 file areas straight into `FILES.RA` and `FILES.ELE`, and rebuilds `FILES.RDX` to match. It's written in Free Pascal and runs natively on Win32 and Linux.

## Download

Get the latest build from the [Releases page](https://github.com/martykazmaier/filedirs/releases).

| Platform | File |
|---|---|
| Windows (32-bit, runs on 64-bit too) | `filedirs-win32.zip` |
| Linux 32-bit (i386) | `filedirs-linux-i386.tar.gz` |
| Linux 64-bit (x86_64) | `filedirs-linux-x86_64.tar.gz` |
| Linux ARM 64-bit (arm64) | `filedirs-linux-arm64.tar.gz` |

## Quick start

Back up your EleBBS system directory first. filedirs makes `.bak` copies itself, but a full backup is cheap.

Do a dry run to see which areas would be added, without changing anything:

```
filedirs --elebbs-dir C:\ELE --dry-run D:\Media\Movies
```

If the list looks right, run it again without `--dry-run`:

```
filedirs --elebbs-dir C:\ELE D:\Media\Movies
```

Running it again later is safe. Folders that already have an area are skipped, so only new folders get added.

## How areas are named

The area name is the folder's path after the directory you scanned, tidied up:

- The scanned directory itself is left out. Scanning `\\192.168.0.6\Media\Anime` names a folder `Yuu Yuu Hakusho Complete Series\OVAs`, not the full UNC path.
- Anything in `(parentheses)` or `[brackets]` is removed, so `Akira (1988) [1080p]` becomes `Akira`.
- Anything after a hyphen is dropped, so `Cowboy Bebop - Complete Series` becomes `Cowboy Bebop`.

Use `--name-style leaf` to name each area with just the folder's own name.

## Long paths

EleBBS stores each area's path in a 40-character field, and many media folders have longer paths. filedirs handles this in two ways:

1. **Short (8.3) names.** On Windows, filedirs stores the folder's short name if it fits, such as `D:\MEDIA\MOVIES\AKIRA~1`.
2. **Symlinks.** If the path still doesn't fit, pass `--link-dir`. filedirs creates a short directory symlink for each of those folders, for example `C:\ELE\MEDIA\A00003`, and stores that path instead.

```
filedirs --elebbs-dir C:\ELE --link-dir C:\ELE\MEDIA \\192.168.0.6\Media\Anime
```

On Windows, creating symlinks needs admin rights or Developer Mode turned on. Without `--link-dir`, folders that don't fit are skipped and listed at the end of the run.

## Options

```
usage: filedirs [-h] [--elebbs-dir DIR] [--dry-run] [--name-style {leaf,relative}]
                [--no-backup] [--template-area N] [--security LEVEL]
                [--uppercase-paths] [--encoding CP] [--follow-symlinks]
                [--link-dir DIR] [--ext LIST] [--version] start_dir
```

| Option | What it does |
|---|---|
| `start_dir` | The directory to scan, including all its subfolders. |
| `--elebbs-dir DIR` | The EleBBS system directory holding `CONFIG.RA`, `FILES.RA` and `FILES.ELE`. If you leave it out, filedirs uses the current directory if it has `CONFIG.RA`, then the `ELEBBS`, `RA` or `ELE` environment variable, then `C:\ELE` on Windows. |
| `--dry-run` | Show the areas that would be added without writing anything. |
| `--ext LIST` | Comma-separated file extensions to look for, in any case, for example `--ext mkv,mp4,avi,m4v`. The default is `avi,mkv,mov,mp4,mpg`. |
| `--name-style {leaf,relative}` | `relative` (the default) names the area by its path after `start_dir`. `leaf` uses just the folder's own name. |
| `--link-dir DIR` | Create symlinks in `DIR` for folders whose path won't fit in 40 characters. See [Long paths](#long-paths). |
| `--template-area N` | Copy security, flags, group and other settings from existing area number `N`. |
| `--security LEVEL` | Download and list security level for new areas. The EleBBS default is 0. |
| `--uppercase-paths` | Store paths in upper case, DOS style. |
| `--encoding CP` | Code page for names and paths in the area records. The default is `cp437`, which is the only one built into the Linux build. |
| `--follow-symlinks` | Also scan inside symlinked directories. |
| `--no-backup` | Don't copy `FILES.RA`, `FILES.ELE` and `FILES.RDX` to `.bak` before writing. |
| `--version` | Show the version number. |
| `-h`, `--help` | Show help. |

## Building from source

You need [Free Pascal](https://www.freepascal.org/) 3.2.2.

On Windows, with the i386-win32 compiler on your `PATH`:

```
build.bat
```

On Linux (on Debian or Ubuntu, install `fp-compiler` and `fp-units-rtl` first):

```
sh build.sh
```

Either one puts `filedirs.exe` or `filedirs` in the project folder.

## Releases

GitHub Actions builds all four versions on every push to `main`. Pushing a version tag publishes them as a release:

```
git tag -a v0.2.1 -m "filedirs 0.2.1"
git push origin v0.2.1
```
