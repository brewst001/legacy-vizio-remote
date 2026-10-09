# Legacy Vizio Remote — Android and Linux

Independent Android remote and Linux terminal settings browser for older Vizio SmartCast TVs.

Designed for owners experiencing SmartCast pairing errors or legacy TLS connection failures.

## Compatibility

| Model | Status |
| --- | --- |
| Vizio E32-D1, firmware 2.0.17 | Android connectivity confirmed; Linux settings control tested |
| Vizio E50-D1 | Unverified; testing reports welcome |
| Other legacy SmartCast models | Unverified; compatibility may vary |

This project is not affiliated with or endorsed by Vizio. Each user must authenticate with their own TV.

## Linux interface

Script: linux/vizio-tui.sh

Requires Bash, curl, jq, and either dialog or whiptail.

Fedora dependencies:

    sudo dnf install curl jq dialog

Launch using your TV's actual IP address:

    VIZIO_HOST=192.168.1.221 bash linux/vizio-tui.sh

Replace the example IP for your network. Use the connection/pairing prompts to configure authentication.

If saved, the Linux token is stored in plaintext with owner-only permissions at:

    ${XDG_CONFIG_HOME:-$HOME/.config}/vizio-tui/connection.json

Do not upload that connection file.

## Downloads and support

Signed Android APKs will be available under GitHub Releases.

Report your TV model, firmware, operating system, and results through GitHub Issues. Remove tokens and Wi-Fi passwords from diagnostics.

---

## Android documentation

# Local TV — Android beta 0.1.0

Independent local-network remote and settings browser designed around the Vizio E32-D1 API on port 9000. Android 8.0 or later. No account, cloud service, ads, telemetry, or embedded TV credentials. Compatibility with other models is not yet established.

## Install and first test

Install `local-tv-beta.apk` on your phone (allow installs from the app opening the file), or use `adb install -r local-tv-beta.apk` from a computer. The beta uses package `net.local.vizioremote.beta`, separate from future production installs.

1. Put your phone and powered-on TV on the same local network.
2. Open Connection. Enter your TV's IP and port 9000. The initial IP 192.168.1.221 is only a convenience default for the development TV; change it for other TVs.
3. Keep Legacy TV TLS compatibility enabled for the E32-D1. Paste your working token and Save. Nothing needs to be reset or paired again.
4. Tap Read power state. On the first request, confirm the certificate belongs to the TV you intend to connect to.
5. Test Volume + once and Volume − once. Check that the TV responds.
6. Open Settings → System → Power Indicator. Change Off to On; refresh and verify. Restore your preferred value.
7. Open Audio and test a small volume change. Verify unavailable settings show their JSON rather than offering an editor.
8. Use Copy / view JSON and paste into a notes app. Close/reopen Local TV and confirm the saved connection still works.

If testing new pairing, Connection → Pair starts a new challenge and immediately displays a PIN input. Enter the fresh PIN without editing a shell command. If the TV setup screen hides it, the Play/Pause remote button may reveal it, as observed on the development E32-D1. Never reuse a challenge token from a previous attempt. PIN cancellation does not currently send a pairing-cancel request to the TV; if a new request is blocked, wait for the previous challenge to expire.

Report the phone model/Android version, TV model/firmware, action taken, expected/actual result, and exact error. Do not share your AUTH_TOKEN, Wi-Fi password, or unredacted network JSON. No device-side testing has been performed in this environment.

## What this version supports

- Volume, mute, input cycling, channels, power-off, and power-state read.
- Nested settings menus, refresh, selectable JSON, and clipboard copy.
- Enabled primitive list choices, numeric values and strings exposed by the TV API.
- Read-only presentation of unsupported types and disabled settings. It does not implement every possible TV action, reset, device-discovery editor, compound setting or Wi-Fi workflow.
- Confirmation before changes. Fresh read and HASHVAL before each write, rejection if the value changed while editing. Advertised MINIMUM/MAXIMUM bounds are used when present; the TV must enforce other undocumented bounds.
- Network changes can disconnect the TV. Power-on over the network is not implemented; Eco Mode may make the API unreachable while off.

