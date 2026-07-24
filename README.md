# Kimi Work for Linux

Unofficial Linux x86_64 packaging for Kimi Work 3.1.3. The Git repository
contains only the reproducible porting and build tooling. It does not track the
source DMG, extracted application, dependency trees, or generated artifacts.
The packaged AppImage, portable archive, Pacman package, and their checksums are
published separately as GitHub Release downloads.

Release: [`v3.1.3-linux.2`](https://github.com/lemon07r/Kimi-Work-Linux/releases/tag/v3.1.3-linux.2)

## Why I made this

I made this port because I wanted a way to use my free Kimi membership credits
on Linux.

Shameless self-plug: if this project is useful and you want to support me, use
[my Kimi referral link](https://kimi-bot.com/activities/viral-referral/share?scenario=invite&from=share_poster&invitation_code=HY39PH).
Kimi says we both get a guaranteed benefit, potentially up to one year of
membership credits. If you would rather use someone else's referral link,
that's fine too—you can still get free membership credits to use with Kimi
Work.

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
- Kimi WebBridge 1.11.3 for Linux x64
- Linux builds of the daemon and gateway native Node modules
- Kimi's Linux-specific `inside_install.sh` PPT tool bootstrap

## Install

Download an artifact and `SHA256SUMS` from the
[GitHub release](https://github.com/lemon07r/Kimi-Work-Linux/releases/tag/v3.1.3-linux.2).

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

The verifier checks the bundled Node, Python, uv, and WebBridge runtimes;
exercises SQLite and PTY modules; imports gateway native modules; scans for
Mach-O, ARM, and other wrong-architecture binaries; confirms the pinned
WebBridge digest in every package; validates the portable and Pacman package
metadata; and verifies every digest in `SHA256SUMS`.

## Browser control with Kimi WebBridge

WebBridge is optional for using Kimi Work, but it is required when you want
Kimi to control your browser. Install Moonshot's official
[Kimi WebBridge Chrome extension](https://chromewebstore.google.com/detail/kimi-webbridge/fldmhceldgbpfpkbgopacenieobmligc);
the bundled WebBridge 1.11.3 daemon is installed and supervised automatically
by Kimi Work. Moonshot's [manual setup page](https://www.kimi.com/features/webbridge)
has additional setup and troubleshooting instructions.

Browser control necessarily grants broad access. The extension can open pages,
click and type in them, and read website content using your existing browser
sessions. Its Chrome Web Store disclosure says it handles web history, user
activity, and website content. Install it only in a browser profile whose data
you are comfortable making available to Kimi-driven tasks, and review each task
before allowing sensitive or irreversible actions.

The vendor-provided WebBridge daemon also emits its own operational telemetry.
That behavior is part of Moonshot's binary rather than this Linux packaging
tooling; consult Moonshot's WebBridge information and privacy disclosures when
deciding whether to enable browser control.

## Limitations

- This is an unofficial port and is not supported by Moonshot AI.
- Only Linux x86_64 is built and tested.
- The packages do not use Moonshot's macOS update feed. Install newer port
  releases from this repository manually.
- Kimi's normal online services, account login, and network access are still
  required for features that depend on them.

## Project status and license

This is an independent community proof of concept for Linux compatibility and
a temporary stopgap until Moonshot AI provides an official Linux release. It is
not affiliated with, sponsored by, endorsed by, or supported by Moonshot AI. If
an official Linux build becomes available, prefer that version.

Kimi Work, Kimi WebBridge, the Kimi name and branding, and all associated
proprietary code and assets belong to Moonshot AI and their respective owners.
This project claims no ownership of those materials.

The [MIT license](LICENSE) applies only to this repository's original Linux
porting, packaging, and verification tooling. It does not grant rights to or
relicense Kimi Work, Kimi WebBridge, or any other bundled third-party software.
