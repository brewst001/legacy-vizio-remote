# Legacy Vizio PowerShell menu — prerelease 0.1.0

Windows PowerShell 5.1 or PowerShell 7, plus Java 17 (JRE or JDK). No Python, WSL, Android SDK, curl replacement, or system TLS changes are required. The complete ZIP is required; the PS1 is not standalone.

Install a current Java 17 runtime from Eclipse Adoptium:
https://adoptium.net/temurin/releases/?version=17&os=windows

After installing, reopen PowerShell and verify `java -version`. If Java is not on PATH, pass `-JavaPath 'C:\path\to\java.exe'`.

Extract the ZIP, open PowerShell in the extracted folder, and run:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\vizio-tui.ps1 -TvAddress 192.168.1.221

Replace the IP with your TV's actual address. Bypass applies to this PowerShell process only; it does not change the persistent execution policy. The script is not Authenticode-signed. Organization policies can still restrict execution.

Use port 9000 with legacy TLS enabled for an E32-D1. Enter your existing token through the hidden prompt, or choose pairing and enter the fresh PIN. If the TV hides its PIN behind setup, the tested remote Play/Pause workaround may expose it; see the main repository README for Link-button setup instructions.

Approve the TV certificate on the first request. Browse System, Audio or another category; select an enabled setting, choose/type a value, and confirm before applying. Unsupported and disabled setting types are read-only. The menu includes volume up/down, mute, power-state read, and JSON viewing/copying. Network changes can disconnect the TV. Network power-on is not implemented. Cancelled pairing is not explicitly cancelled on the TV; an outstanding challenge may need to expire.

## Storage and transport

Configuration is stored at `%LOCALAPPDATA%\LegacyVizioRemote`. If you opt to save the token, it is encrypted using Windows DPAPI for the current Windows user. There is no plaintext-token fallback. The folder is restricted to that user. Tokens are not placed in Java command-line arguments; requests use process stdin. Tokens still exist in process memory while in use.

Certificate fingerprints are stored separately in `trusted-certificates.json` and are remembered even if you do not save the token. Changed certificates are rejected. The menu allows you to explicitly forget the current TV's certificate after verifying a legitimate change. First-use trust requires a trusted local network; Vizio certificates may be shared between physical TVs.

The bundled Java helper reuses the Android project's Bouncy Castle transport and certificate pinning. Legacy TLS compatibility stays within this process. Only private/link-local IPv4 destinations are accepted. TLS 1.0 remains an obsolete protocol; this tool cannot upgrade the TV firmware.

There is no telemetry, cloud account or bundled TV credential.

## Test scope

PowerShell parser and runtime integration tested on Linux with PowerShell 7 against a TLS 1.0 simulator: certificate approval, declined trust, saved pin reuse, changed-certificate rejection before HTTP/token transmission, private-address restrictions, and a numeric setting update with a fresh hash.

Windows PowerShell 5.1, DPAPI storage, Windows folder ACLs, and actual TV control using this frontend have NOT been tested. This is a prerelease, not a claim of verified Windows or E50-D1 compatibility. The shared transport already works in the Android E32-D1 app.

## Rebuild helper from the repository

With JDK 17 installed on Linux:

    JAVA_HOME=/path/to/jdk-17 bash powershell/build-helper.sh

The helper compiles the existing `app/src/main/java/net/local/vizioremote/TvTransport.java` and the PowerShell CLI source. Dependency JARs remain under app/libs in the repository; the release ZIP includes copies under lib. Do not commit TV credentials, private signing keys, or configuration files.

## License and support

Provided as-is without support or a commitment to updates. MIT license and NOTICE included. Bouncy Castle retains its separate license in THIRD-PARTY-LICENSE.txt. Independent project; no affiliation with or endorsement by Vizio.
