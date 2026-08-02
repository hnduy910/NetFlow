#!/bin/sh
set -eu
IPA="${1:-}"
if [ -z "$IPA" ] || [ ! -f "$IPA" ]; then
  echo "Usage: $0 /path/to/NetFlow.ipa" >&2
  exit 2
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unzip -q "$IPA" -d "$TMP"
APP="$(find "$TMP/Payload" -maxdepth 1 -type d -name '*.app' | head -n 1)"
[ -n "$APP" ] || { echo "ERROR: Payload/*.app not found" >&2; exit 1; }
PLIST="$APP/Info.plist"
[ -f "$PLIST" ] || { echo "ERROR: Info.plist not found" >&2; exit 1; }
if command -v plutil >/dev/null 2>&1; then
  EXEC="$(plutil -extract CFBundleExecutable raw -o - "$PLIST" 2>/dev/null || true)"
else
  EXEC="$(python3 - "$PLIST" <<'PY2'
import plistlib,sys
with open(sys.argv[1],'rb') as f: print(plistlib.load(f).get('CFBundleExecutable',''))
PY2
)"
fi
[ -n "$EXEC" ] || { echo "ERROR: CFBundleExecutable is missing or empty" >&2; exit 1; }
[ -f "$APP/$EXEC" ] || { echo "ERROR: executable does not exist: $APP/$EXEC" >&2; exit 1; }
echo "OK: CFBundleExecutable=$EXEC"
echo "OK: executable exists"
echo "OK: IPA structure is compatible with direct loaders"
