#!/usr/bin/env bash
# Fails if a built V1 release APK declares any permission other than RECORD_AUDIO
# (docs/SPEC.md §4). Usage: tools/check_release_manifest.sh [path/to/app-release.apk]
set -euo pipefail
APK="${1:-app/build/app/outputs/flutter-apk/app-release.apk}"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/opt/sdk/android}}"
AAPT2="$(ls -d "$SDK"/build-tools/*/aapt2 | sort -V | tail -1)"
[ -f "$APK" ] || { echo "APK not found: $APK" >&2; exit 2; }

perms="$("$AAPT2" dump permissions "$APK" | sed -n "s/^uses-permission: name='\([^']*\)'.*/\1/p" | sort -u)"
echo "Permissions in $APK:"; echo "${perms:-<none>}" | sed 's/^/  /'

# Android auto-generates <pkg>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION (signature-level, app-internal).
unexpected="$(echo "$perms" | grep -v -x 'android.permission.RECORD_AUDIO' | grep -v 'DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION$' || true)"
if [ -n "$unexpected" ]; then
  echo "FAIL: unexpected permissions:" >&2; echo "$unexpected" | sed 's/^/  /' >&2; exit 1
fi
echo "OK: release APK requests RECORD_AUDIO only (no INTERNET)."
