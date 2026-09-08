#!/usr/bin/env bash
set -euo pipefail

MODE="run"
if [[ $# -gt 0 && "$1" != "--arch" ]]; then
  MODE="$1"
  shift
fi

ARCHITECTURE="${ARCHITECTURE:-$(uname -m)}"
if [[ $# -gt 0 ]]; then
  if [[ "$1" != "--arch" || $# -ne 2 ]]; then
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--release-app] [--arch arm64|x86_64]" >&2
    exit 2
  fi
  ARCHITECTURE="$2"
fi

case "$ARCHITECTURE" in
  arm64|x86_64)
    ;;
  *)
    echo "unsupported architecture: $ARCHITECTURE (expected arm64 or x86_64)" >&2
    exit 2
    ;;
esac
APP_NAME="MacBookPet"
DISPLAY_NAME="bibishi"
BUNDLE_ID="com.susunext.MacBookPet"
APP_VERSION="1.0.1"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Sparkle auto-update feed. Override with SPARKLE_FEED_URL=<url> when building
# a fork that points at a different appcast. The public key is read from
# script/sparkle_public_key.txt — produced by script/setup_sparkle.sh.
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://guwan050-sys.github.io/bibishi/appcast.xml}"
SPARKLE_PUBLIC_KEY_FILE="$ROOT_DIR/script/sparkle_public_key.txt"
DIST_DIR="$ROOT_DIR/dist/$ARCHITECTURE"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON="$ROOT_DIR/Assets/MacBookPet.icns"
STATUS_ICON="$ROOT_DIR/Assets/CubePetStatusIcon.png"
NETEASE_MUSIC_PERMISSION_ICON="$ROOT_DIR/Assets/NetEaseMusicPermissionIcon.png"
QQ_MUSIC_PERMISSION_ICON="$ROOT_DIR/Assets/QQMusicPermissionIcon.png"
KUGOU_MUSIC_PERMISSION_ICON="$ROOT_DIR/Assets/KuGouMusicPermissionIcon.png"
CUBE_SKIN_ICE2_IMAGE="$ROOT_DIR/Assets/CubeSkinIce2.png"
CUBE_SKIN_RAINBOW2_IMAGE="$ROOT_DIR/Assets/CubeSkinRainbow2.png"
PET_COLA_IMAGE="$ROOT_DIR/Assets/PetCola.png"
FISH_SHAPED_PASTRY_IMAGE="$ROOT_DIR/Assets/FishShapedPastry.png"
PUDDING_CUP_IMAGE="$ROOT_DIR/Assets/PuddingCup.png"
THREE_COLOR_DANGO_IMAGE="$ROOT_DIR/Assets/ThreeColorDango.png"
PET_MENU_BACKGROUND_IMAGE="$ROOT_DIR/Assets/PetMenuBackground.jpg"
PET_MENU_HAND_DRAWN_BUTTON_IMAGE="$ROOT_DIR/Assets/PetMenuHandDrawnButton.png"
PET_MENU_HAND_DRAWN_CARD_IMAGE="$ROOT_DIR/Assets/PetMenuHandDrawnCard.png"
MY_PETS_COLLECTION_CARD_IMAGE="$ROOT_DIR/Assets/MyPetsCollectionCard.png"
PET_NECK_SCARF_IMAGE="$ROOT_DIR/Assets/PetNeckScarf.png"
PET_NECK_SCARF_MUSHROOM_IMAGE="$ROOT_DIR/Assets/PetNeckScarfMushroom.png"
PET_NECK_SCARF_FLOWER_PLAID_IMAGE="$ROOT_DIR/Assets/PetNeckScarfFlowerPlaid.png"
PET_NECK_SCARF_BLUE_STRIPE_IMAGE="$ROOT_DIR/Assets/PetNeckScarfBlueStripe.png"
PET_NECK_SCARF_CREAM_FLOWER_IMAGE="$ROOT_DIR/Assets/PetNeckScarfCreamFlower.png"
PET_NECK_SCARF_STAR_TASSEL_IMAGE="$ROOT_DIR/Assets/PetNeckScarfStarTassel.png"
PET_NECK_SCARF_RED_STRIPE_IMAGE="$ROOT_DIR/Assets/PetNeckScarfRedStripe.png"
PET_NECK_SCARF_RUST_KNIT_IMAGE="$ROOT_DIR/Assets/PetNeckScarfRustKnit.png"
PET_NECK_SCARF_COLORFUL_POLKA_DOT_IMAGE="$ROOT_DIR/Assets/PetNeckScarfColorfulPolkaDot.png"
PET_NECK_SCARF_KOI_WAVE_IMAGE="$ROOT_DIR/Assets/PetNeckScarfKoiWave.png"
PET_NECK_SCARF_ROCK_LIGHTNING_IMAGE="$ROOT_DIR/Assets/PetNeckScarfRockLightning.png"
PET_NECK_SCARF_LEMON_LACE_IMAGE="$ROOT_DIR/Assets/PetNeckScarfLemonLace.png"
PET_NECK_SCARF_GALAXY_IMAGE="$ROOT_DIR/Assets/PetNeckScarfGalaxy.png"
PET_NECK_SCARF_RAINBOW_POM_POM_IMAGE="$ROOT_DIR/Assets/PetNeckScarfRainbowPomPom.png"
PET_NECK_SCARF_AUTUMN_PLAID_IMAGE="$ROOT_DIR/Assets/PetNeckScarfAutumnPlaid.png"
PET_NECK_SCARF_ACORN_ARGYLE_IMAGE="$ROOT_DIR/Assets/PetNeckScarfAcornArgyle.png"
PET_NECK_SCARF_STRAWBERRY_HEART_IMAGE="$ROOT_DIR/Assets/PetNeckScarfStrawberryHeart.png"
PET_HEAD_PAW_BASEBALL_CAP_IMAGE="$ROOT_DIR/Assets/PetHeadPawBaseballCap.png"
PET_HEAD_AVIATOR_CAP_IMAGE="$ROOT_DIR/Assets/PetHeadAviatorCap.png"
PET_HEAD_LEAF_NEWSBOY_CAP_IMAGE="$ROOT_DIR/Assets/PetHeadLeafNewsboyCap.png"

BUILD_CONFIGURATION="debug"
if [[ "$MODE" == "--release-app" || "$MODE" == "release-app" ]]; then
  BUILD_CONFIGURATION="release"
fi

# Keep local builds independent from an unlicensed full Xcode installation.
# Callers can still override this explicitly when they need another toolchain.
if [[ -z "${DEVELOPER_DIR:-}" && -d "/Library/Developer/CommandLineTools" ]]; then
  export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
fi

# The currently selected Command Line Tools can expose a newer default SDK
# whose Swift module version does not match its compiler. Prefer the installed
# 15.4 SDK for this macOS 14+ app when no SDK has been selected explicitly.
COMPATIBLE_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
if [[ -z "${SDKROOT:-}" && -d "$COMPATIBLE_SDK" ]]; then
  export SDKROOT="$COMPATIBLE_SDK"
fi

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/clang-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$ROOT_DIR/.build/swiftpm-module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"

if [[ "$MODE" != "--release-app" && "$MODE" != "release-app" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

swift build -c "$BUILD_CONFIGURATION" --arch "$ARCHITECTURE"
BUILD_BINARY="$(swift build -c "$BUILD_CONFIGURATION" --arch "$ARCHITECTURE" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

# Sparkle.framework ships as a SwiftPM binary artifact under
# .build/artifacts/sparkle/... (universal, both arm64 and x86_64).
# Copy it into Contents/Frameworks and add @loader_path/../Frameworks
# to the binary's rpath so the @rpath/Sparkle.framework linkage resolves.
SPARKLE_FRAMEWORK_SRC="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK_SRC" ]]; then
  mkdir -p "$APP_CONTENTS/Frameworks"
  rm -rf "$APP_CONTENTS/Frameworks/Sparkle.framework"
  cp -R "$SPARKLE_FRAMEWORK_SRC" "$APP_CONTENTS/Frameworks/Sparkle.framework"
  # Strip extended attributes (e.g. com.apple.FinderInfo) that arrive with the
  # downloaded Sparkle binary and would otherwise make `codesign --verify
  # --deep --strict` fail. Recursive across the whole framework.
  /usr/bin/xattr -cr "$APP_CONTENTS/Frameworks/Sparkle.framework"
  if ! /usr/bin/otool -l "$APP_BINARY" | /usr/bin/grep -q "@loader_path/../Frameworks"; then
    /usr/bin/install_name_tool -add_rpath "@loader_path/../Frameworks" "$APP_BINARY"
  fi
else
  echo "warning: Sparkle.framework not found at $SPARKLE_FRAMEWORK_SRC" >&2
  echo "         spark-package resolve may not have completed yet." >&2
fi

cp "$APP_ICON" "$APP_RESOURCES/MacBookPet.icns"
cp "$STATUS_ICON" "$APP_RESOURCES/CubePetStatusIcon.png"
cp "$NETEASE_MUSIC_PERMISSION_ICON" "$APP_RESOURCES/NetEaseMusicPermissionIcon.png"
cp "$QQ_MUSIC_PERMISSION_ICON" "$APP_RESOURCES/QQMusicPermissionIcon.png"
cp "$KUGOU_MUSIC_PERMISSION_ICON" "$APP_RESOURCES/KuGouMusicPermissionIcon.png"
cp "$CUBE_SKIN_ICE2_IMAGE" "$APP_RESOURCES/CubeSkinIce2.png"
cp "$CUBE_SKIN_RAINBOW2_IMAGE" "$APP_RESOURCES/CubeSkinRainbow2.png"
cp "$PET_COLA_IMAGE" "$APP_RESOURCES/PetCola.png"
cp "$FISH_SHAPED_PASTRY_IMAGE" "$APP_RESOURCES/FishShapedPastry.png"
cp "$PUDDING_CUP_IMAGE" "$APP_RESOURCES/PuddingCup.png"
cp "$THREE_COLOR_DANGO_IMAGE" "$APP_RESOURCES/ThreeColorDango.png"
cp "$PET_MENU_BACKGROUND_IMAGE" "$APP_RESOURCES/PetMenuBackground.jpg"
cp "$PET_MENU_HAND_DRAWN_BUTTON_IMAGE" "$APP_RESOURCES/PetMenuHandDrawnButton.png"
cp "$PET_MENU_HAND_DRAWN_CARD_IMAGE" "$APP_RESOURCES/PetMenuHandDrawnCard.png"
cp "$MY_PETS_COLLECTION_CARD_IMAGE" "$APP_RESOURCES/MyPetsCollectionCard.png"
cp "$PET_NECK_SCARF_IMAGE" "$APP_RESOURCES/PetNeckScarf.png"
cp "$PET_NECK_SCARF_MUSHROOM_IMAGE" "$APP_RESOURCES/PetNeckScarfMushroom.png"
cp "$PET_NECK_SCARF_FLOWER_PLAID_IMAGE" "$APP_RESOURCES/PetNeckScarfFlowerPlaid.png"
cp "$PET_NECK_SCARF_BLUE_STRIPE_IMAGE" "$APP_RESOURCES/PetNeckScarfBlueStripe.png"
cp "$PET_NECK_SCARF_CREAM_FLOWER_IMAGE" "$APP_RESOURCES/PetNeckScarfCreamFlower.png"
cp "$PET_NECK_SCARF_STAR_TASSEL_IMAGE" "$APP_RESOURCES/PetNeckScarfStarTassel.png"
cp "$PET_NECK_SCARF_RED_STRIPE_IMAGE" "$APP_RESOURCES/PetNeckScarfRedStripe.png"
cp "$PET_NECK_SCARF_RUST_KNIT_IMAGE" "$APP_RESOURCES/PetNeckScarfRustKnit.png"
cp "$PET_NECK_SCARF_COLORFUL_POLKA_DOT_IMAGE" "$APP_RESOURCES/PetNeckScarfColorfulPolkaDot.png"
cp "$PET_NECK_SCARF_KOI_WAVE_IMAGE" "$APP_RESOURCES/PetNeckScarfKoiWave.png"
cp "$PET_NECK_SCARF_ROCK_LIGHTNING_IMAGE" "$APP_RESOURCES/PetNeckScarfRockLightning.png"
cp "$PET_NECK_SCARF_LEMON_LACE_IMAGE" "$APP_RESOURCES/PetNeckScarfLemonLace.png"
cp "$PET_NECK_SCARF_GALAXY_IMAGE" "$APP_RESOURCES/PetNeckScarfGalaxy.png"
cp "$PET_NECK_SCARF_RAINBOW_POM_POM_IMAGE" "$APP_RESOURCES/PetNeckScarfRainbowPomPom.png"
cp "$PET_NECK_SCARF_AUTUMN_PLAID_IMAGE" "$APP_RESOURCES/PetNeckScarfAutumnPlaid.png"
cp "$PET_NECK_SCARF_ACORN_ARGYLE_IMAGE" "$APP_RESOURCES/PetNeckScarfAcornArgyle.png"
cp "$PET_NECK_SCARF_STRAWBERRY_HEART_IMAGE" "$APP_RESOURCES/PetNeckScarfStrawberryHeart.png"
cp "$PET_HEAD_PAW_BASEBALL_CAP_IMAGE" "$APP_RESOURCES/PetHeadPawBaseballCap.png"
cp "$PET_HEAD_AVIATOR_CAP_IMAGE" "$APP_RESOURCES/PetHeadAviatorCap.png"
cp "$PET_HEAD_LEAF_NEWSBOY_CAP_IMAGE" "$APP_RESOURCES/PetHeadLeafNewsboyCap.png"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>CFBundleIconFile</key>
  <string>MacBookPet.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSInputMonitoringUsageDescription</key>
  <string>MacBookPet uses input monitoring to release the desktop pet immediately when you stop dragging it.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>MacBookPet checks whether Music, NetEase Music, QQ Music, or KuGou Music is playing so the pet can react to your music.</string>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>com.susunext.macbookpet.food</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
      <key>UTTypeDescription</key>
      <string>CubePet Food</string>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key>
        <array>
          <string>mbpetfood</string>
        </array>
      </dict>
    </dict>
  </array>
  <key>LSUIElement</key>
  <true/>
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$(cat "$SPARKLE_PUBLIC_KEY_FILE" 2>/dev/null || true)</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ ! -s "$SPARKLE_PUBLIC_KEY_FILE" ]]; then
  echo "warning: script/sparkle_public_key.txt is missing or empty." >&2
  echo "         Run script/setup_sparkle.sh to generate the Sparkle key pair." >&2
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --release-app|release-app)
    echo "$APP_BUNDLE"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--release-app] [--arch arm64|x86_64]" >&2
    exit 2
    ;;
esac
