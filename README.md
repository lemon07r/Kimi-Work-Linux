# Kimi Work for Linux

Unofficial Linux x86_64 packaging for Kimi Work 3.1.3. This repository contains
only the reproducible porting and build tooling; it does not contain the source
DMG, extracted application, dependencies, or generated binaries.

Release: [`v3.1.3-linux.1`](https://github.com/lemon07r/Kimi-Work-Linux/releases/tag/v3.1.3-linux.1)

## Supported systems

The packages target 64-bit x86 Linux:

- Arch Linux and CachyOS through the Pacman package
- Other modern glibc-based distributions through the AppImage
- A portable `tar.gz` archive for manual installation

ARM64, 32-bit x86, musl-only distributions, and non-Linux hosts are not
supported by this build.

The port replaces the incompatible macOS platform layer with:

- Electron 41.7.2 for Linux x64
- Node.js 24.15.0 for Linux x64
- CPython 3.12.13 (python-build-standalone release 20260718)
- uv 0.11.29 for Linux x64
- Linux builds of the daemon and gateway native Node modules
- Kimi's Linux-specific `inside_install.sh` PPT tool bootstrap

## Install

Download an artifact and `SHA256SUMS` from the
[GitHub release](https://github.com/lemon07r/Kimi-Work-Linux/releases/tag/v3.1.3-linux.1).

Arch Linux or CachyOS:

```bash
sudo pacman -U Kimi-Work-3.1.3-linux-x64.pacman
```

AppImage:

```bash
sudo pacman -S fuse2 # Arch/CachyOS; use your distribution's FUSE 2 package
chmod +x Kimi-Work-3.1.3-linux-x86_64.AppImage
./Kimi-Work-3.1.3-linux-x86_64.AppImage
```

If FUSE 2 is unavailable, use the AppImage extraction fallback:

```bash
./Kimi-Work-3.1.3-linux-x86_64.AppImage --appimage-extract-and-run
```

Portable archive:

```bash
tar -xzf Kimi-Work-3.1.3-linux-x64.tar.gz
./Kimi-Work-3.1.3-linux-x64/kimi-work
```

Verify all downloaded files from the directory containing them:

```bash
sha256sum --check SHA256SUMS
```

## Build

Prerequisites:

- Linux x86_64
- [Bun](https://bun.sh/) 1.3 or newer and Node.js 24 or newer
- 7-Zip, `curl`, `file`, GNU `sha256sum`, and GNU `tar`
- A locally supplied `kimi_3.1.3.dmg`

The DMG must be the authorized Kimi Work 3.1.3 macOS distribution. It remains
local and is ignored by Git.

```bash
bun install --frozen-lockfile
bun run build
```

Use a different DMG path or prepare the Linux resource tree without packaging:

```bash
./scripts/build-linux.sh --dmg /path/to/kimi_3.1.3.dmg
./scripts/build-linux.sh --dmg /path/to/kimi_3.1.3.dmg --prepare-only
```

Artifacts and their freshly generated checksums are written to `dist/`.
Downloads made by the builder are version-pinned and SHA-256 verified.

The public build workflow is Bun-first. The builder retains the npm CLI bundled
with the target Node 24 runtime only when installing native application
dependencies, ensuring those addons are built for the exact runtime shipped in
the package.

## Verify

```bash
bun run check
bun audit
bun run verify
```

The verifier checks the bundled Node, Python, and uv runtimes; exercises SQLite
and PTY modules; imports gateway native modules; scans for Mach-O, ARM, and
other wrong-architecture binaries; validates the portable and Pacman package
metadata; and verifies every digest in `SHA256SUMS`.

## Limitations

- Kimi's macOS-only `kimi-webbridge` helper has no vendor Linux build and is
  omitted. Browser automation through Kimi WebBridge is therefore unavailable.
- This is an unofficial port and is not supported by Moonshot AI.
- Only Linux x86_64 is built and tested.
- The packages do not use Moonshot's macOS update feed. Install newer port
  releases from this repository manually.
- Kimi's normal online services, account login, and network access are still
  required for features that depend on them.

## Ownership, permission, and license

This port is distributed with written permission from Moonshot AI. Kimi Work,
the Kimi name and branding, the bundled application, and all associated
proprietary code and assets remain the property of Moonshot AI and their
respective owners. No ownership of those materials is claimed here.

The [MIT license](LICENSE) applies only to this repository's original Linux
porting, packaging, and verification tooling. It does not relicense Kimi Work
or any bundled third-party software.
