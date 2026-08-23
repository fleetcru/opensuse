#!/usr/bin/env bash
set -Eeuo pipefail

readonly GO_VERSION="go1.27.0"
readonly NVM_VERSION="v0.40.7"
readonly NODE_VERSION="24"
readonly PNPM_VERSION="11.22.0"
readonly JAVA_VERSION="17.0.20-tem"
readonly FLUTTER_VERSION="3.47.1"

log() {
    printf '\n==> %s\n' "$1"
}

check_requirements() {
    local required_commands=(
        curl
        grep
        mktemp
        sed
        sha256sum
        sudo
        tar
        uname
        zypper
    )

    local command_name

    for command_name in "${required_commands[@]}"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            echo "Error: required command not found: $command_name" >&2
            exit 1
        fi
    done

    if [[ "$(uname -s)" != "Linux" ]]; then
        echo "Error: this script supports Linux only." >&2
        exit 1
    fi

    if [[ "$(uname -m)" != "x86_64" ]]; then
        echo "Error: this script supports AMD64/x86_64 only." >&2
        echo "Detected architecture: $(uname -m)" >&2
        exit 1
    fi
}

update_opensuse() {
    log "Updating openSUSE"

    sudo zypper dup

    log "Installing the Plasma 6 X11 session"

    sudo zypper install plasma6-session-x11
}

install_system_dev_packages() {
    log "Installing Git, terminal utilities, and build tools"

    sudo zypper install \
        git \
        git-lfs \
        gh \
        curl \
        wget \
        file \
        unzip \
        zip \
        xz \
        jq \
        ripgrep \
        fd \
        fzf \
        bat \
        tmux \
        shellcheck \
        gcc \
        gcc-c++ \
        make \
        cmake \
        ninja \
        pkg-config

    log "Installing the openSUSE development pattern"

    sudo zypper install -t pattern devel_basis

    log "Installing required Flutter Linux dependencies"

    sudo zypper install \
        clang \
        libGLU1

    log "Installing Tauri system dependencies"

    sudo zypper install \
        webkit2gtk3-devel \
        libopenssl-devel \
        libappindicator3-1 \
        librsvg-devel

    log "Configuring Git LFS"

    git lfs install
}

install_go() (
    set -Eeuo pipefail

    local go_file="go1.27.0.linux-amd64.tar.gz"
    local go_url="https://go.dev/dl/go1.27.0.linux-amd64.tar.gz"
    local go_sha256="675c26c449cbb18fc24b74650de1eabbae6e16f64326fd85a283fb3b58280685"

    local go_temp_dir
    local go_archive
    local path_line

    go_temp_dir="$(mktemp -d)"
    go_archive="${go_temp_dir}/${go_file}"

    cleanup_go() {
        rm -rf -- "$go_temp_dir"
    }

    trap cleanup_go EXIT

    log "Downloading $go_file"

    curl \
        --proto '=https' \
        --tlsv1.2 \
        --fail \
        --show-error \
        --location \
        --retry 3 \
        --retry-delay 2 \
        --output "$go_archive" \
        "$go_url"

    log "Verifying the Go SHA-256 checksum"

    printf '%s  %s\n' "$go_sha256" "$go_archive" |
        sha256sum --check -

    log "Installing $GO_VERSION into /usr/local/go"

    sudo rm -rf -- /usr/local/go
    sudo tar -C /usr/local -xzf "$go_archive"

    if [[ ! -x /usr/local/go/bin/go ]]; then
        echo "Error: Go installation failed." >&2
        exit 1
    fi

    path_line='export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"'

    touch "$HOME/.bashrc"

    if ! grep -Fqx "$path_line" "$HOME/.bashrc"; then
        {
            printf '\n'
            printf '# Go toolchain\n'
            printf '%s\n' "$path_line"
        } >> "$HOME/.bashrc"
    fi

    /usr/local/go/bin/go version
)

