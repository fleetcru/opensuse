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

Run the script as your regular sudo-enabled user. Do not prefix the script
with `sudo`; it uses `sudo` internally for system-level changes so that
user-level tools remain owned by your account.

One-liner:

```bash
curl -fsSL -H 'Cache-Control: no-cache' "https://suse.fleetcru.dev/setup.sh?refresh=$(date +%s)" -o /tmp/setup.sh && chmod +x /tmp/setup.sh && /tmp/setup.sh
```

The script asks for your sudo password near the beginning and asks whether to
reboot at the end. Rebooting is recommended.

Do not run `sudo /tmp/setup.sh` on a personal machine. That makes root own
user-level tools such as Flutter, Rust, Node, and SDKMAN.

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

## Android Studio desktop entry

The script installs Android Studio under `/opt/android-studio`. To add it to
the KDE application menu, create this desktop entry:

```bash
sudo tee /usr/share/applications/android-studio.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Android Studio
Comment=Android development environment
Exec=/opt/android-studio/bin/studio.sh %f
Icon=/opt/android-studio/bin/studio.png
Terminal=false
Categories=Development;IDE;
StartupWMClass=jetbrains-android-studio
EOF

sudo update-desktop-database /usr/share/applications 2>/dev/null || true
```

You can also launch it directly with:

```bash
/opt/android-studio/bin/studio.sh
```

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