Some category paths are firmware-specific and may return an error. Copy the error/JSON for adding support rather than guessing write paths.

## Transport and token storage

The app bundles Bouncy Castle bcprov/bcutil 1.86 and bctls 1.86.1. Legacy mode enables TLS 1.0, TLS 1.1 and TLS 1.2 and accepts an initial server without secure-renegotiation support; renegotiation remains disabled. Modern mode currently uses TLS 1.2 only. These choices apply only to this app's connections, without changing Android's system TLS settings.

Only private IPv4 and link-local IPv4 destinations are accepted. There is no public internet/cloud functionality. The first certificate requires explicit approval; its SHA-256 fingerprint is pinned, and a changed certificate is rejected until you deliberately clear the pin in Connection. This is first-use trust, not public-CA authentication. Vizio certificates may be shared between TVs, so certificate pinning alone does not uniquely identify the physical unit.

The AUTH token is encrypted with an Android Keystore AES-GCM key and stored in app-private preferences. Backup is disabled. Uninstalling/clearing app data removes the saved connection. IP, port and certificate fingerprint are app-private preferences. Each person enters their own TV token or pairs their own TV. No token is included in the APK or source archive.

## Build on Linux

Install JDK 17, Python 3, Android SDK command-line tools, platform android-35 and build-tools 35.0.0. Android Studio SDK Manager can install the Android components. The included Gradle project can also be opened in Android Studio; the standalone build script avoids needing Gradle.

```bash
export JAVA_HOME=/absolute/path/to/jdk-17
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
bash build.sh
```

Output: `build/local-tv-unsigned.apk`. For a separate beta package:

```bash
BUILD_PACKAGE=net.local.vizioremote.beta bash build.sh
```

The three dependency JARs are bundled in app/libs with their license in THIRD-PARTY-LICENSE.txt. SDK/JDK binaries are not included.

## Sign releases using your own permanent key

The supplied beta is signed with a testing key. It is installable, but this key is not your permanent release identity. Do not distribute it as a final production release. The permanent key should be generated and retained on your computer.

```bash
mkdir -p "$HOME/.local/share/local-tv-signing"
chmod 700 "$HOME/.local/share/local-tv-signing"
keytool -genkeypair -keystore "$HOME/.local/share/local-tv-signing/release.jks" \
  -alias local-tv -keyalg RSA -keysize 3072 -validity 10000
chmod 600 "$HOME/.local/share/local-tv-signing/release.jks"
bash build.sh
bash sign-release.sh "$HOME/.local/share/local-tv-signing/release.jks" local-tv
```

Choose your own passwords when prompted. Save the key, alias and passwords in secure backups; do not commit them to source control or send them here. Output: `build/local-tv-release.apk`. The signing script verifies the signature and prints the APK checksum. Future production updates must use the same package ID and signing key, and a larger versionCode in the manifest/build script/Gradle configuration. Beta and production can coexist and store separate credentials.

A signed APK can be shared directly for sideloading. Signing is not the same as Google Play approval or Android developer verification. Distribution rules vary by country, device and time; check the current Android requirements before broad release. A Play release also needs current target SDK compliance, a release listing, privacy disclosures and testing beyond this prototype.

## Automated tests and verified scope

```bash
JAVA_HOME=/absolute/path/to/jdk-17 python3 tests/test_transport.py
```

This starts an isolated local TLS 1.0 server with AES128-SHA and verifies certificate approval, authenticated UTF-8 requests, Content-Length and chunked responses, changed-certificate rejection, modern-mode rejection of TLS 1.0, and private-address/type policy. It requires openssl and Python's SSL module. Test-only loopback access is package-private and unavailable through the Android UI.

The APK is compile-checked, dexed, packaged, zip-aligned and signature-verified. A TLS 1.0 simulator is not the actual Kinoma firmware and supports secure renegotiation; it does not fully reproduce the TV's missing renegotiation extension. UI, Android Keystore operation, PIN timing and real-TV behavior still require phone testing. Begin with the existing working token before testing pairing.

## License

Original application source is MIT licensed; see LICENSE. Bouncy Castle keeps its own license. This project is not affiliated with or endorsed by Vizio. Do not claim broad model support until tested.
