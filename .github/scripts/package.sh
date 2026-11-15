#!/usr/bin/env bash
# Build the addon zip for a release tag and print what the release is.
#
#   .github/scripts/package.sh v0.1.0-beta.1
#
# Checks that the tag follows the CurseForge-style naming (vX.Y.Z, vX.Y.Z-alpha.N,
# vX.Y.Z-beta.N) and that both .toc files carry the same version, then writes
# dist/ForeverGearScale-<version>.zip with a ForeverGearScale/ folder inside.
# When GITHUB_OUTPUT is set (in Actions), it also exports version, release_type
# and zip for the next steps.
set -euo pipefail

ADDON=ForeverGearScale
TAG="${1:?usage: package.sh <tag>}"

if [[ ! "$TAG" =~ ^v([0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta)\.[0-9]+)?)$ ]]; then
  echo "::error::Tag '$TAG' must look like v1.2.3, v1.2.3-beta.1 or v1.2.3-alpha.1" >&2
  exit 1
fi
VERSION="${BASH_REMATCH[1]}"

case "$VERSION" in
  *-alpha.*) RELEASE_TYPE=alpha ;;
  *-beta.*)  RELEASE_TYPE=beta ;;
  *)         RELEASE_TYPE=release ;;
esac

for toc in "$ADDON".toc "$ADDON"_*.toc; do
  [[ -f "$toc" ]] || continue
  toc_version="$(sed -n 's/^## Version:[[:space:]]*//p' "$toc" | tr -d '\r')"
  if [[ "$toc_version" != "$VERSION" ]]; then
    echo "::error file=$toc::'## Version: $toc_version' does not match tag $TAG (expected $VERSION)" >&2
    exit 1
  fi
done

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$ADDON" dist

# Ship only what the game loads, plus the license and readme.
cp "$ADDON"*.toc ./*.lua LICENSE README.md "$STAGE/$ADDON/"
cp -r Data "$STAGE/$ADDON/"

ZIP="dist/$ADDON-$VERSION.zip"
rm -f "$ZIP"
(cd "$STAGE" && zip -qr -X "$OLDPWD/$ZIP" "$ADDON")

echo "version=$VERSION"
echo "release_type=$RELEASE_TYPE"
echo "zip=$ZIP"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "version=$VERSION"
    echo "release_type=$RELEASE_TYPE"
    echo "zip=$ZIP"
  } >> "$GITHUB_OUTPUT"
fi
