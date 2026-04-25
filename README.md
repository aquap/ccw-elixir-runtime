# ccw-elixir-runtime

Prebuilt asdf + Erlang/OTP + Elixir tarball for Claude Code Web sessions.

Each fresh CCW instance has no Elixir toolchain. Compiling OTP from source
takes 5–10 minutes; this repo ships a tarball that drops into `$HOME` in
seconds.

## Use it

Paste this into your CCW startup commands (replace `<TAG>` with the
release tag you want to pin to — see [Releases](../../releases)):

```bash
set -euo pipefail
export LC_ALL=C.UTF-8 LANG=C.UTF-8
URL="https://github.com/aquap/ccw-elixir-runtime/releases/download/<TAG>/ccw-elixir-runtime-linux-x86_64.tar.gz"
curl -fsSL "$URL" | tar -xzf - -C "$HOME"
"$HOME/.ccw-elixir-runtime/setup.sh"
```

What it leaves behind, in order:

1. `~/.asdf/` — asdf with Erlang and Elixir already installed.
2. `~/.ccw-elixir-runtime/` — `setup.sh`, `hex_proxy.py`, `versions.env`.
3. `~/.bashrc` — appended with `LC_ALL=C.UTF-8`, `. ~/.asdf/asdf.sh`, and
   `HEX_MIRROR_URL=http://127.0.0.1:8789` (guarded by markers; safe to re-run).
4. A backgrounded `hex_proxy.py` listening on `127.0.0.1:8789`, forwarding
   to `https://repo.hex.pm`. Workaround for the CCW egress proxy that
   rejects Erlang's `:httpc` but accepts Python's TLS stack.

After it runs, open a new shell (or `source ~/.bashrc`) and `mix deps.get`
will work against the proxy automatically.

## Pinned versions

See [`versions.env`](versions.env). Current:

- asdf `v0.19.0` (Go binary; the bash-era `asdf.sh` is gone, so the bashrc
  snippet now just puts `~/.asdf/bin` and `~/.asdf/shims` on `PATH`).
- Erlang/OTP `27.2`
- Elixir `1.18.3-otp-27`

## Cutting a new release

The tarball must be built on a Linux box matching the CCW sandbox's glibc
and architecture. Easiest: build inside a CCW session.

```bash
git clone https://github.com/aquap/ccw-elixir-runtime
cd ccw-elixir-runtime
./scripts/build_bundle.sh
# ~10–15 min later:
#   /tmp/ccw-elixir-runtime-linux-x86_64.tar.gz
#   /tmp/ccw-elixir-runtime-linux-x86_64.tar.gz.sha256
```

Then:

1. Bump `versions.env` (`OTP_VERSION`, `ELIXIR_VERSION`, `RELEASE_TAG`).
2. Tag and push: `git tag otp27.2-elixir1.18.3-v1 && git push --tags`.
3. Create a GitHub release on that tag, attach the tarball + `.sha256`.
4. Update the `<TAG>` in your CCW startup commands.

## Layout

```
versions.env                  Pinned versions, sourced by build_bundle.sh.
scripts/build_bundle.sh       One-off build. Run on a CCW session.
scripts/setup.sh              Goes inside the tarball; runs at $HOME after extract.
scripts/hex_proxy.py          Goes inside the tarball; started by setup.sh.
```

## Tarball contents

```
.asdf/                        → ~/.asdf
.ccw-elixir-runtime/
  setup.sh
  hex_proxy.py
  versions.env                → ~/.ccw-elixir-runtime/
```
