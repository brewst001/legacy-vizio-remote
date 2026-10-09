#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
sdk=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
[[ -n $sdk ]] || { echo 'Set ANDROID_SDK_ROOT to your Android SDK directory.' >&2; exit 1; }
javac_bin=${JAVA_HOME:+$JAVA_HOME/bin/}javac
bt="$sdk/build-tools/35.0.0"
platform="$sdk/platforms/android-35/android.jar"
[[ -f $platform && -x $bt/aapt2 ]] || { echo 'Install SDK platform android-35 and build-tools 35.0.0.' >&2; exit 1; }
rm -rf build
mkdir -p build/classes build/dex
"$javac_bin" -encoding UTF-8 -source 8 -target 8 -classpath "$platform:app/libs/*" -d build/classes app/src/main/java/net/local/vizioremote/*.java
"${JAVA_HOME:+$JAVA_HOME/bin/}jar" cf build/classes.jar -C build/classes .
"$bt/d8" --min-api 26 --lib "$platform" --output build/dex build/classes.jar app/libs/*.jar
"$bt/aapt2" link -o build/base.apk -I "$platform" --manifest app/src/main/AndroidManifest.xml --min-sdk-version 26 --target-sdk-version 35 --version-code 1 --version-name 0.1.0 ${BUILD_PACKAGE:+--rename-manifest-package "$BUILD_PACKAGE"}
python3 - <<'PY'
import zipfile,pathlib
with zipfile.ZipFile('build/base.apk','a',zipfile.ZIP_DEFLATED) as z:
    for p in pathlib.Path('build/dex').glob('*.dex'): z.write(p,p.name)
PY
"$bt/zipalign" -p -f 4 build/base.apk build/local-tv-unsigned.apk
echo "Built: $PWD/build/local-tv-unsigned.apk"
