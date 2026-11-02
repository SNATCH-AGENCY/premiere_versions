# Release setup

Repository: https://github.com/pewakkk/premiere_versions

Feed URL: https://raw.githubusercontent.com/pewakkk/premiere_versions/main/docs/appcast.xml

The public release feed is hosted in this repository. Publish the verified release asset before updating the feed. GitHub Pages is not required.

1. Run `python3 tools/enable_sparkle.py` from the project folder. It downloads the official Sparkle 2.10.1 SDK, verifies SHA-256 and installs it in ignored Vendor/. Pass --archive to use a downloaded copy.
2. The main project already embeds its public update key. For your own fork, run `python3 tools/configure_update_key.py` in normal Terminal. It uses the official Keychain generator and obtains only the public value with -p. Never paste exported key material or commit a private key. A 32-byte value alone cannot prove whether it is public or a private seed. Keep a separate private backup of your key.
3. Build and run `python3 tools/distribution_preflight.py /path/to/app.app`. It checks the public key, linked SDK, installer service, stable metadata/feed URL and pristine code signature.
4. Run `python3 Tests/check_real_updates.py --output /path/to/report.json` from normal Terminal. It uses two isolated sandboxed fixture apps with a unique bundle ID, rejects a tampered archive, then installs a signed local update and checks relaunch, a folder bookmark, language, shortcut, two custom icon slots and Finder icon restoration. It does not replace the installed Premiere Versions app or upload test releases. The fixture's temporary-folder exception is not present in production app entitlements.
5. Use `python3 tools/sign_release.py /path/to/app.app /path/to/output` to create a pristine ZIP and an official generated/signed appcast using the Keychain-backed signing tools. No private key is exported and nothing is uploaded.
6. After review and a successful real-update report, publish the archive in GitHub Releases, then publish appcast.xml as docs/appcast.xml. The feed must point to an already-available archive. No public test releases are needed.

Machine bundle version is version.build (4.6.1); PVBuildNumber is the displayed build (1). Keep the bundle identifier and Premiere Versions.app filename stable across updates.

Provide a short tested first-launch README beside the release archive. Apple Developer ID/notarization are not configured. The Sparkle signature authenticates updates but does not replace macOS application trust.

Official docs: https://sparkle-project.org/documentation/
Sandbox integration: https://sparkle-project.org/documentation/sandboxing/
