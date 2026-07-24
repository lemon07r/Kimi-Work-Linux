#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES="$PROJECT_DIR/build/linux-resources"
RESOURCES_ONLY=false
WEBBRIDGE_SHA256="5f89a15b6dcffa3c88837d3a8fab073fa8499a17f2cbe27f32d428c540f4b418"

if [ "$#" -gt 1 ]; then
  printf 'Usage: %s [--resources-only]\n' "$0" >&2
  exit 2
fi
if [ "$#" -eq 1 ]; then
  if [ "$1" != "--resources-only" ]; then
    printf 'Unknown argument: %s\n' "$1" >&2
    printf 'Usage: %s [--resources-only]\n' "$0" >&2
    exit 2
  fi
  RESOURCES_ONLY=true
fi

fail() {
  printf '[verify] ERROR: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf '[verify] PASS: %s\n' "$*"
}

assert_x86_64_elf() {
  local binary="$1"
  local description="$2"
  file "$binary" | grep -Eq 'ELF 64-bit.*x86-64' ||
    fail "$description is not a Linux x86_64 ELF binary"
}

[ -d "$RESOURCES" ] || fail "Linux resources have not been prepared"

NODE_BIN="$RESOURCES/runtime/node"
PYTHON_BIN="$RESOURCES/daimon-bundle/runtime/python/cpython-3.12/bin/python3.12"
UV_BIN="$RESOURCES/daimon-bundle/runtime/uv/uv"
WEBBRIDGE_BIN="$RESOURCES/kimi-webbridge"
DAIMON_DIR="$RESOURCES/daimon-bundle/app/daimon"
GATEWAY_DIR="$RESOURCES/gateway"

[ "$("$NODE_BIN" --version)" = "v24.15.0" ] || fail "Wrong Node runtime"
"$PYTHON_BIN" -c 'import sys; assert sys.version_info[:3] == (3, 12, 13)'
"$UV_BIN" --version | grep -q '^uv 0\.11\.29' || fail "Wrong uv runtime"
assert_x86_64_elf "$NODE_BIN" "Node runtime"
assert_x86_64_elf "$PYTHON_BIN" "Python runtime"
assert_x86_64_elf "$UV_BIN" "uv runtime"
pass "Node, Python, and uv runtimes execute natively"

[ -x "$WEBBRIDGE_BIN" ] || fail "Kimi WebBridge is missing or not executable"
[ "$(sha256sum "$WEBBRIDGE_BIN" | cut -d ' ' -f 1)" = "$WEBBRIDGE_SHA256" ] ||
  fail "Kimi WebBridge does not match the pinned v1.11.3 digest"
assert_x86_64_elf "$WEBBRIDGE_BIN" "Kimi WebBridge"
file "$WEBBRIDGE_BIN" | grep -q 'statically linked' ||
  fail "Kimi WebBridge is not statically linked"
"$WEBBRIDGE_BIN" --help | grep -q '^Kimi WebBridge daemon and toolkit$' ||
  fail "Kimi WebBridge CLI failed to load"
pass "Kimi WebBridge v1.11.3 is pinned, static, executable, and loadable"

"$NODE_BIN" -e \
  'const db = require(process.argv[1]); const d = new db(":memory:"); console.log(d.prepare("select 1 as ok").get().ok); d.close()' \
  "$DAIMON_DIR/node_modules/better-sqlite3" | grep -qx 1 ||
  fail "better-sqlite3 native module failed"
"$NODE_BIN" -e \
  'const pty = require(process.argv[1]); const p = pty.spawn("/bin/sh", ["-c", "printf pty-ok"], {name:"xterm", cols:80, rows:24}); p.onData(d => process.stdout.write(d)); p.onExit(() => process.exit(0))' \
  "$DAIMON_DIR/node_modules/node-pty" | tr -d '\r' | grep -q 'pty-ok' ||
  fail "node-pty native module failed"
pass "Daemon SQLite and PTY native modules load under bundled Node"

(
  cd "$GATEWAY_DIR"
  "$NODE_BIN" -e \
    'Promise.all([import("sharp"), import("@napi-rs/canvas"), import("@mariozechner/clipboard"), import("@snazzah/davey"), import("sqlite-vec")]).then(() => console.log("gateway-native-ok"))'
) | grep -q 'gateway-native-ok' || fail "Gateway native modules failed"
pass "Gateway Linux native modules load"

if find "$RESOURCES" -type f -exec file {} + |
  awk '/Mach-O/ { found = 1 } END { exit !found }'; then
  fail "macOS Mach-O binaries remain in Linux resources"
fi
pass "No macOS binaries remain in packaged resources"

if find "$RESOURCES" -type f -exec file {} + |
  awk '/ELF.*(ARM|aarch64)/ { found = 1 } END { exit !found }'; then
  fail "ARM Linux binaries remain in the x86_64 resources"
fi
pass "No wrong-architecture Linux binaries remain"

if [ "$RESOURCES_ONLY" = true ]; then
  exit 0
fi

