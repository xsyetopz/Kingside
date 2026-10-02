#!/bin/sh
# Archives a signed release build for one platform. On macOS it writes a notarized, stapled DMG
# signed with Developer ID; on iOS and tvOS it uploads the build to App Store Connect for TestFlight.
# Tools/release-keychain.sh installs the certificate and profile first.
#
# Usage: Tools/release.sh PLATFORM TAG BUILD OUTDIR   (PLATFORM: macOS, iOS, or tvOS)
#   TAG: MAJOR.MINOR.PATCH with an optional -alpha.N, -beta.N, or -rc.N; the app's version drops
#   the suffix. BUILD: the build number, which must grow with each upload.
# Environment: PROFILE_UUID, APP_STORE_CONNECT_KEY_PATH (.p8), APP_STORE_CONNECT_KEY_ID,
# APP_STORE_CONNECT_ISSUER_ID.
# Writes OUTDIR/Kingside-TAG-macOS.dmg on macOS. Exit status: 0 done, 1 failure, 2 usage error.

set -eu

usage() { echo "usage: $0 macOS|iOS|tvOS TAG BUILD OUTDIR" >&2; exit 2; }
[ $# -eq 4 ] || usage
platform=$1 tag=$2 build=$3
case $platform in
  macOS) identity='Developer ID Application' ;;
  iOS | tvOS) identity='Apple Distribution' ;;
  *) usage ;;
esac
echo "$tag" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(alpha|beta|rc)\.[1-9][0-9]*)?$' \
  || { echo "$tag: not MAJOR.MINOR.PATCH[-alpha|beta|rc.N]" >&2; exit 2; }
echo "$build" | grep -Eq '^[1-9][0-9]*$' || { echo "$build: not a positive integer" >&2; exit 2; }
: "${PROFILE_UUID:?}" "${APP_STORE_CONNECT_KEY_PATH:?}" "${APP_STORE_CONNECT_KEY_ID:?}"
: "${APP_STORE_CONNECT_ISSUER_ID:?}"

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$4"
out=$(CDPATH='' cd -- "$4" && pwd)
cd "$root"
bundle_id=io.github.xsyetopz.Kingside
team=$(plutil -extract teamID raw AppStore/ExportOptions.plist)
archive="$out/Kingside-$platform.xcarchive"

# The profile goes through RELEASE_PROVISIONING_PROFILE, which only the app target reads; setting
# PROVISIONING_PROFILE_SPECIFIER here would apply it to the package targets too.
rm -rf "$archive"
xcodebuild archive -project Kingside.xcodeproj -scheme Kingside \
  -destination "generic/platform=$platform" -archivePath "$archive" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team" \
  RELEASE_PROVISIONING_PROFILE="$PROFILE_UUID" \
  MARKETING_VERSION="${tag%%-*}" CURRENT_PROJECT_VERSION="$build"

options="$out/ExportOptions-$platform.plist"
if [ "$platform" = macOS ]; then
  cp Config/ExportOptions-DeveloperID.plist "$options"
else
  cp AppStore/ExportOptions.plist "$options"
  /usr/libexec/PlistBuddy -c 'Set :signingStyle manual' -c 'Set :destination upload' \
    -c "Add :signingCertificate string $identity" "$options"
fi
/usr/libexec/PlistBuddy -c 'Add :provisioningProfiles dict' \
  -c "Add :provisioningProfiles:$bundle_id string $PROFILE_UUID" "$options"

export_dir="$out/export-$platform"
rm -rf "$export_dir"
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export_dir" \
  -exportOptionsPlist "$options" -allowProvisioningUpdates \
  -authenticationKeyPath "$APP_STORE_CONNECT_KEY_PATH" -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID"

if [ "$platform" != macOS ]; then
  echo "Uploaded Kingside $tag ($build) for $platform to App Store Connect."
  exit 0
fi

# Submits a zip or DMG for notarization and waits; prints Apple's log when it is not accepted.
notarize() {
  xcrun notarytool submit "$1" --key "$APP_STORE_CONNECT_KEY_PATH" \
    --key-id "$APP_STORE_CONNECT_KEY_ID" --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
    --wait --output-format json >"$out/notary.json"
  status=$(jq -r .status "$out/notary.json")
  [ "$status" = Accepted ] && return 0
  echo "Notarization of $1: $status" >&2
  xcrun notarytool log "$(jq -r .id "$out/notary.json")" --key "$APP_STORE_CONNECT_KEY_PATH" \
    --key-id "$APP_STORE_CONNECT_KEY_ID" --issuer "$APP_STORE_CONNECT_ISSUER_ID" >&2
  exit 1
}

app="$export_dir/Kingside.app"
ditto -c -k --keepParent "$app" "$out/Kingside-notarize.zip"
notarize "$out/Kingside-notarize.zip"
xcrun stapler staple "$app"
spctl --assess --type execute --verbose=2 "$app"

dmg="$out/Kingside-$tag-macOS.dmg"
staging="$out/dmg-staging"
rm -rf "$staging" "$dmg"
mkdir -p "$staging"
ditto "$app" "$staging/Kingside.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname Kingside -srcfolder "$staging" -format UDZO "$dmg"
rm -rf "$staging"
codesign --sign "$identity" --timestamp "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
echo "Wrote $dmg"
