# Legacy Vizio Remote

Android remote, Linux terminal settings browser, and experimental Windows PowerShell menu for older Vizio SmartCast TVs.

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

[Download Android APK, Linux script, or PowerShell package](https://github.com/brewst001/legacy-vizio-remote/releases)

Android, Linux, and PowerShell are published as separate releases.

## Initial setup and the Link button

This project was created to keep an otherwise functional TV usable when
the original SmartCast setup process failed.

The following sequence worked on an E32-D1 with firmware 2.0.17.
Other models and firmware versions are unverified.

If your TV is already paired and you have a working token, enter that
token directly. The remote steps below may not be necessary.

### Get the TV onto your local network

For initial setup, connect the TV to your router using Ethernet.
If it already has a working Wi-Fi connection, use that instead.

Find the TV's current IP address in your router's connected-device list.
Your phone or Linux computer must be able to reach that address.
Connecting to the TV's temporary setup Wi-Fi is not the same as joining
your home network.

### Flipper Zero

The following community remote file provided working Link and
Play_pause commands on the tested E32-D1, despite its E70U-D3 filename:

[Download Vizio_E70U-D3.ir](https://raw.githubusercontent.com/UberGuidoZ/Flipper-IRDB/main/TVs/Vizio/Vizio_E70U-D3.ir)

Source: [UberGuidoZ/Flipper-IRDB](https://github.com/UberGuidoZ/Flipper-IRDB).
The file credits emptythevoid for capturing the signals.

1. Download the file as Vizio_E70U-D3.ir, not as a text or HTML file.
2. Connect the Flipper by USB and open qFlipper.
3. Copy the file into SD Card → infrared using File Manager.
4. On the Flipper, open Infrared → Saved Remotes and select the file.
5. Point the Flipper at the TV and send Link twice as separate presses.
   This reached the SmartCast setup screen on the tested TV.

### Original or universal remote

An original remote with Link can be used instead of a Flipper.

A universal remote must support the Vizio Link command, or allow that
command to be learned/programmed onto a button. A basic Vizio profile
with only power, volume and input controls may omit it.

Universal-remote programming depends on the remote model. There is no
verified universal setup code for all remotes. The Flipper .ir file
cannot necessarily be imported into another remote directly.

For programmable remotes, the source file lists these parsed signals:

| Button | Protocol | Address | Command |
| --- | --- | --- | --- |
| Link | NEC | 0x04 | 0x63 |
| Play/Pause | NEC | 0x04 | 0x37 |

These are protocol values, not universal-remote setup codes.

### Pair through this project's app or Linux script

1. Keep the TV powered on and connected to your local network.
2. Enter its current IP address and port 9000.
3. In Android, enable legacy TLS compatibility and select Pair.
   In Linux, choose the pairing option under authentication.
4. If the SmartCast setup screen hides the PIN, send Play_pause
   from the Flipper or press Play/Pause on the compatible remote.
   This exposed the PIN during the tested E32-D1 setup.
5. Enter the current four-digit PIN promptly into the app or script.
   A new pairing attempt can produce a different PIN.
6. After pairing succeeds, test a power-state read or small volume change.

These tools perform PIN/token pairing with the TV's local API.
They do not guarantee completion of every SmartCast onboarding step,
or a fix for every cause of a TV turning itself back on.

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

## Windows PowerShell (prerelease)

Requires Windows PowerShell 5.1 or PowerShell 7 and Java 17. Download and extract the complete PowerShell release ZIP; the script requires its bundled Java TLS helper and libraries.

From the extracted folder:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\vizio-tui.ps1 -TvAddress 192.168.1.221

Replace the example IP with your TV's address. The Java helper avoids the Windows Schannel failure encountered with this TV and pins the approved TV certificate. Saved tokens use Windows DPAPI.

[PowerShell setup and limitations](powershell/README.md)

PowerShell/Linux integration tests passed against a TLS 1.0 simulator. Windows credential storage and this frontend's actual TV control remain unverified. Provided as-is without support.

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
