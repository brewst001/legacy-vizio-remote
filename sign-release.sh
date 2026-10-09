#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
sdk=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
[[ -n $sdk ]] || { echo 'Set ANDROID_SDK_ROOT.' >&2; exit 1; }
keystore=${1:?Usage: bash sign-release.sh /absolute/path/to/your-release.jks [alias]}
alias=${2:-local-tv}
[[ -f $keystore ]] || { echo 'Create your keystore first; see README.md.' >&2; exit 1; }
"$sdk/build-tools/35.0.0/apksigner" sign --ks "$keystore" --ks-key-alias "$alias" --out build/local-tv-release.apk build/local-tv-unsigned.apk
"$sdk/build-tools/35.0.0/apksigner" verify --verbose --print-certs build/local-tv-release.apk
sha256sum build/local-tv-release.apk
