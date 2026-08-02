#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "[1/7] Swift parse"
swiftc -parse $(find NetFlow -name '*.swift' -print | sort)
echo "[2/7] Property lists"
plutil -lint NetFlow/Info.plist NetFlow/NetFlow.entitlements
echo "[3/7] Localizations"
plutil -lint NetFlow/Resources/en.lproj/Localizable.strings NetFlow/Resources/vi.lproj/Localizable.strings
echo "[4/7] App icon"
test -s NetFlow/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
python3 - <<'PY'
from PIL import Image
im=Image.open('NetFlow/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png')
assert im.size==(1024,1024), im.size
assert im.mode in ('RGB','RGBA'), im.mode
print('App icon:', im.size, im.mode)
PY
echo "[5/7] Source membership"
python3 - <<'PY'
from pathlib import Path
pbx=Path('NetFlow.xcodeproj/project.pbxproj').read_text()
missing=[str(p) for p in Path('NetFlow').rglob('*.swift') if p.name not in pbx]
assert not missing, 'Swift files missing from project: '+str(missing)
print('All Swift files referenced by project')
PY
echo "[6/7] iOS 16 API guard"
! grep -R '\.topBarTrailing' NetFlow --include='*.swift'
echo "[7/7] Required bundle keys"
for key in CFBundleExecutable CFBundleIdentifier CFBundlePackageType CFBundleShortVersionString CFBundleVersion; do
  /usr/libexec/PlistBuddy -c "Print :$key" NetFlow/Info.plist >/dev/null 2>&1 || plutil -extract "$key" raw NetFlow/Info.plist >/dev/null
 done
echo "Static project checks passed. Run xcodebuild on macOS for the final SDK compile/signing check."
