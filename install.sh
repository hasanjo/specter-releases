#!/usr/bin/env bash
#
# Specter installer.
#
#   curl -fsSL https://your-url/install.sh | bash
#
# Downloads the right prebuilt `specter` binary for this machine from GitHub
# Releases and installs it to ~/.specter/bin (override with SPECTER_INSTALL).
#
# Env overrides:
#   SPECTER_REPO     GitHub "owner/repo" to download from   (default below)
#   SPECTER_VERSION  Tag to install, e.g. v0.1.0            (default: latest)
#   SPECTER_INSTALL  Install root                           (default: ~/.specter)
#
set -euo pipefail

# ---------------------------------------------------------------------------
# TODO: set this to your GitHub repository (owner/name).
SPECTER_REPO="${SPECTER_REPO:-hasanjo/specter-releases}"
# ---------------------------------------------------------------------------

SPECTER_INSTALL="${SPECTER_INSTALL:-$HOME/.specter}"
BIN_DIR="$SPECTER_INSTALL/bin"

info()  { printf '\033[1;36m=>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required but not installed."

# --- detect platform --------------------------------------------------------
os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
  Linux*)                 asset_os="linux"; ext="" ;;
  Darwin*)                asset_os="osx";   ext="" ;;
  MINGW*|MSYS*|CYGWIN*)   asset_os="win";   ext=".exe" ;;
  *) die "unsupported operating system: $os" ;;
esac

case "$arch" in
  x86_64|amd64)           asset_arch="x64" ;;
  arm64|aarch64)          asset_arch="arm64" ;;
  *) die "unsupported architecture: $arch" ;;
esac

asset="specter-${asset_os}-${asset_arch}${ext}"

# --- resolve version --------------------------------------------------------
version="${SPECTER_VERSION:-}"
if [ -z "$version" ]; then
  info "Resolving latest release…"
  # Follow the /releases/latest redirect to read the tag (no jq needed).
  effective="$(curl -fsSL -o /dev/null -w '%{url_effective}' \
    "https://github.com/${SPECTER_REPO}/releases/latest" || true)"
  version="${effective##*/tag/}"
  [ -n "$version" ] && [ "$version" != "$effective" ] \
    || die "could not determine the latest version. Set SPECTER_VERSION explicitly."
fi

url="https://github.com/${SPECTER_REPO}/releases/download/${version}/${asset}"

# --- download ---------------------------------------------------------------
mkdir -p "$BIN_DIR"
target="$BIN_DIR/specter${ext}"

info "Downloading ${asset} (${version})…"
tmp="$(mktemp)"
curl -fSL --progress-bar "$url" -o "$tmp" \
  || die "download failed: $url"

chmod +x "$tmp"
mv -f "$tmp" "$target"
info "Installed to $target"

# --- PATH setup -------------------------------------------------------------
add_to_path_hint() {
  case ":$PATH:" in
    *":$BIN_DIR:"*) return 0 ;;
  esac

  # Append to the most relevant shell profile so new shells pick it up.
  local line="export PATH=\"$BIN_DIR:\$PATH\""
  local profile=""
  case "${SHELL:-}" in
    *zsh)  profile="$HOME/.zshrc" ;;
    *bash) profile="$HOME/.bashrc" ;;
    *)     profile="$HOME/.profile" ;;
  esac

  if [ -n "$profile" ] && ! grep -qsF "$BIN_DIR" "$profile" 2>/dev/null; then
    printf '\n# Added by the Specter installer\n%s\n' "$line" >> "$profile"
    info "Added $BIN_DIR to PATH in $profile"
    warn "Open a new terminal, or run:  export PATH=\"$BIN_DIR:\$PATH\""
  else
    warn "Add $BIN_DIR to your PATH to run 'specter' from anywhere."
  fi

  if [ "$asset_os" = "win" ]; then
    warn "To use 'specter' in PowerShell/cmd too, add this folder to your Windows PATH:"
    warn "    $BIN_DIR"
  fi
}
add_to_path_hint

echo
info "Done. Verify with:  specter --version"
info "Then run inside any repo:  specter review"
