#!/usr/bin/env bash
# Generate appcast.xml from the two bibishi DMGs (arm64 + x86_64) sitting in
# dist/. The script is run by publish_release.sh after package_dmg.sh for
# both architectures, and produces dist/appcast.xml that Sparkle ships with.
#
# Sparkle reads the appcast from SUFeedURL, picks the <enclosure> whose
# sparkle:arch matches the running machine, verifies sparkle:edSignature with
# the SUPublicEDKey baked into Info.plist, then downloads and installs.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_BIN_DIR="$ROOT_DIR/script/.sparkle-bin"
PRIVATE_KEY_FILE="$ROOT_DIR/script/sparkle_private_key"
APP_BUNDLE="$ROOT_DIR/dist/arm64/MacBookPet.app"
DIST_DIR="$ROOT_DIR/dist"
APPCAST_OUTPUT="$DIST_DIR/appcast.xml"

GITHUB_REPO="${GITHUB_REPO:-guwan050-sys/bibishi}"

if [[ ! -x "$SPARKLE_BIN_DIR/sign_update" ]]; then
  echo "error: $SPARKLE_BIN_DIR/sign_update not found." >&2
  echo "       Run script/setup_sparkle.sh first." >&2
  exit 1
fi
if [[ ! -s "$PRIVATE_KEY_FILE" ]]; then
  echo "error: $PRIVATE_KEY_FILE not found." >&2
  echo "       Run script/setup_sparkle.sh to generate / export the key." >&2
  exit 1
fi
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "error: $APP_BUNDLE does not exist. Build first." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
if [[ -z "$VERSION" ]]; then
  echo "error: could not read CFBundleShortVersionString from Info.plist." >&2
  exit 1
fi

ARM64_DMG="$DIST_DIR/arm64/bibishi-$VERSION-arm64.dmg"
X86_DMG="$DIST_DIR/x86_64/bibishi-$VERSION-x86_64.dmg"

if [[ ! -f "$ARM64_DMG" ]]; then
  echo "error: $ARM64_DMG missing. Build it with:" >&2
  echo "       ./script/package_dmg.sh --arch arm64" >&2
  exit 1
fi
if [[ ! -f "$X86_DMG" ]]; then
  echo "error: $X86_DMG missing. Build it with:" >&2
  echo "       ./script/package_dmg.sh --arch x86_64" >&2
  exit 1
fi

echo "==> Signing arm64 DMG"
# sign_update prints sparkle:edSignature="..." length="..." when called on
# an update archive; we parse out the edSignature value.
ARM64_RAW="$("$SPARKLE_BIN_DIR/sign_update" --ed-key-file "$PRIVATE_KEY_FILE" "$ARM64_DMG")"
ARM64_SIG="$(echo "$ARM64_RAW" \
  | /usr/bin/sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
ARM64_LEN="$(stat -f%z "$ARM64_DMG")"

echo "==> Signing x86_64 DMG"
X86_RAW="$("$SPARKLE_BIN_DIR/sign_update" --ed-key-file "$PRIVATE_KEY_FILE" "$X86_DMG")"
X86_SIG="$(echo "$X86_RAW" \
  | /usr/bin/sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
X86_LEN="$(stat -f%z "$X86_DMG")"

if [[ -z "$ARM64_SIG" || -z "$X86_SIG" ]]; then
  echo "error: failed to parse edSignature from sign_update output." >&2
  echo "       arm64 output: $ARM64_RAW" >&2
  echo "       x86_64 output: $X86_RAW" >&2
  exit 1
fi

PUB_DATE="$(LC_ALL=C /bin/date -u +'%a, %d %b %Y %H:%M:%S +0000')"
TAG="v$VERSION"

mkdir -p "$DIST_DIR"
cat >"$APPCAST_OUTPUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>bibishi</title>
    <item>
      <title>bibishi $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure url="https://github.com/$GITHUB_REPO/releases/download/$TAG/bibishi-$VERSION-arm64.dmg"
                 sparkle:version="$VERSION"
                 sparkle:shortVersionString="$VERSION"
                 sparkle:os="macos"
                 sparkle:arch="arm64"
                 sparkle:edSignature="$ARM64_SIG"
                 length="$ARM64_LEN"
                 type="application/x-apple-diskimage" />
      <enclosure url="https://github.com/$GITHUB_REPO/releases/download/$TAG/bibishi-$VERSION-x86_64.dmg"
                 sparkle:version="$VERSION"
                 sparkle:shortVersionString="$VERSION"
                 sparkle:os="macos"
                 sparkle:arch="x86_64"
                 sparkle:edSignature="$X86_SIG"
                 length="$X86_LEN"
                 type="application/x-apple-diskimage" />
    </item>
  </channel>
</rss>
XML

echo "==> Wrote $APPCAST_OUTPUT"
echo "    version: $VERSION"
echo "    arm64: $ARM64_DMG ($ARM64_LEN bytes, sig ${ARM64_SIG:0:12}...)"
echo "    x86_64: $X86_DMG ($X86_LEN bytes, sig ${X86_SIG:0:12}...)"
