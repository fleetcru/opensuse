# Fleetcru openSUSE Tumbleweed Setup

Automated setup for an x86_64 openSUSE Tumbleweed KDE desktop.

## What it installs

- System updates and KDE Plasma X11 support
- Firefox from Mozilla's official repository
- Git, Git LFS, GitHub CLI, ShellCheck, and build tools
- Go
- Node.js through NVM
- pnpm through Corepack
- Rust, Rustfmt, and Clippy
- Flutter and Dart
- Android Studio
- Java through SDKMAN
- uv and Python

The script also installs the required Flutter Linux dependencies and stages the Flutter archive under `/var/tmp/setup-dev`.

## Requirements

- x86_64 Linux
- openSUSE Tumbleweed
- Working `sudo` access
- Internet access
- At least 4 GB of free disk space for Android Studio
- Run the script as a normal user when possible

## Normal installation

Download and run the latest version with cache refresh:

```bash
curl -fsSL -H 'Cache-Control: no-cache' \
  "https://suse.fleetcru.dev/setup.sh?refresh=$(date +%s)" \
  -o /tmp/setup.sh && chmod +x /tmp/setup.sh && sudo /tmp/setup.sh
```

The script asks whether to reboot at the end. Rebooting is recommended.

## Cloud-init installation

Use [cloud-init-setup.yaml](./cloud-init-setup.yaml) as DigitalOcean User Data or cloud-init configuration.

The cloud-init runner:

1. Updates package metadata.
2. Installs `curl` and `sudo`.
3. Downloads the latest `setup.sh` with a cache-busting query.
4. Runs the setup as `root`.
5. Answers the reboot prompt with `N`.
6. Writes output to `/var/log/fleetcru-setup.log`.

To inspect cloud-init progress:

```bash
sudo tail -f /var/log/fleetcru-setup.log
sudo cloud-init status --long
```

Root execution is intentional for cloud-init, but Flutter will warn that it is running as root and user-level files will be stored under `/root`.

## Android Studio and Flutter

The script installs Android Studio but does not complete the Android SDK wizard automatically.

After launching Android Studio and installing the SDK components, run:

```bash
flutter config --android-sdk "$HOME/Android/Sdk"
flutter doctor --android-licenses
flutter doctor
```

If Android Studio uses another SDK location, replace the path accordingly.

## Safety and idempotence

The script uses:

- `set -Eeuo pipefail`
- SHA-256 verification for downloaded archives
- Idempotent checks for installed tools and configuration
- Normal GPG verification for Zypper
- Automatic GPG key import without disabling signature checks

The Firefox setup removes stale Mozilla repository metadata and the revoked old RPM key, imports Mozilla's current official signing key, refreshes only the Mozilla repository, and falls back to openSUSE's `MozillaFirefox` package if Mozilla does not provide `firefox`.

Review the script before running it on a production workstation.
