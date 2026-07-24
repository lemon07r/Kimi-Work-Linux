#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="$PROJECT_DIR/kimi_3.1.3.dmg"
PREPARE_ONLY=false
EXTRACT_DIR="$PROJECT_DIR/extracted"
APP_SOURCE="$PROJECT_DIR/app-source"
BUILD_DIR="$PROJECT_DIR/build"
CACHE_DIR="$BUILD_DIR/cache"
LINUX_RESOURCES="$BUILD_DIR/linux-resources"
LINUX_APP="$BUILD_DIR/linux-app"
INPUT_STAMP="$BUILD_DIR/input-dmg.sha256"
EXTRACT_LOG="$BUILD_DIR/7z-extract.log"
NODE_VERSION="24.15.0"
NODE_ARCHIVE="node-v${NODE_VERSION}-linux-x64.tar.xz"
NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_ARCHIVE}"
NODE_SHA256="472655581fb851559730c48763e0c9d3bc25975c59d518003fc0849d3e4ba0f6"
PYTHON_ARCHIVE="cpython-3.12.13+20260718-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz"
PYTHON_URL="https://github.com/astral-sh/python-build-standalone/releases/download/20260718/cpython-3.12.13%2B20260718-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz"
PYTHON_SHA256="5854aa6ec71cad00334d5065633c210b2e7feb40956767a59a91791cadcf0b79"
UV_VERSION="0.11.29"
UV_ARCHIVE="uv-x86_64-unknown-linux-gnu.tar.gz"
UV_URL="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/${UV_ARCHIVE}"
UV_SHA256="04f8b82f5d47f0512dcd32c67a4a6f16a0ea27c81537c338fd0ad6b23cebe829"
WEBBRIDGE_VERSION="v1.11.3"
WEBBRIDGE_ARCHIVE="kimi-webbridge-${WEBBRIDGE_VERSION}-linux-amd64"
WEBBRIDGE_URL="https://cdn.kimi.com/webbridge/${WEBBRIDGE_VERSION}/releases/kimi-webbridge-linux-amd64"
WEBBRIDGE_SHA256="5f89a15b6dcffa3c88837d3a8fab073fa8499a17f2cbe27f32d428c540f4b418"

log() {
  printf '[kimi-linux] %s\n' "$*"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

usage() {
  printf 'Usage: %s [--dmg PATH] [--prepare-only]\n' "$0"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dmg)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        printf 'Missing path after --dmg.\n' >&2
        usage >&2
        exit 2
      fi
      DMG_PATH="$2"
      shift 2
      ;;
    --prepare-only)
      PREPARE_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

download_verified() {
  local url="$1"
  local destination="$2"
  local expected_sha256="$3"
  if [ ! -f "$destination" ]; then
    log "Downloading $(basename "$destination")"
    curl --fail --location --retry 3 --output "$destination.part" "$url"
    mv "$destination.part" "$destination"
  fi
  local actual_sha256
  actual_sha256="$(sha256sum "$destination" | cut -d ' ' -f 1)"
  if [ "$actual_sha256" != "$expected_sha256" ]; then
    printf 'Checksum mismatch for %s\nExpected: %s\nActual:   %s\n' \
      "$destination" "$expected_sha256" "$actual_sha256" >&2
    exit 1
  fi
}

if [ "$(uname -s)" != "Linux" ] || [ "$(uname -m)" != "x86_64" ]; then
  printf 'This port builder currently targets Linux x86_64 only.\n' >&2
  exit 1
fi

for command_name in 7z awk bun curl file grep node sha256sum tar tee; do
  require_command "$command_name"
done

if [ ! -f "$DMG_PATH" ]; then
  printf 'Missing input DMG: %s\n' "$DMG_PATH" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR" "$CACHE_DIR"

if [ ! -x "$PROJECT_DIR/node_modules/.bin/asar" ] ||
  [ ! -x "$PROJECT_DIR/node_modules/.bin/electron-builder" ]; then
  log "Installing Bun-managed build dependencies"
  (
    cd "$PROJECT_DIR"
    bun install --frozen-lockfile
  )
fi

DMG_SHA256="$(sha256sum "$DMG_PATH" | cut -d ' ' -f 1)"
PREVIOUS_DMG_SHA256=""
if [ -f "$INPUT_STAMP" ]; then
  PREVIOUS_DMG_SHA256="$(tr -d '\r\n' <"$INPUT_STAMP")"
fi

