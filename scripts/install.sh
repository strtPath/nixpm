#!/usr/bin/env bash
# nixpm installer
# Install:   cp scripts/install.sh ... (or curl -fsSL .../scripts/install.sh | bash)
# Uninstall: rm ~/.local/bin/nixpm

set -euo pipefail

RAW="https://raw.githubusercontent.com/strtPath/nixpm/main/bin/nixpm"
DESTDIR="${PREFIX:-${HOME}/.local}/bin"

main() {
  echo "==> Installing nixpm..."

  # Do NOT abort when nix is missing (R8): nixpm installs fine without it and
  # its own preflight self-reports at first use. This pointer is a courtesy.
  if ! command -v nix >/dev/null 2>&1; then
    echo "=> Warning: Nix is not installed yet; nixpm will report this at first use."
    echo "   Install Nix: https://nixos.org/download/"
  fi

  mkdir -p "$DESTDIR"

  # Protocol pinned: this script downloads code that runs as the user, so a
  # network fluke downgrading to plain HTTP is a MITM vector — https required.
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --proto '=https' --tlsv1.2 "$RAW" -o "$DESTDIR/nixpm"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --https-only "$RAW" -O "$DESTDIR/nixpm"
  else
    echo "=> Neither curl nor wget found. Install one and try again."
    exit 1
  fi

  chmod +x "$DESTDIR/nixpm"

  echo "==> Installed to $DESTDIR/nixpm"

  case ":${PATH}:" in
    *:"$DESTDIR":*) ;;
    *)
      echo "=> Add $DESTDIR to your PATH:"
      echo "   export PATH=\"$DESTDIR:\$PATH\""
      ;;
  esac
}

main "$@"
