# nixpm

A tiny, friendly package-manager wrapper around [Nix](https://nixos.org/). Inspired by `pacman` and Homebrew, it gives you simple commands for everyday Nix operations — plus optional desktop-menu integration so newly-installed GUI apps show up right away instead of after a logout.

---

## Features

- **`search`**, **`install`**, **`remove`**, **`list`** — the basics, done cleanly
- **`info`** — one-line metadata (description, homepage, license, main program)
- **`apps`** — see which installed Nix packages ship `.desktop` files
- **Auto desktop reload** — detects Omarchy, Hyprland, Sway, or KDE Plasma and reloads the launcher/menu after install/remove
- **Pure Bash** — no Python, no compiled code, one small script
- **Works everywhere Nix works** — Arch, NixOS, macOS, WSL, you name it

---

## Install

### Quick (curl)

> ⚠️ Hosted at `strtPath/nixpm`.

```bash
curl -fsSL https://raw.githubusercontent.com/strtPath/nixpm/main/scripts/install.sh | bash
```

### Manual

```bash
git clone https://github.com/strtPath/nixpm.git
cd nixpm
make install        # copies to ~/.local/bin
```

Or just copy `bin/nixpm` anywhere on your `PATH` and `chmod +x` it.

---

## Usage

```bash
# Search
nixpm search firefox

# Install (reloads your desktop launcher/menu automatically on supported DEs)
nixpm install firefox

# Remove
nixpm remove firefox

# List installed packages
nixpm list

# Which ones have menu entries?
nixpm apps

# Show package metadata
nixpm info pavucontrol

# Enter a temporary shell with the package available
nixpm shell go

# Update nix channels / flake inputs
nixpm update

# Upgrade everything
nixpm upgrade
```

### Global flags

| Flag | Effect |
|------|--------|
| `--no-restart` | Skip the automatic desktop-menu reload after install/remove/upgrade |
| `-h`, `--help` | Show help |
| `-V`, `--version` | Show version |

---

## Desktop integration (optional)

### The problem

Nix installs packages to `/nix/store/…` and symlinks them into `~/.nix-profile/`. Most desktop environments and launchers search for `.desktop` files using the `XDG_DATA_DIRS` environment variable. By default this **does not include** `~/.nix-profile/share`, so GUI apps installed via Nix may not appear in your app menu until you log out and back in.

### What nixpm does

After `install`, `remove`, or `upgrade`, `nixpm` attempts to reload your session so launchers notice the change:

| Desktop / WM | Action |
|-------------|--------|
| **Omarchy** (Hyprland + Quickshell) | `omarchy restart shell` |
| **Hyprland** (plain) | `hyprctl reload` + hint to restart launcher |
| **Sway** | `swaymsg reload` |
| **KDE Plasma** | `kbuildsycoca6` (rebuilds app database) |
| **Other / none** | Prints a notice to log out or restart your launcher |

You can disable this entirely:

```bash
nixpm --no-restart install firefox
```

Or in your config (see below).

### Persistent fix for Hyprland / Sway

If you want Nix apps to be visible **permanently** without needing to reload every time, add the Nix profile paths to your compositor's startup environment.

**`~/.config/hypr/envs.lua`** (or equivalent):
```lua
local xdg = os.getenv("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
if not xdg:find("/.nix-profile/share", 1, true) then
  xdg = xdg .. ":" .. os.getenv("HOME") .. "/.nix-profile/share:/nix/var/nix/profiles/default/share"
end
hl.env("XDG_DATA_DIRS", xdg)

local path = os.getenv("PATH") or "/usr/local/bin:/usr/bin"
if not path:find("/.nix-profile/bin", 1, true) then
  path = os.getenv("HOME") .. "/.nix-profile/bin:/nix/var/nix/profiles/default/bin:" .. path
end
hl.env("PATH", path)
```

Then in `~/.config/hypr/hyprland.lua`:
```lua
require("hypr.envs")
```

Also create `~/.config/environment.d/90-nix.conf` for systemd user services:
```ini
XDG_DATA_DIRS=/usr/local/share:/usr/share:/home/YOURNAME/.nix-profile/share:/nix/var/nix/profiles/default/share
```

For **Sway**, add to your `~/.config/sway/config`:
```sway
set $nix_datadir $HOME/.nix-profile/share:/nix/var/nix/profiles/default/share
set $nix_bindir $HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin

exec systemctl --user set-environment XDG_DATA_DIRS=$XDG_DATA_DIRS:$nix_datadir
exec systemctl --user set-environment PATH=$nix_bindir:$PATH
```

---

## Configuration

Create `~/.config/nixpm/config` (bash-sourced, optional):

```bash
# Which nixpkgs attribute path to use
NIXPM_NIXPKGS="nixpkgs"

# Auto-reload desktop session after install/remove/upgrade
#   true  = always try (warn if unsupported)
#   auto  = only if a supported DE/WM is detected (default)
#   false = never try
NIXPM_RESTART_MENU="auto"
```

---

## Requirements

- [Nix](https://nixos.org/download/) package manager (multi-user mode recommended)
- Bash 4.0+
- `jq` (used for pretty `info` output)

---

## Why not just use `nix-env`?

You absolutely can — `nixpm` is just a thin wrapper that:

1. Saves you typing `nix-env -iA nixpkgs.` prefixes
2. Formats `nix search` output so it's readable
3. Restarts your desktop environment automatically so new apps appear
4. Provides familiar, short aliases (`search`, `install`, `remove`, `list`)

If you prefer the raw Nix CLI, keep using it. `nixpm` is for people who want the Nix ecosystem without memorizing `nix-env` flags.

---

## License

MIT