APPIMAGE="$PROJECT_DIR/dist/Kimi-Work-3.1.3-linux-x86_64.AppImage"
TARBALL="$PROJECT_DIR/dist/Kimi-Work-3.1.3-linux-x64.tar.gz"
PACMAN_PACKAGE="$PROJECT_DIR/dist/Kimi-Work-3.1.3-linux-x64.pacman"
CHECKSUMS="$PROJECT_DIR/dist/SHA256SUMS"
[ -f "$APPIMAGE" ] || fail "AppImage artifact is missing"
[ -f "$TARBALL" ] || fail "tar.gz artifact is missing"
[ -f "$PACMAN_PACKAGE" ] || fail "Pacman artifact is missing"
[ -f "$CHECKSUMS" ] || fail "SHA256SUMS is missing"
[ -x "$APPIMAGE" ] || fail "AppImage is not executable"
pass "AppImage, tar.gz, and Pacman artifacts exist"

assert_x86_64_elf "$APPIMAGE" "AppImage"
pass "AppImage is a native Linux x86_64 executable"

VERIFY_TMP="$(mktemp -d)"
trap 'rm -rf "$VERIFY_TMP"' EXIT

tar -tzf "$TARBALL" |
  awk '$0 == "Kimi-Work-3.1.3-linux-x64/kimi-work" { found = 1 }
    END { exit !found }' ||
  fail "Portable archive does not contain the expected executable"
pass "Portable archive layout is valid"

TARBALL_WEBBRIDGE="Kimi-Work-3.1.3-linux-x64/resources/resources/kimi-webbridge"
mkdir -p "$VERIFY_TMP/tarball"
tar -xzf "$TARBALL" -C "$VERIFY_TMP/tarball" "$TARBALL_WEBBRIDGE" ||
  fail "Portable archive does not contain Kimi WebBridge"
[ -x "$VERIFY_TMP/tarball/$TARBALL_WEBBRIDGE" ] ||
  fail "Kimi WebBridge is not executable in the portable archive"
[ "$(sha256sum "$VERIFY_TMP/tarball/$TARBALL_WEBBRIDGE" | cut -d ' ' -f 1)" = "$WEBBRIDGE_SHA256" ] ||
  fail "Portable archive contains the wrong Kimi WebBridge"

command -v bsdtar >/dev/null 2>&1 ||
  fail "bsdtar is required to verify the Pacman package"
PACMAN_WEBBRIDGE="opt/Kimi Work/resources/resources/kimi-webbridge"
mkdir -p "$VERIFY_TMP/pacman"
bsdtar -xf "$PACMAN_PACKAGE" -C "$VERIFY_TMP/pacman" "$PACMAN_WEBBRIDGE" ||
  fail "Pacman package does not contain Kimi WebBridge"
[ -x "$VERIFY_TMP/pacman/$PACMAN_WEBBRIDGE" ] ||
  fail "Kimi WebBridge is not executable in the Pacman package"
[ "$(sha256sum "$VERIFY_TMP/pacman/$PACMAN_WEBBRIDGE" | cut -d ' ' -f 1)" = "$WEBBRIDGE_SHA256" ] ||
  fail "Pacman package contains the wrong Kimi WebBridge"

mkdir -p "$VERIFY_TMP/appimage"
(
  cd "$VERIFY_TMP/appimage"
  "$APPIMAGE" --appimage-extract "resources/resources/kimi-webbridge" >/dev/null
) || fail "AppImage does not contain Kimi WebBridge"
APPIMAGE_WEBBRIDGE="$VERIFY_TMP/appimage/squashfs-root/resources/resources/kimi-webbridge"
[ -x "$APPIMAGE_WEBBRIDGE" ] ||
  fail "Kimi WebBridge is not executable in the AppImage"
[ "$(sha256sum "$APPIMAGE_WEBBRIDGE" | cut -d ' ' -f 1)" = "$WEBBRIDGE_SHA256" ] ||
  fail "AppImage contains the wrong Kimi WebBridge"
pass "Every package contains the executable pinned Kimi WebBridge"

if command -v pacman >/dev/null 2>&1; then
  PACMAN_METADATA="$(pacman -Qip "$PACMAN_PACKAGE")" ||
    fail "Pacman package metadata is invalid"
  grep -Eq '^Name +: kimi-desktop$' <<<"$PACMAN_METADATA" ||
    fail "Pacman package has the wrong name"
  grep -Eq '^Version +: 3\.1\.3-1$' <<<"$PACMAN_METADATA" ||
    fail "Pacman package has the wrong version"
  grep -Eq '^Architecture +: x86_64$' <<<"$PACMAN_METADATA" ||
    fail "Pacman package has the wrong architecture"
  grep -Eq '^Packager +: lemon07r$' <<<"$PACMAN_METADATA" ||
    fail "Pacman package has the wrong packager"
  pass "Pacman package metadata is valid and attributed to lemon07r"
fi

(
  cd "$PROJECT_DIR/dist"
  sha256sum --check --strict SHA256SUMS
) || fail "Artifact checksums do not verify"
pass "All artifact checksums verify"
