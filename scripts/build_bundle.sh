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

UNAME_M="$(uname -m)"
case "$UNAME_M" in
  x86_64)         ASDF_ARCH=amd64 ;;
  aarch64|arm64)  ASDF_ARCH=arm64 ;;
  *) echo "==> unsupported arch: $UNAME_M" >&2; exit 1 ;;
esac
OUT_NAME="ccw-elixir-runtime-linux-${UNAME_M}.tar.gz"
OUT_PATH="/tmp/${OUT_NAME}"

ASDF_DIR="$HOME/.asdf"
RUNTIME_DIR="$HOME/.ccw-elixir-runtime"

# asdf 0.16+ is a Go binary; data lives in $ASDF_DATA_DIR (defaults to
# $HOME/.asdf), and shims must be on PATH directly (no asdf.sh anymore).
export ASDF_DATA_DIR="$ASDF_DIR"
export PATH="$ASDF_DIR/bin:$ASDF_DIR/shims:$PATH"

echo "==> Build host: $(uname -a)"
echo "==> HOME: $HOME"
echo "==> Versions: asdf=$ASDF_VERSION otp=$OTP_VERSION elixir=$ELIXIR_VERSION"

# --- 1. asdf -----------------------------------------------------------------
if [ -d "$ASDF_DIR" ]; then
  echo "==> $ASDF_DIR already exists; refusing to clobber. Move it aside and rerun." >&2
  exit 1
fi
echo "==> Downloading asdf $ASDF_VERSION (linux-$ASDF_ARCH)"
mkdir -p "$ASDF_DIR/bin"
ASDF_TARBALL="asdf-${ASDF_VERSION}-linux-${ASDF_ARCH}.tar.gz"
curl -fsSL \
  "https://github.com/asdf-vm/asdf/releases/download/${ASDF_VERSION}/${ASDF_TARBALL}" \
  | tar -xz -C "$ASDF_DIR/bin"
chmod +x "$ASDF_DIR/bin/asdf"
asdf --version

# --- 2. Build deps for OTP ---------------------------------------------------
# kerl (used by asdf-erlang) needs these. Apt-get may already have most of them
# in the CCW image; install what's missing.
# Skip /etc/apt/sources.list.d/ entirely so broken third-party PPAs on the
# build host (e.g. deadsnakes, ondrej/php returning 403) can't fail the build.
echo "==> Installing OTP build deps (sudo apt-get)"
APT_OPTS=(-o "Dir::Etc::SourceParts=/dev/null")
sudo apt-get "${APT_OPTS[@]}" update -qq
sudo apt-get "${APT_OPTS[@]}" install -y --no-install-recommends \
  build-essential autoconf m4 libncurses-dev libssl-dev \
  libwxgtk3.2-dev libgl1-mesa-dev libglu1-mesa-dev libpng-dev \
  libssh-dev unixodbc-dev xsltproc fop libxml2-utils \
  unzip curl ca-certificates git

# --- 3. Pin tool versions up-front ------------------------------------------
# `asdf install` (no args) reads $HOME/.tool-versions and installs each entry.
# Writing it now means we can install both tools with one command and the file
# is in the right place for the runtime smoke test.
cat > "$HOME/.tool-versions" <<EOF
erlang $OTP_VERSION
elixir $ELIXIR_VERSION
EOF

# --- 4. Plugins + installs ---------------------------------------------------
echo "==> Adding asdf erlang and elixir plugins"
asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git
asdf plugin add elixir https://github.com/asdf-vm/asdf-elixir.git

echo "==> Installing Erlang/OTP $OTP_VERSION (this is the slow step) and Elixir $ELIXIR_VERSION"
KERL_BUILD_DOCS=no KERL_INSTALL_MANPAGES=no KERL_INSTALL_HTMLDOCS=no \
  asdf install

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
