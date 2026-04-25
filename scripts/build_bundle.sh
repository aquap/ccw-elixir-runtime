#!/usr/bin/env bash
# Build the CCW Elixir runtime tarball.
#
# Run this once per version bump on a Claude Code Web session (so the
# binaries match the target glibc/arch). The tarball it produces is
# uploaded as a GitHub release asset; CCW startup pulls it down.
#
# Output:
#   /tmp/ccw-elixir-runtime-linux-<arch>.tar.gz
#   /tmp/ccw-elixir-runtime-linux-<arch>.tar.gz.sha256

set -euo pipefail

export LC_ALL=C.UTF-8 LANG=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$REPO_DIR/versions.env"

ARCH="$(uname -m)"
OUT_NAME="ccw-elixir-runtime-linux-${ARCH}.tar.gz"
OUT_PATH="/tmp/${OUT_NAME}"

ASDF_DIR="$HOME/.asdf"
RUNTIME_DIR="$HOME/.ccw-elixir-runtime"

echo "==> Build host: $(uname -a)"
echo "==> HOME: $HOME"
echo "==> Versions: asdf=$ASDF_REF otp=$OTP_VERSION elixir=$ELIXIR_VERSION"

# --- 1. asdf -----------------------------------------------------------------
if [ -d "$ASDF_DIR" ]; then
  echo "==> $ASDF_DIR already exists; refusing to clobber. Move it aside and rerun." >&2
  exit 1
fi
echo "==> Cloning asdf $ASDF_REF"
git clone --depth 1 --branch "$ASDF_REF" https://github.com/asdf-vm/asdf.git "$ASDF_DIR"

# shellcheck disable=SC1091
. "$ASDF_DIR/asdf.sh"

# --- 2. Build deps for OTP ---------------------------------------------------
# kerl (used by asdf-erlang) needs these. Apt-get may already have most of them
# in the CCW image; install what's missing.
echo "==> Installing OTP build deps (sudo apt-get)"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
  build-essential autoconf m4 libncurses-dev libssl-dev \
  libwxgtk3.2-dev libgl1-mesa-dev libglu1-mesa-dev libpng-dev \
  libssh-dev unixodbc-dev xsltproc fop libxml2-utils \
  unzip curl ca-certificates git

# --- 3. Erlang ---------------------------------------------------------------
echo "==> Adding asdf erlang plugin"
asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git
echo "==> Installing Erlang/OTP $OTP_VERSION (this is the slow step)"
KERL_BUILD_DOCS=no KERL_INSTALL_MANPAGES=no KERL_INSTALL_HTMLDOCS=no \
  asdf install erlang "$OTP_VERSION"
asdf global erlang "$OTP_VERSION"

# --- 4. Elixir ---------------------------------------------------------------
echo "==> Adding asdf elixir plugin"
asdf plugin add elixir https://github.com/asdf-vm/asdf-elixir.git
echo "==> Installing Elixir $ELIXIR_VERSION"
asdf install elixir "$ELIXIR_VERSION"
asdf global elixir "$ELIXIR_VERSION"

asdf reshim

# --- 5. Runtime helpers ------------------------------------------------------
echo "==> Staging $RUNTIME_DIR"
rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR"
cp "$SCRIPT_DIR/setup.sh"      "$RUNTIME_DIR/setup.sh"
cp "$SCRIPT_DIR/hex_proxy.py"  "$RUNTIME_DIR/hex_proxy.py"
cp "$REPO_DIR/versions.env"    "$RUNTIME_DIR/versions.env"
chmod +x "$RUNTIME_DIR/setup.sh"

# --- 6. Smoke test -----------------------------------------------------------
echo "==> Smoke test"
erl -noshell -eval 'io:format("erl ok ~s~n", [erlang:system_info(otp_release)]), halt().'
elixir -e 'IO.puts("elixir ok " <> System.version())'

# --- 7. Tar ------------------------------------------------------------------
echo "==> Creating $OUT_PATH"
tar -czf "$OUT_PATH" \
  -C "$HOME" \
  --transform 's,^\.asdf,.asdf,' \
  --transform 's,^\.ccw-elixir-runtime,.ccw-elixir-runtime,' \
  .asdf .ccw-elixir-runtime

sha256sum "$OUT_PATH" | awk '{print $1}' > "${OUT_PATH}.sha256"

echo
echo "==> Done."
echo "    Tarball : $OUT_PATH"
echo "    SHA256  : $(cat "${OUT_PATH}.sha256")"
echo "    Size    : $(du -h "$OUT_PATH" | awk '{print $1}')"
echo
echo "Next: upload $OUT_NAME (and the .sha256) to a GitHub release"
echo "      on aquap/ccw-elixir-runtime tagged $RELEASE_TAG."
