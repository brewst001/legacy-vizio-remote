# Legacy Vizio Remote

Android remote and Linux terminal settings browser for older Vizio SmartCast TVs.

Provides local control through the TV's API, including compatibility with the legacy TLS used by the E32-D1.

**Provided as-is. No technical support, troubleshooting assistance, or commitment to updates is provided.**

## Compatibility

| Model | Status |
| --- | --- |
| Vizio E32-D1, firmware 2.0.17 | Android connectivity and Linux settings control tested |
| Vizio E50-D1 | Not tested |
| Other older Vizio SmartCast TVs | Not tested; compatibility may vary |

An E50-D1 or another model using a similar interface may work, but compatibility is not guaranteed.

## Downloads

[Download Android APK or Linux script](https://github.com/brewst001/legacy-vizio-remote/releases)

Android and Linux are published as separate releases.

## Android

Requires Android 8.0 or later.

1. Download and install the APK, or install it with ADB:

       adb install -r local-tv-release.apk

2. Connect your phone and TV to the same local network.
3. Open Connection and enter your TV's IP address.
4. For the E32-D1, use port 9000 and enable legacy TLS compatibility.
5. Enter an existing authentication token or use PIN pairing.

The Android release is signed with the project's permanent signing key.

Features include remote controls, a settings browser, and JSON viewing/copying. Network power-on is not implemented.

## Linux

Requires Bash, curl, jq, OpenSSL, timeout (GNU coreutils), and either dialog or whiptail.

Fedora/Nobara dependencies:

    sudo dnf install curl jq dialog openssl coreutils

Run the downloaded script:

    VIZIO_HOST=192.168.1.221 bash vizio-tui.sh

Or run it from the repository:

    VIZIO_HOST=192.168.1.221 bash linux/vizio-tui.sh

Replace the example IP with your TV's address. Configure authentication through the script's prompts.

## Credentials and limitations

Each user must authenticate with their own TV. No TV credentials are included.

Android stores the token encrypted using Android Keystore. The Linux script optionally saves its token in plaintext with owner-only permissions:

    ${XDG_CONFIG_HOME:-$HOME/.config}/vizio-tui/connection.json

The Linux script asks you to approve the TV's public key on first connection, then checks that key before sending API requests or tokens. Trusted keys are saved separately from credentials, with owner-only permissions:

    ${XDG_CONFIG_HOME:-$HOME/.config}/vizio-tui/trusted-keys.json

A changed key is rejected. The menu can explicitly forget the current TV's key after a verified device or key change. First-use trust requires a trusted local network; manufacturer keys may be shared between TVs. Public-key pinning works with the existing TV certificate, without updating its issuer, hostname or expiry.

Legacy TLS compatibility is scoped to the application. Settings availability depends on TV firmware. Eco Mode may make the network API unavailable while the TV is off.

## License

MIT license; see LICENSE. Bundled Bouncy Castle license notices are in THIRD-PARTY-LICENSE.txt.

Independent project. Not affiliated with or endorsed by Vizio.