if [ "$DMG_SHA256" != "$PREVIOUS_DMG_SHA256" ]; then
  log "Extracting the DMG"
  rm -rf "$EXTRACT_DIR" "$APP_SOURCE"
  mkdir -p "$EXTRACT_DIR"
  set +e
  7z x -y "$DMG_PATH" "-o$EXTRACT_DIR" 2>&1 | tee "$EXTRACT_LOG"
  SEVEN_ZIP_STATUS="${PIPESTATUS[0]}"
  set -e
  if [ "$SEVEN_ZIP_STATUS" -ne 0 ]; then
    UNEXPECTED_7Z_ERRORS="$(
      awk '/^ERROR:/ &&
        $0 !~ /^ERROR: Dangerous link path was ignored : .*\/gateway\/node_modules\/\.bin\// {
          print
        }' "$EXTRACT_LOG"
    )"
    EXPECTED_LINK_WARNINGS="$(
      grep -c '^ERROR: Dangerous link path was ignored : .*/gateway/node_modules/\.bin/' \
        "$EXTRACT_LOG" || true
    )"
    if [ "$SEVEN_ZIP_STATUS" -ne 2 ] ||
      [ "$EXPECTED_LINK_WARNINGS" -eq 0 ] ||
      [ -n "$UNEXPECTED_7Z_ERRORS" ]; then
      printf '7-Zip failed while extracting %s (status %s).\n' \
        "$DMG_PATH" "$SEVEN_ZIP_STATUS" >&2
      [ -z "$UNEXPECTED_7Z_ERRORS" ] ||
        printf '%s\n' "$UNEXPECTED_7Z_ERRORS" >&2
      exit 1
    fi
    log "Ignored $EXPECTED_LINK_WARNINGS unsafe gateway .bin links; Linux dependencies replace them"
  fi
fi

APP_ASAR="$(find "$EXTRACT_DIR" -type f \
  -path '*/Kimi.app/Contents/Resources/app.asar' -print -quit)"
if [ -z "$APP_ASAR" ]; then
  printf 'The input DMG did not contain the expected Kimi app.asar.\n' >&2
  exit 1
fi
EXTRACTED_APP="$(dirname "$(dirname "$APP_ASAR")")"
SOURCE_RESOURCES="$EXTRACTED_APP/Resources/resources"
if [ ! -d "$SOURCE_RESOURCES" ]; then
  printf 'The input DMG did not contain the expected Kimi resources directory.\n' >&2
  exit 1
fi
printf '%s\n' "$DMG_SHA256" >"$INPUT_STAMP"

if [ ! -d "$APP_SOURCE" ]; then
  log "Extracting app.asar"
  "$PROJECT_DIR/node_modules/.bin/asar" extract "$APP_ASAR" "$APP_SOURCE"
fi

log "Preparing packaged application source"
rm -rf "$LINUX_APP"
mkdir -p "$LINUX_APP"
cp -a --reflink=auto "$APP_SOURCE/." "$LINUX_APP/"
cp "$PROJECT_DIR/packaging/app-package.json" "$LINUX_APP/package.json"
node "$PROJECT_DIR/scripts/patch-linux-app.mjs" "$LINUX_APP"

log "Preparing Linux resources"
rm -rf "$LINUX_RESOURCES"
mkdir -p "$LINUX_RESOURCES"
cp -a --reflink=auto "$SOURCE_RESOURCES/." "$LINUX_RESOURCES/"

# 7-Zip materializes HFS extended attributes as colon-suffixed files. They are
# neither application data nor valid portable Linux resources.
find "$LINUX_RESOURCES" -type f -name '*:com.apple.*' -delete

# Replace the source DMG's Mach-O helper with Moonshot's matching Linux
# release. The desktop process owns installation and supervision of this root
# helper; the inner Daimon bundle intentionally keeps includesWebBridge=false.
download_verified \
  "$WEBBRIDGE_URL" \
  "$CACHE_DIR/$WEBBRIDGE_ARCHIVE" \
  "$WEBBRIDGE_SHA256"
install -m 0755 \
  "$CACHE_DIR/$WEBBRIDGE_ARCHIVE" \
  "$LINUX_RESOURCES/kimi-webbridge"

download_verified "$NODE_URL" "$CACHE_DIR/$NODE_ARCHIVE" "$NODE_SHA256"
rm -rf "$BUILD_DIR/node"
mkdir -p "$BUILD_DIR/node"
tar -xJf "$CACHE_DIR/$NODE_ARCHIVE" -C "$BUILD_DIR/node" --strip-components=1
rm -rf "$LINUX_RESOURCES/runtime"
mkdir -p "$LINUX_RESOURCES/runtime/node_modules"
install -m 0755 "$BUILD_DIR/node/bin/node" "$LINUX_RESOURCES/runtime/node"
cp -a "$BUILD_DIR/node/lib/node_modules/npm" "$LINUX_RESOURCES/runtime/node_modules/npm"

download_verified "$UV_URL" "$CACHE_DIR/$UV_ARCHIVE" "$UV_SHA256"
rm -rf "$BUILD_DIR/uv"
mkdir -p "$BUILD_DIR/uv"
tar -xzf "$CACHE_DIR/$UV_ARCHIVE" -C "$BUILD_DIR/uv"
install -m 0755 \
  "$BUILD_DIR/uv/uv-x86_64-unknown-linux-gnu/uv" \
  "$LINUX_RESOURCES/daimon-bundle/runtime/uv/uv"

