#!/usr/bin/env bash
# nixpm installer
# Install:   curl -fsSL https://raw.githubusercontent.com/YOURUSER/nixpm/main/install.sh | bash
# Uninstall: rm ~/.local/bin/nixpm

set -euo pipefail

REPO="https://github.com/YOURUSER/nixpm"
RAW="https://raw.githubusercontent.com/YOURUSER/nixpm/main/bin/nixpm"
DESTDIR="${PREFIX:-${HOME}/.local}/bin"

main() {
  echo "==> Installing nixpm..."

  if ! command -v nix >/dev/null 2>&1; then
    echo "=> Nix is not installed."
    echo "   Install Nix first: https://nixos.org/download/"
    exit 1
  fi

  mkdir -p "$DESTDIR"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$RAW" -o "$DESTDIR/nixpm"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$RAW" -O "$DESTDIR/nixpm"
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
