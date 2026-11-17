# Changelog

## v0.3.1

Small machines can no longer be bricked by nixpm's own good intentions.

- `search` builds a local index once and greps that for later queries.
  On machines under ~6 GB the first whole-package-set evaluation is
  refused up front (exit 3) with a pointer to `nixpm install <name>`,
  instead of freezing the box. Tune with `NIXPM_MIN_INDEX_MEM_MB`
  (0 disables the guard); cgroup limits are honoured, so containers
  are judged by their own memory cap.
- `upgrade` with no arguments scans the whole package set — same guard,
  same exit code. `upgrade <name>` still runs ungated.
- Search queries are matched literally: `nixpm search 'lib(foo'` no
  longer crashes awk, and `a.b` no longer matches `aXb`.
- `nixpm help`, `--version` and a clean no-nix error now work on a
  machine without Nix — two readable lines pointing at nixos.org,
  no raw `\n`.
- Unknown commands are caught by nixpm before Nix gets a chance to
  complain about them.
- `--no-restart` is accepted before or after the subcommand and can no
  longer be mistaken for a package name.
- `apps` finds `.desktop` files in any output of multi-output packages
  (geany and friends).
- `install.sh` no longer aborts when Nix is missing; nixpm's own
  preflight reports that at first use instead.
- Long index builds print a heartbeat every 10 seconds so you know
  nothing has hung.
- A low-RAM machine that already has an index keeps searching it (with
  a staleness warning) instead of being locked out of `search` entirely.
- `search --rebuild` forces a fresh index when you want one.
- `install.sh` pins its download to HTTPS (a downgrade on a flaky
  network is a MITM vector for a script that runs as you).
- nixpm now says so at startup if it meets bash 3 (macOS default),
  rather than dying inside `mapfile`.

One caveat about the memory guard: it protects the **cold-cache** case.
A machine whose `~/.cache/nix` is already warm can finish the same
whole-package-set eval in seconds — the guard cannot tell the two
apart and refuses anyway. Anyone verifying guard behaviour on a small
machine must start from an empty eval cache, or the run certifies
nothing.

## v0.3.0

Initial single-file CLI: pacman-flavoured commands, local search index,
upgrade preview, desktop-menu reload. Earlier history lives in the git log.
