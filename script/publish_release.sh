#!/usr/bin/env bash
# Build, sign, and publish a bibishi release end-to-end.
#
# Steps:
#   1. Build the .app for both arm64 and x86_64
#   2. Package DMGs for both architectures
#   3. Generate dist/appcast.xml with edDSA signatures
#   4. Create a GitHub Release with the two DMGs attached
#   5. Push dist/appcast.xml to the gh-pages branch (served at
#      https://$GITHUB_REPO/<repo>/appcast.xml — what Sparkle polls)
#
# Required environment:
#   - gh CLI logged in (gh auth status)
#   - script/sparkle_private_key present (script/setup_sparkle.sh)
#   - Working tree clean (so we can commit/push the appcast)
#
# Optional env overrides:
#   GITHUB_REPO   default: guwan050-sys/bibishi
#   DRY_RUN       if set to 1, skip the gh release create / push steps
#   SKIP_BUILD    if set to 1, reuse the DMGs already in dist/

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITHUB_REPO="${GITHUB_REPO:-guwan050-sys/bibishi}"
DRY_RUN="${DRY_RUN:-0}"

cd "$ROOT_DIR"

# --- Preflight -----------------------------------------------------------

if [[ ! -s "$ROOT_DIR/script/sparkle_private_key" ]]; then
  echo "error: script/sparkle_private_key is missing." >&2
  echo "       Run script/setup_sparkle.sh first." >&2
  exit 1
fi

if [[ "$DRY_RUN" != "1" && -n "$(git status --porcelain)" ]]; then
  echo "error: working tree has uncommitted changes." >&2
  echo "       Commit or stash them before publishing." >&2
  git status --short >&2
  exit 1
fi

if [[ "$DRY_RUN" != "1" ]] && ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI not installed. Install with: brew install gh" >&2
  exit 1
fi
if [[ "$DRY_RUN" != "1" ]] && ! gh auth status >/dev/null 2>&1; then
  echo "error: gh CLI not logged in. Run: gh auth login" >&2
  exit 1
fi

# --- Build + package -----------------------------------------------------

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "==> Building arm64"
  ARCH=arm64 "$ROOT_DIR/script/build_and_run.sh" --release-app --arch arm64 >/dev/null
  "$ROOT_DIR/script/package_dmg.sh" --arch arm64 >/dev/null

  echo "==> Building x86_64"
  ARCH=x86_64 "$ROOT_DIR/script/build_and_run.sh" --release-app --arch x86_64 >/dev/null
  "$ROOT_DIR/script/package_dmg.sh" --arch x86_64 >/dev/null
else
  echo "==> SKIP_BUILD set; reusing existing DMGs"
fi

# Read version from the freshly built arm64 bundle.
VERSION="$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' \
  "$ROOT_DIR/dist/arm64/MacBookPet.app/Contents/Info.plist")"
TAG="v$VERSION"

echo "==> Version: $VERSION (tag $TAG)"

ARM64_DMG="$ROOT_DIR/dist/arm64/bibishi-$VERSION-arm64.dmg"
X86_DMG="$ROOT_DIR/dist/x86_64/bibishi-$VERSION-x86_64.dmg"

if [[ ! -f "$ARM64_DMG" || ! -f "$X86_DMG" ]]; then
  echo "error: missing DMG(s) after build:" >&2
  [[ -f "$ARM64_DMG" ]] || echo "       - $ARM64_DMG" >&2
  [[ -f "$X86_DMG" ]] || echo "       - $X86_DMG" >&2
  exit 1
fi

# --- Appcast generation --------------------------------------------------

GITHUB_REPO="$GITHUB_REPO" "$ROOT_DIR/script/generate_appcast.sh"

# --- GitHub Release ------------------------------------------------------

if [[ "$DRY_RUN" == "1" ]]; then
  echo "==> DRY_RUN: skipping gh release create and git push"
  exit 0
fi

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "==> Release $TAG already exists; uploading DMG assets to it"
  gh release upload "$TAG" "$ARM64_DMG" "$X86_DMG" --clobber
else
  echo "==> Creating GitHub release $TAG"
  gh release create "$TAG" \
    "$ARM64_DMG" \
    "$X86_DMG" \
    --title "bibishi $VERSION" \
    --generate-notes
fi

# --- Push appcast.xml to gh-pages ---------------------------------------

echo "==> Publishing appcast.xml to gh-pages branch"
WORKTREE_DIR="$(mktemp -d)"
trap 'rm -rf "$WORKTREE_DIR"' EXIT

if ! git show-ref --verify --quiet "refs/remotes/origin/gh-pages"; then
  # First time: create an orphan gh-pages branch with just appcast.xml.
  echo "    (first publish — creating gh-pages branch)"
  git worktree add --detach "$WORKTREE_DIR"
  git -C "$WORKTREE_DIR" checkout --orphan gh-pages
  git -C "$WORKTREE_DIR" reset --hard
  cp "$ROOT_DIR/dist/appcast.xml" "$WORKTREE_DIR/appcast.xml"
  git -C "$WORKTREE_DIR" add appcast.xml
  git -C "$WORKTREE_DIR" -c user.name="bibishi Publisher" \
    -c user.email="publisher@localhost" \
    commit -m "Publish appcast.xml for $TAG"
  git -C "$WORKTREE_DIR" push origin HEAD:gh-pages
  git -C "$WORKTREE_DIR" checkout --
  git worktree remove "$WORKTREE_DIR" --force
else
  git worktree add "$WORKTREE_DIR" origin/gh-pages
  cp "$ROOT_DIR/dist/appcast.xml" "$WORKTREE_DIR/appcast.xml"
  git -C "$WORKTREE_DIR" add appcast.xml
  if ! git -C "$WORKTREE_DIR" diff --cached --quiet; then
    git -C "$WORKTREE_DIR" -c user.name="bibishi Publisher" \
      -c user.email="publisher@localhost" \
      commit -m "Publish appcast.xml for $TAG"
    git -C "$WORKTREE_DIR" push origin gh-pages
  else
    echo "    (appcast unchanged, skipping push)"
  fi
  git worktree remove "$WORKTREE_DIR" --force
fi

echo ""
echo "Done. Release $TAG is live with auto-update enabled."
echo "Verify Sparkle by installing v1.0.0 from the previous release and"
echo "launching it — you should see an update prompt for $VERSION."
