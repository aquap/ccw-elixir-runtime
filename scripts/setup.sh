#!/usr/bin/env bash
# Run after the runtime tarball is extracted into $HOME.
#
# - Relocates OTP (it bakes absolute paths at build time) for the current $HOME.
# - Wires asdf, HEX_MIRROR_URL, and a UTF-8 locale into ~/.bashrc (idempotent).
# - Starts the hex.pm proxy in the background.
#
# Safe to re-run; everything is guarded.

set -euo pipefail

export LC_ALL=C.UTF-8 LANG=C.UTF-8

RUNTIME_DIR="$HOME/.ccw-elixir-runtime"
ASDF_DIR="$HOME/.asdf"
MARKER="# >>> ccw-elixir-runtime >>>"
ENDMARK="# <<< ccw-elixir-runtime <<<"
PROXY_PORT=8789
PROXY_LOG="/tmp/hex_proxy.log"

if [ ! -d "$ASDF_DIR" ] || [ ! -d "$RUNTIME_DIR" ]; then
  echo "setup.sh: expected $ASDF_DIR and $RUNTIME_DIR to exist; did extraction succeed?" >&2
  exit 1
fi

# --- 1. Relocate OTP ---------------------------------------------------------
# OTP's `Install` script rewrites the absolute paths baked into erts/bin/erl
# and friends. asdf-erlang puts each install at $ASDF_DIR/installs/erlang/<ver>/.
for otp_root in "$ASDF_DIR"/installs/erlang/*/; do
  [ -d "$otp_root" ] || continue
  if [ -x "$otp_root/Install" ]; then
    echo "setup.sh: relocating OTP at $otp_root"
    "$otp_root/Install" -minimal "${otp_root%/}" >/dev/null
  fi
done

# --- 2. Reshim asdf so $ASDF_DIR/shims is current ---------------------------
# shellcheck disable=SC1091
. "$ASDF_DIR/asdf.sh"
asdf reshim >/dev/null 2>&1 || true

# --- 3. Wire ~/.bashrc (idempotent) -----------------------------------------
BASHRC="$HOME/.bashrc"
touch "$BASHRC"
if ! grep -qF "$MARKER" "$BASHRC"; then
  echo "setup.sh: appending env to $BASHRC"
  cat >> "$BASHRC" <<EOF

$MARKER
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
. "\$HOME/.asdf/asdf.sh"
export HEX_MIRROR_URL=http://127.0.0.1:${PROXY_PORT}
$ENDMARK
EOF
else
  echo "setup.sh: ~/.bashrc already wired"
fi

# --- 4. Start hex_proxy ------------------------------------------------------
if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${PROXY_PORT}\$"; then
  echo "setup.sh: hex_proxy already listening on :${PROXY_PORT}"
else
  echo "setup.sh: starting hex_proxy on :${PROXY_PORT} (log: $PROXY_LOG)"
  nohup python3 "$RUNTIME_DIR/hex_proxy.py" >"$PROXY_LOG" 2>&1 &
  disown || true
  # Wait briefly for it to bind.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${PROXY_PORT}\$"; then
      break
    fi
    sleep 0.2
  done
fi

# --- 5. Smoke test -----------------------------------------------------------
echo "setup.sh: smoke test"
erl -noshell -eval 'io:format("erl ok ~s~n", [erlang:system_info(otp_release)]), halt().'
elixir -e 'IO.puts("elixir ok " <> System.version())'

echo "setup.sh: done. Open a new shell (or 'source ~/.bashrc') to pick up env."
