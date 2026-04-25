#!/usr/bin/env bash
# Run after the runtime tarball is extracted into $HOME.
#
# - Relocates OTP (it bakes absolute paths at build time) for the current $HOME.
# - Pins erlang/elixir in $HOME/.tool-versions so asdf shims resolve.
# - Wires asdf shims, HEX_MIRROR_URL, and a UTF-8 locale into ~/.bashrc
#   (idempotent; the marker block is rewritten on each run so upgrades pick
#   up changes).
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
if [ ! -x "$ASDF_DIR/bin/asdf" ]; then
  echo "setup.sh: $ASDF_DIR/bin/asdf is missing or not executable" >&2
  exit 1
fi

# asdf 0.16+ has no asdf.sh — shims live at $ASDF_DIR/shims and the binary at
# $ASDF_DIR/bin/asdf. Both must be on PATH for the rest of this script.
export ASDF_DATA_DIR="$ASDF_DIR"
export PATH="$ASDF_DIR/bin:$ASDF_DIR/shims:$PATH"

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

# --- 2. Pin tool versions ----------------------------------------------------
# The tarball doesn't include $HOME/.tool-versions (it lives outside $ASDF_DIR).
# Without it, asdf shims fail with "No version is set for command erl".
# Recreate it from versions.env (idempotent; preserves any unrelated entries
# the user already has).
# shellcheck disable=SC1091
. "$RUNTIME_DIR/versions.env"
TOOL_VERSIONS="$HOME/.tool-versions"
touch "$TOOL_VERSIONS"
pin_tool() {
  local tool="$1" version="$2"
  if grep -qE "^${tool}( |\$)" "$TOOL_VERSIONS"; then
    if ! grep -qE "^${tool} ${version}\$" "$TOOL_VERSIONS"; then
      sed -i.bak -E "s|^${tool} .*|${tool} ${version}|" "$TOOL_VERSIONS"
      rm -f "${TOOL_VERSIONS}.bak"
    fi
  else
    printf '%s %s\n' "$tool" "$version" >> "$TOOL_VERSIONS"
  fi
}
pin_tool erlang "$OTP_VERSION"
pin_tool elixir "$ELIXIR_VERSION"
echo "setup.sh: pinned $TOOL_VERSIONS to erlang $OTP_VERSION, elixir $ELIXIR_VERSION"

# --- 3. Reshim so $ASDF_DIR/shims is current --------------------------------
asdf reshim >/dev/null 2>&1 || true

# --- 4. Wire ~/.bashrc (idempotent, self-updating) --------------------------
# Always rewrite the marker block so older installs (which sourced the now-gone
# asdf.sh) get the new PATH-based snippet.
BASHRC="$HOME/.bashrc"
touch "$BASHRC"
if grep -qF "$MARKER" "$BASHRC"; then
  sed -i.bak "/$MARKER/,/$ENDMARK/d" "$BASHRC"
  rm -f "${BASHRC}.bak"
  # Drop a trailing blank line if we just left one behind.
  sed -i -e ':a' -e '/^\n*$/{$d;N;ba' -e '}' "$BASHRC"
fi
cat >> "$BASHRC" <<EOF

$MARKER
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export ASDF_DATA_DIR="\$HOME/.asdf"
export PATH="\$HOME/.asdf/bin:\$HOME/.asdf/shims:\$PATH"
export HEX_MIRROR_URL=http://127.0.0.1:${PROXY_PORT}
$ENDMARK
EOF
echo "setup.sh: wrote env block to $BASHRC"

# --- 5. Start hex_proxy ------------------------------------------------------
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

# --- 6. Smoke test -----------------------------------------------------------
echo "setup.sh: smoke test"
erl -noshell -eval 'io:format("erl ok ~s~n", [erlang:system_info(otp_release)]), halt().'
elixir -e 'IO.puts("elixir ok " <> System.version())'

echo "setup.sh: done. Open a new shell (or 'source ~/.bashrc') to pick up env."