download_verified "$PYTHON_URL" "$CACHE_DIR/$PYTHON_ARCHIVE" "$PYTHON_SHA256"
rm -rf "$LINUX_RESOURCES/daimon-bundle/runtime/python/cpython-3.12"
mkdir -p "$LINUX_RESOURCES/daimon-bundle/runtime/python/cpython-3.12"
tar -xzf "$CACHE_DIR/$PYTHON_ARCHIVE" \
  -C "$LINUX_RESOURCES/daimon-bundle/runtime/python/cpython-3.12" \
  --strip-components=1

NODE_BIN="$LINUX_RESOURCES/runtime/node"
NPM_CLI="$LINUX_RESOURCES/runtime/node_modules/npm/bin/npm-cli.js"
export PATH="$LINUX_RESOURCES/runtime:$PATH"
export npm_config_audit=false
export npm_config_cache="$CACHE_DIR/npm"
export npm_config_fund=false
export npm_config_update_notifier=false

# These installs intentionally use the npm CLI bundled with Node 24.15.0.
# Native addons must be built for the exact Node runtime shipped in Kimi Work;
# Bun manages the public build harness, while this is a target-runtime boundary.
log "Installing Linux gateway dependencies"
rm -rf "$LINUX_RESOURCES/gateway/node_modules"
(
  cd "$LINUX_RESOURCES/gateway"
  "$NODE_BIN" "$NPM_CLI" install --omit=dev --save-exact \
    openclaw@2026.3.13 clawhub@0.23.1
)

log "Installing Linux daemon native modules"
rm -rf "$BUILD_DIR/native-daemon"
mkdir -p "$BUILD_DIR/native-daemon"
cp "$PROJECT_DIR/packaging/native-daemon-package.json" "$BUILD_DIR/native-daemon/package.json"
(
  cd "$BUILD_DIR/native-daemon"
  "$NODE_BIN" "$NPM_CLI" install --omit=dev
)
for module_name in better-sqlite3 node-pty; do
  rm -rf "$LINUX_RESOURCES/daimon-bundle/app/daimon/node_modules/$module_name"
  cp -a \
    "$BUILD_DIR/native-daemon/node_modules/$module_name" \
    "$LINUX_RESOURCES/daimon-bundle/app/daimon/node_modules/$module_name"
done

# node-pty ships unused macOS and Windows prebuilds even after compiling its
# active Linux addon. Koffi similarly ships a platform matrix. Pruning those
# inactive binaries removes platform residue and saves roughly 80 MiB.
rm -rf \
  "$LINUX_RESOURCES/daimon-bundle/app/daimon/node_modules/node-pty/prebuilds"
KOFFI_BINARIES="$LINUX_RESOURCES/gateway/node_modules/koffi/build/koffi"
if [ -d "$KOFFI_BINARIES/linux_x64" ]; then
  find "$KOFFI_BINARIES" -mindepth 1 -maxdepth 1 -type d \
    ! -name linux_x64 -exec rm -rf {} +
fi

chmod 0755 \
  "$LINUX_RESOURCES/runtime/node" \
  "$LINUX_RESOURCES/daimon-bundle/runtime/uv/uv" \
  "$LINUX_RESOURCES/daimon-bundle/runtime/python/cpython-3.12/bin/python3.12" \
  "$LINUX_RESOURCES/daimon-bundle/bin/daimon" \
  "$LINUX_RESOURCES/daimon-bundle/bin/kimi-daimon"

"$NODE_BIN" "$PROJECT_DIR/scripts/rewrite-linux-metadata.mjs" "$LINUX_RESOURCES"

log "Running resource-level verification"
bash "$PROJECT_DIR/scripts/verify-linux.sh" --resources-only

if [ "$PREPARE_ONLY" = true ]; then
  log "Linux resources are ready at $LINUX_RESOURCES"
  exit 0
fi

log "Building AppImage, tar.gz, and Pacman packages"
rm -rf "$PROJECT_DIR/dist"
(
  cd "$PROJECT_DIR"
  bun run package:linux
)

log "Generating SHA256SUMS"
(
  cd "$PROJECT_DIR/dist"
  sha256sum \
    Kimi-Work-3.1.3-linux-x86_64.AppImage \
    Kimi-Work-3.1.3-linux-x64.tar.gz \
    Kimi-Work-3.1.3-linux-x64.pacman >SHA256SUMS
)

log "Verifying packaged output"
bash "$PROJECT_DIR/scripts/verify-linux.sh"
log "Build complete. Artifacts are in $PROJECT_DIR/dist"
