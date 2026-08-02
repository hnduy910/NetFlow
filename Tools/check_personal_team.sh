#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENT="$ROOT/NetFlow/NetFlow.entitlements"
if /usr/libexec/PlistBuddy -c "Print :com.apple.developer.networking.wifi-info" "$ENT" >/dev/null 2>&1; then
  echo "ERROR: Unsupported Access Wi-Fi Information entitlement is still present."
  exit 1
fi
echo "OK: Personal Team compatible — Wi-Fi Information entitlement is absent."
