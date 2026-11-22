#!/usr/bin/env bash
# nixpm installer
# Install:   cp scripts/install.sh ... (or curl -fsSL .../scripts/install.sh | bash)
# Uninstall: rm ~/.local/bin/nixpm

set -euo pipefail

# The v0.3.1 release ships bin/nixpm and SHA256SUMS as release assets, so the
# installer pins to the latest release instead of main's head. One push to
# main can no longer change what this script installs.
BASE="https://github.com/strtPath/nixpm/releases"
DESTDIR="${PREFIX:-${HOME}/.local}/bin"

# Resolve the latest release tag once, then fetch both assets from that tag.
# Two separate releases/latest requests could straddle a publish and pair
# one release's checksums with the next release's payload.
latest_tag() {
  # gsub strips the CR from CRLF header lines, or the tag fails sanitizing.
  local loc
  if command -v curl >/dev/null 2>&1; then
    loc="$(curl -fsSI "$BASE/latest" | awk 'tolower($1)=="location:"{v=$2} END{gsub(/\r/,"",v); print v}')"
  else
    loc="$(wget -q --spider --server-response "$BASE/latest" 2>&1 \
      | awk 'tolower($1)=="location:"{v=$2} END{gsub(/\r/,"",v); print v}')"
  fi
  case "$loc" in
    */releases/tag/*) printf '%s\n' "${loc##*/}" ;;
    *) return 1 ;;
  esac
}

main() {
  echo "==> Installing nixpm..."

  # Do NOT abort when nix is missing (R8): nixpm installs fine without it and
  # its own preflight self-reports at first use. This pointer is a courtesy.
  if ! command -v nix >/dev/null 2>&1; then
    echo "=> Warning: Nix is not installed yet; nixpm will report this at first use."
    echo "   Install Nix: https://nixos.org/download/"
  fi

  mkdir -p "$DESTDIR"

  # curl pins the protocol so a redirect can't downgrade to plain HTTP (a
  # MITM vector for code that runs as the user). wget offers no equivalent:
  # its --https-only only governs link following in recursive mode and does
  # nothing on a single-URL fetch, so the fallback relies on the https://
  # URL itself. curl is the primary path on essentially every target.
  if command -v curl >/dev/null 2>&1; then
    fetch() { curl -fsSL --proto '=https' --tlsv1.2 "$1" -o "$2"; }
  elif command -v wget >/dev/null 2>&1; then
    fetch() { wget -q "$1" -O "$2"; }
  else
    echo "=> Neither curl nor wget found. Install one and try again."
    exit 1
  fi

  # Stage inside DESTDIR so the final mv stays on one filesystem and is
  # atomic. A connection drop mid-download can never leave a truncated but
  # executable nixpm on PATH: it only lands once complete and verified.
  WORK="$(mktemp -d "$DESTDIR/.nixpm-install.XXXXXX")"
  trap 'rm -rf "$WORK"' EXIT

  # Both assets then come from the same tag, so a publish mid-install can
  # never mix two releases. A tag we cannot sanity-check means no install.
  TAG="$(latest_tag || true)"
  case "$TAG" in '' | *[!A-Za-z0-9._+-]*)
    echo "=> Could not resolve the latest release tag; refusing to guess."
    exit 1 ;;
  esac
  REL="$BASE/download/$TAG"

  # Checksums first: a release missing its SHA256SUMS asset fails before the
  # payload is even fetched.
  fetch "$REL/SHA256SUMS" "$WORK/SHA256SUMS"
  fetch "$REL/nixpm" "$WORK/nixpm"

  # Verify the bytes before chmod or mv. Refusing beats installing an
  # unverified script, so no checksum tool means no install.
  if command -v sha256sum >/dev/null 2>&1; then
    ( cd "$WORK" && exec sha256sum -c SHA256SUMS )
  elif command -v shasum >/dev/null 2>&1; then
    ( cd "$WORK" && exec shasum -a 256 -c SHA256SUMS )
  else
    echo "=> Neither sha256sum nor shasum found; refusing to install unverified bytes."
    exit 1
  fi

  chmod 755 "$WORK/nixpm"
  mv "$WORK/nixpm" "$DESTDIR/nixpm"

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
