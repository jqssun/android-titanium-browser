#!/bin/bash
# Build the bundled Flash Player extension from the single source script.
#
#   ./repack.sh                 # writes dist/flash-player.crx
#
# Reads player/extension/manifest.json and player/flashplayer.js, stamps a new
# monotonically increasing version, and packs with the browser's own CRX3
# signer. The signing key is NOT in this repository; it lives beside the
# release keystore and FLASH_PLAYER_EXT_KEY overrides its location. Losing it
# means the extension gets a new id: regenerate the key, replace the "key"
# value in the manifest with the new SPKI, and the build's bundled.json entry
# follows automatically.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
KEY_PEM=${FLASH_PLAYER_EXT_KEY:-/f/flash-player-extension-key.pem}

if [ ! -f "$KEY_PEM" ]; then
  echo "player: signing key not found at $KEY_PEM (set FLASH_PLAYER_EXT_KEY)" >&2
  exit 1
fi
if [ ! -f "$SCRIPT_DIR/flashplayer.js" ] || [ ! -f "$SCRIPT_DIR/extension/manifest.json" ]; then
  echo "player: flashplayer.js or extension/manifest.json is missing" >&2
  exit 1
fi

browser=${MSEDGE:-}
if [ -z "$browser" ]; then
  for candidate in \
    "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
    "/c/Program Files/Microsoft/Edge/Application/msedge.exe" \
    "/g/win-apps/Edge/Application/msedge.exe" \
    "/g/win-apps/Chrome/Application/chrome.exe"; do
    [ -f "$candidate" ] && browser=$candidate && break
  done
fi
if [ -z "$browser" ]; then
  echo "player: no Edge or Chrome found to pack with (set MSEDGE)" >&2
  exit 1
fi

w() { command -v cygpath >/dev/null 2>&1 && cygpath -w "$1" || echo "$1"; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
stage=$work/flash-player
mkdir -p "$stage"

version=1.$(date +%s)
sed "s|\"version\": \"[^\"]*\"|\"version\": \"$version\"|" \
  "$SCRIPT_DIR/extension/manifest.json" > "$stage/manifest.json"
cp "$SCRIPT_DIR/flashplayer.js" "$stage/flashplayer.js"

MSYS_NO_PATHCONV=1 "$browser" --no-first-run \
  --user-data-dir="$(w "$work/profile")" \
  --pack-extension="$(w "$stage")" --pack-extension-key="$(w "$KEY_PEM")" >/dev/null 2>&1

if [ ! -f "$stage.crx" ]; then
  echo "player: $browser produced no flash-player.crx" >&2
  exit 1
fi

mkdir -p "$SCRIPT_DIR/dist"
cp "$stage.crx" "$SCRIPT_DIR/dist/flash-player.crx"

py=""
for p in py python python3; do command -v $p >/dev/null 2>&1 && py=$p && break; done
if [ -n "$py" ]; then
  "$py" - "$SCRIPT_DIR/dist/flash-player.crx" "$SCRIPT_DIR/flashplayer.js" "$SCRIPT_DIR/extension/manifest.json" <<'PY'
import base64, hashlib, json, struct, sys, zipfile

crx, source, template = sys.argv[1], sys.argv[2], sys.argv[3]


def varint(buf, i):
    value = shift = 0
    while True:
        byte = buf[i]
        i += 1
        value |= (byte & 0x7F) << shift
        shift += 7
        if not byte & 0x80:
            return value, i


data = open(crx, "rb").read()
assert data[:4] == b"Cr24", "not a CRX file"
header = data[12:12 + struct.unpack("<I", data[8:12])[0]]
i = 0
while i < len(header):
    key, i = varint(header, i)
    length, i = varint(header, i)
    if key >> 3 == 10000:
        break
    i += length
packed_key = header[i + 2:i + 18]
assert len(packed_key) == 16, "no signing key in the crx header"
ext_id = "".join(chr(97 + n) for byte in packed_key for n in (byte >> 4, byte & 15))

archive = zipfile.ZipFile(crx)
assert sorted(archive.namelist()) == ["flashplayer.js", "manifest.json"], archive.namelist()
manifest = json.loads(archive.read("manifest.json"))
packed = archive.read("flashplayer.js")
local = open(source, "rb").read()
assert packed == local, "packed script differs from player/flashplayer.js"

source_manifest = json.load(open(template, encoding="utf-8"))
source_manifest.pop("version")
shipped = dict(manifest)
shipped.pop("version")
assert shipped == source_manifest, "packed manifest drifted from the template"

# The manifest key pins the id, so it has to be the key the crx was signed with,
# or the build records one id and Chromium installs another.
assert manifest.get("key"), "the manifest template lost its \"key\""
assert hashlib.sha256(base64.b64decode(manifest["key"])).digest()[:16] == packed_key, \
    "manifest key and signing key disagree"

print("id      ", ext_id)
print("version ", manifest["version"])
print("crx     ", len(data), "bytes; script", len(packed), "bytes, byte-identical")
PY
else
  echo "player: no python on PATH, the crx was packed but not verified" >&2
fi
