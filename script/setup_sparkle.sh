#!/usr/bin/env bash
# One-time setup for Sparkle auto-update.
#
# Downloads the Sparkle CLI tools (generate_keys / sign_update / generate_appcast),
# generates an edDSA key pair, and stores both keys locally so the appcast
# generation and signing can run from a non-interactive script.
#
# Sparkle's default flow stores the private key only in the macOS Keychain.
# That works for a developer who sits at the Mac, but breaks the build pipeline
# the moment the Keychain is reset. This script immediately exports the private
# key to script/sparkle_private_key (gitignored) so it survives.
#
# Safe to re-run: if the key already exists in the Keychain, it is reused and
# just re-exported to the file.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_BIN_DIR="$ROOT_DIR/script/.sparkle-bin"
PRIVATE_KEY_FILE="$ROOT_DIR/script/sparkle_private_key"
PUBLIC_KEY_FILE="$ROOT_DIR/script/sparkle_public_key.txt"

# Read the resolved Sparkle version from Package.resolved so the downloaded
# CLI tools always match the framework version SwiftPM pulled in.
# Package.resolved is JSON, so we grep for the first "version" : "X.Y.Z"
# entry (skipping the file-format "version" : 2 at the bottom).
if [[ ! -s "$ROOT_DIR/Package.resolved" ]]; then
  echo "error: Package.resolved missing. Run \`swift package resolve\` first." >&2
  exit 1
fi
RESOLVED_VERSION="$(grep -E '"version"[[:space:]]*:[[:space:]]*"[0-9]' \
  "$ROOT_DIR/Package.resolved" \
  | /usr/bin/head -1 \
  | /usr/bin/sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
if [[ -z "$RESOLVED_VERSION" ]]; then
  echo "error: could not find Sparkle version in Package.resolved." >&2
  echo "       Run \`swift package resolve\` to regenerate it." >&2
  exit 1
fi

SPARKLE_VERSION="$RESOLVED_VERSION"
TARBALL_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"

echo "==> Sparkle version: $SPARKLE_VERSION"

mkdir -p "$SPARKLE_BIN_DIR"

# Download + extract only if generate_keys isn't already present.
if [[ ! -x "$SPARKLE_BIN_DIR/generate_keys" ]]; then
  echo "==> Downloading Sparkle-$SPARKLE_VERSION.tar.xz"
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  if ! curl --fail --location --silent --show-error \
      -o "$TMP_DIR/sparkle.tar.xz" "$TARBALL_URL"; then
    echo "error: failed to download $TARBALL_URL" >&2
    echo "       Check your network connection or that Sparkle $SPARKLE_VERSION exists on GitHub." >&2
    exit 1
  fi
  tar -xJf "$TMP_DIR/sparkle.tar.xz" -C "$TMP_DIR" --strip-components=1
  cp -R "$TMP_DIR/bin/." "$SPARKLE_BIN_DIR/"
  chmod +x "$SPARKLE_BIN_DIR/"*
fi

echo "==> Generating / reusing Sparkle edDSA key pair"
echo "    (Keychain may prompt for permission — click 'Always Allow')"

# generate_keys creates a key in the macOS Keychain if one does not already
# exist, then prints an Info.plist snippet containing the public key. We
# extract the base64 value from the <string>...</string> line.
GENERATE_OUTPUT="$("$SPARKLE_BIN_DIR/generate_keys" 2>&1)"
echo "$GENERATE_OUTPUT" || true

PUBLIC_KEY="$(echo "$GENERATE_OUTPUT" \
  | /usr/bin/grep -oE '<string>[A-Za-z0-9+/=]+</string>' \
  | /usr/bin/head -1 \
  | /usr/bin/sed -E 's|<string>(.+)</string>|\1|')"

if [[ -z "$PUBLIC_KEY" ]]; then
  echo "error: could not extract public key from generate_keys output." >&2
  echo "       Run \`$SPARKLE_BIN_DIR/generate_keys\` manually and re-run this script." >&2
  exit 1
fi

printf '%s\n' "$PUBLIC_KEY" >"$PUBLIC_KEY_FILE"
echo "==> Wrote public key to $PUBLIC_KEY_FILE"

# Export the private key from the Keychain to a file so future builds don't
# depend on the Keychain being intact.
if [[ ! -s "$PRIVATE_KEY_FILE" ]]; then
  "$SPARKLE_BIN_DIR/generate_keys" -x "$PRIVATE_KEY_FILE"
  chmod 600 "$PRIVATE_KEY_FILE"
  echo "==> Wrote private key to $PRIVATE_KEY_FILE (mode 600, gitignored)"
else
  echo "==> Private key already present at $PRIVATE_KEY_FILE (skipping export)"
fi

echo ""
echo "Done. Next steps:"
echo "  1. Commit script/sparkle_public_key.txt if you want it tracked (safe)."
echo "  2. Back up script/sparkle_private_key somewhere secure — losing it"
echo "     means no more signed updates ever."
echo "  3. Build the app: ./script/build_and_run.sh --release-app"
echo "  4. Publish a release: ./script/publish_release.sh"
