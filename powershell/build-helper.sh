#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
javac_bin=${JAVA_HOME:+$JAVA_HOME/bin/}javac
jar_bin=${JAVA_HOME:+$JAVA_HOME/bin/}jar
mkdir -p build/powershell-classes powershell/lib
"$javac_bin" --release 8 -encoding UTF-8 -cp 'app/libs/*' -d build/powershell-classes app/src/main/java/net/local/vizioremote/TvTransport.java powershell/src/net/local/vizioremote/TransportCli.java
"$jar_bin" cf powershell/lib/transport.jar -C build/powershell-classes .
echo 'Built powershell/lib/transport.jar'
