#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "[1/8] Swift parse"
swiftc -parse $(find NetFlow NetFlowTests -name '*.swift' -print 2>/dev/null | sort)
echo "[2/8] Property lists"
plutil -lint NetFlow/Info.plist NetFlow/NetFlow.entitlements
echo "[3/8] Localizations"
plutil -lint NetFlow/Resources/en.lproj/Localizable.strings NetFlow/Resources/vi.lproj/Localizable.strings
echo "[4/8] App icon"
test -s NetFlow/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
if command -v sips >/dev/null 2>&1; then
  ICON_INFO="$(sips -g pixelWidth -g pixelHeight NetFlow/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png)"
  echo "$ICON_INFO" | grep -q "pixelWidth: 1024"
  echo "$ICON_INFO" | grep -q "pixelHeight: 1024"
  echo "App icon: 1024x1024"
else
  python3 - <<'PY'
from PIL import Image
im=Image.open('NetFlow/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png')
assert im.size==(1024,1024), im.size
assert im.mode in ('RGB','RGBA'), im.mode
print('App icon:', im.size, im.mode)
PY
fi
echo "[5/8] Source membership"
python3 - <<'PY'
from pathlib import Path
pbx=Path('NetFlow.xcodeproj/project.pbxproj').read_text()
swift_files = list(Path('NetFlow').rglob('*.swift')) + list(Path('NetFlowTests').rglob('*.swift'))
missing=[str(p) for p in swift_files if p.name not in pbx]
assert not missing, 'Swift files missing from project: '+str(missing)
print('All Swift files referenced by project')
PY
echo "[6/8] iOS 16 API guard"
! grep -R '\.topBarTrailing' NetFlow --include='*.swift'
echo "[7/8] Required bundle keys"
for key in CFBundleExecutable CFBundleIdentifier CFBundlePackageType CFBundleShortVersionString CFBundleVersion; do
  /usr/libexec/PlistBuddy -c "Print :$key" NetFlow/Info.plist >/dev/null 2>&1 || plutil -extract "$key" raw NetFlow/Info.plist >/dev/null
 done
echo "[8/8] XCTest target"
test -d NetFlowTests
grep -q 'NetFlowTests' NetFlow.xcodeproj/project.pbxproj
test "$(find NetFlowTests -name '*Tests.swift' -print | wc -l | tr -d ' ')" -ge 1
echo "Static project checks passed. Run xcodebuild on macOS for the final SDK compile/signing check."