install_node_stack() (
    set -Eeo pipefail

    export NVM_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvm"

    log "Installing NVM $NVM_VERSION"

    curl \
        --proto '=https' \
        --tlsv1.2 \
        --fail \
        --silent \
        --show-error \
        --location \
        "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" |
        bash

    set +u
    source "$HOME/.bashrc" || true
    set -u

    if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
        echo "Error: NVM was not found at:" >&2
        echo "  $NVM_DIR/nvm.sh" >&2
        exit 1
    fi

    set +u
    source "$NVM_DIR/nvm.sh"
    set -u

    log "Installing Node.js $NODE_VERSION"

    nvm install "$NODE_VERSION"
    nvm alias default "$NODE_VERSION"
    nvm use "$NODE_VERSION"

    if ! command -v node >/dev/null 2>&1; then
        echo "Error: Node.js installation failed." >&2
        exit 1
    fi

    log "Installing pnpm $PNPM_VERSION through Corepack"

    corepack enable pnpm
    corepack install --global "pnpm@${PNPM_VERSION}"

    echo
    echo "NVM:  $(nvm --version)"
    echo "Node: $(node --version)"
    echo "npm:  $(npm --version)"
    echo "pnpm: $(pnpm --version)"
)

install_sdkman_and_java() (
    set -Eeo pipefail

    log "Installing SDKMAN"

    curl \
        --proto '=https' \
        --tlsv1.2 \
        --fail \
        --silent \
        --show-error \
        --location \
        https://get.sdkman.io |
        bash

    if [[ ! -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
        echo "Error: SDKMAN installation failed." >&2
        exit 1
    fi

    set +u
    source "$HOME/.sdkman/bin/sdkman-init.sh"
    set -u

    log "Installing Eclipse Temurin JDK $JAVA_VERSION"

    sdk install java "$JAVA_VERSION"
    sdk default java "$JAVA_VERSION"
    sdk use java "$JAVA_VERSION"

    echo
    sdk version
    java --version
    javac --version
    echo "JAVA_HOME=$JAVA_HOME"
)

load_sdkman_java() {
    if [[ ! -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
        echo "Error: SDKMAN initialization file was not found." >&2
        exit 1
    fi

    set +u
    source "$HOME/.sdkman/bin/sdkman-init.sh"
    set -u

    sdk use java "$JAVA_VERSION" >/dev/null
}

install_rust() (
    set -Eeo pipefail

    log "Installing Rust through the official Rustup installer"

    curl \
        --proto '=https' \
        --tlsv1.2 \
        --silent \
        --show-error \
        --fail \
        https://sh.rustup.rs |
        sh -s -- -y

    if [[ ! -s "$HOME/.cargo/env" ]]; then
        echo "Error: Rust environment file was not created." >&2
        exit 1
    fi

    set +u
    source "$HOME/.cargo/env"
    set -u

    log "Installing Rustfmt and Clippy"

    rustup component add rustfmt clippy

    echo
    echo "Rustup: $(rustup --version)"
    echo "Rust:   $(rustc --version)"
    echo "Cargo:  $(cargo --version)"
)

install_uv_and_python() (
    set -Eeo pipefail

    log "Installing uv using the official installer"

    curl \
        --proto '=https' \
        --tlsv1.2 \
        --fail \
        --silent \
        --show-error \
        --location \
        https://astral.sh/uv/install.sh |
        sh

    export PATH="$HOME/.local/bin:$PATH"

    if ! command -v uv >/dev/null 2>&1; then
        echo "Error: uv installation failed." >&2
        exit 1
    fi

    local path_line
    path_line='export PATH="$HOME/.local/bin:$PATH"'

    touch "$HOME/.bashrc"

    if ! grep -Fqx "$path_line" "$HOME/.bashrc"; then
        {
            printf '\n'
            printf '# User-installed command-line tools\n'
            printf '%s\n' "$path_line"
        } >> "$HOME/.bashrc"
    fi

    log "Installing Python through uv"

    uv python install

    echo
    uv --version
    uv python list
)

install_android_studio() (
    set -Eeuo pipefail

    local studio_version="2026.1.3.8"
    local studio_file="android-studio-quail3-patch1-linux.tar.gz"
    local studio_url="https://edgedl.me.gvt1.com/android/studio/ide-zips/2026.1.3.8/android-studio-quail3-patch1-linux.tar.gz"
    local studio_sha256="5bd5ee5d6e747b13f82fba3241380bd358cc2f4a847815c8e860757df13dc35f"

    local studio_temp_dir
    local studio_archive

    studio_temp_dir="$(mktemp -d)"
    studio_archive="${studio_temp_dir}/${studio_file}"

    cleanup_android_studio() {
        rm -rf -- "$studio_temp_dir"
    }

    trap cleanup_android_studio EXIT

    log "Downloading Android Studio $studio_version"

    curl \
        --proto '=https' \
        --tlsv1.2 \
        --fail \
        --show-error \
        --location \
        --retry 3 \
        --retry-delay 2 \
        --output "$studio_archive" \
        "$studio_url"

    log "Verifying the Android Studio SHA-256 checksum"

    printf '%s  %s\n' "$studio_sha256" "$studio_archive" |
        sha256sum --check -

    log "Installing Android Studio into /opt/android-studio"

    sudo rm -rf -- /opt/android-studio
    sudo tar -C /opt -xzf "$studio_archive"

    if [[ ! -x /opt/android-studio/bin/studio.sh ]]; then
        echo "Error: Android Studio installation failed." >&2
        exit 1
    fi

    sudo ln -sfn \
        /opt/android-studio/bin/studio.sh \
        /usr/local/bin/android-studio

    echo
    echo "Android Studio installed successfully."
    echo "Start it after reboot with:"
    echo "  android-studio"
)

install_flutter() (
    set -Eeuo pipefail

    local flutter_file="flutter_linux_3.47.1-stable.tar.xz"
    local flutter_url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.1-stable.tar.xz"
    local flutter_sha256="a1d8166c0309267cb7dc99f1424eecf08b86946ad3b50723c6f59945964aea45"

    local flutter_base="$HOME/develop"
    local flutter_install="${flutter_base}/flutter-${FLUTTER_VERSION}"
    local flutter_link="${flutter_base}/flutter"
    local flutter_temp_dir
    local flutter_archive
    local path_line

    flutter_temp_dir="$(mktemp -d)"
    flutter_archive="${flutter_temp_dir}/${flutter_file}"

    cleanup_flutter() {
        rm -rf -- "$flutter_temp_dir"
    }

    trap cleanup_flutter EXIT

    log "Downloading Flutter $FLUTTER_VERSION"

    curl \
        --proto '=https' \
        --tlsv1.2 \
        --fail \
        --show-error \
        --location \
        --retry 3 \
        --retry-delay 2 \
        --output "$flutter_archive" \
        "$flutter_url"

    log "Verifying the Flutter SHA-256 checksum"

    printf '%s  %s\n' "$flutter_sha256" "$flutter_archive" |
        sha256sum --check -

    log "Extracting Flutter"

    mkdir -p "$flutter_base"
    mkdir -p "$flutter_temp_dir/extracted"

    tar \
        -xJf "$flutter_archive" \
        -C "$flutter_temp_dir/extracted"

    if [[ ! -x "$flutter_temp_dir/extracted/flutter/bin/flutter" ]]; then
        echo "Error: Flutter archive is invalid." >&2
        exit 1
    fi

    if [[ ! -d "$flutter_install" ]]; then
        mv "$flutter_temp_dir/extracted/flutter" "$flutter_install"
    else
        echo "Flutter $FLUTTER_VERSION is already installed."
    fi

    # Preserve an existing non-symlink Flutter installation.
    if [[ -e "$flutter_link" && ! -L "$flutter_link" ]]; then
        local flutter_backup
        flutter_backup="${flutter_link}.backup.$(date +%Y%m%d-%H%M%S)"

        echo "Moving the existing Flutter installation to:"
        echo "  $flutter_backup"

        mv "$flutter_link" "$flutter_backup"
    fi

    ln -sfn "$flutter_install" "$flutter_link"

    path_line='export PATH="$HOME/develop/flutter/bin:$PATH"'

    touch "$HOME/.bashrc"

    if ! grep -Fqx "$path_line" "$HOME/.bashrc"; then
        {
            printf '\n'
            printf '# Flutter SDK\n'
            printf '%s\n' "$path_line"
        } >> "$HOME/.bashrc"
    fi

    export PATH="$HOME/develop/flutter/bin:$PATH"

    log "Enabling Flutter targets"

    flutter config \
        --enable-android \
        --enable-web \
        --enable-linux-desktop

    echo
    flutter --version
    dart --version
)

show_versions() {
    export PATH="$HOME/develop/flutter/bin:/usr/local/go/bin:$HOME/go/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
    export NVM_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvm"

    if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        set +u
        source "$NVM_DIR/nvm.sh"
        set -u

        nvm use "$NODE_VERSION" >/dev/null
    fi

    if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
        set +u
        source "$HOME/.sdkman/bin/sdkman-init.sh"
        set -u

        sdk use java "$JAVA_VERSION" >/dev/null
    fi

    log "Installed development tools"

    printf '%-10s %s\n' "Go:"      "$(go version)"
    printf '%-10s %s\n' "Rust:"    "$(rustc --version)"
    printf '%-10s %s\n' "Cargo:"   "$(cargo --version)"
    printf '%-10s %s\n' "Rustup:"  "$(rustup --version)"
    printf '%-10s %s\n' "NVM:"     "$(nvm --version)"
    printf '%-10s %s\n' "Node:"    "$(node --version)"
    printf '%-10s %s\n' "npm:"     "$(npm --version)"
    printf '%-10s %s\n' "pnpm:"    "$(pnpm --version)"
    printf '%-10s %s\n' "Java:"    "$(java --version 2>&1 | sed -n '1p')"
    printf '%-10s %s\n' "Javac:"   "$(javac --version 2>&1)"
    printf '%-10s %s\n' "Flutter:" "$(flutter --version | sed -n '1p')"
    printf '%-10s %s\n' "Dart:"    "$(dart --version 2>&1)"
    printf '%-10s %s\n' "uv:"      "$(uv --version)"
    printf '%-10s %s\n' "Git:"     "$(git --version)"
    printf '%-10s %s\n' "GitHub:"  "$(gh --version | sed -n '1p')"
    printf '%-10s %s\n' "GCC:"     "$(gcc --version | sed -n '1p')"
    printf '%-10s %s\n' "Clang:"   "$(clang --version | sed -n '1p')"
    printf '%-10s %s\n' "CMake:"   "$(cmake --version | sed -n '1p')"

    echo
    echo "Managed Python installations:"
    uv python list
}

ask_to_reboot() {
    local answer=""

    echo

    if ! read -r -p "Reboot the computer now? [y/N] " answer; then
        answer=""
    fi

    if [[ "$answer" =~ ^[Yy]$ ]]; then
        log "Rebooting"
        sudo reboot
    else
        echo
        echo "Reboot skipped."
        echo "Reboot later with:"
        echo "  sudo reboot"
    fi
}

main() {
    check_requirements

    log "Requesting sudo authentication"
    sudo -v

    update_opensuse
    install_system_dev_packages

    install_go
    export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"

    install_node_stack

    install_rust
    export PATH="$HOME/.cargo/bin:$PATH"

    install_uv_and_python
    export PATH="$HOME/.local/bin:$PATH"

    install_sdkman_and_java
    load_sdkman_java

    install_android_studio

    install_flutter
    export PATH="$HOME/develop/flutter/bin:$PATH"

    show_versions

    echo
    echo "Base system and development tools installed successfully."
    echo
    echo "Android Studio still requires first-run Android SDK setup."
    echo "After reboot:"
    echo
    echo "  1. Authenticate GitHub:"
    echo "       gh auth login"
    echo
    echo "  2. Start Android Studio:"
    echo "       android-studio"
    echo
    echo "  3. Install API 35, API 36, Build Tools 36.0.0,"
    echo "     Platform Tools, Command-line Tools, Emulator, CMake and NDK."
    echo
    echo "  4. Configure ANDROID_HOME and accept Android licenses."
    echo

    ask_to_reboot
}

main "$@"
