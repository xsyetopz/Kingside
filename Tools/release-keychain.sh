#!/bin/sh
# Imports one signing certificate and one provisioning profile from GitHub Actions secrets into a
# temporary keychain, for Tools/release.sh. CI only: it changes the user's keychain search list.
#
# Usage: Tools/release-keychain.sh          (prints the profile's UUID on stdout)
#        Tools/release-keychain.sh --delete (removes the temporary keychain)
# Environment: RUNNER_TEMP, KEYCHAIN_SECRET, CERT_BASE64 (.p12), CERT_SECRET (.p12 password),
# PROFILE_BASE64 (.provisionprofile or .mobileprovision).
# Exit status: 0 done, 1 failure.

set -eu

: "${RUNNER_TEMP:?}"
keychain="$RUNNER_TEMP/kingside-release.keychain-db"

if [ "${1:-}" = --delete ]; then
  [ ! -f "$keychain" ] || security delete-keychain "$keychain"
  exit 0
fi

for name in KEYCHAIN_SECRET CERT_BASE64 CERT_SECRET PROFILE_BASE64; do
  eval "value=\${$name:-}"
  # shellcheck disable=SC2154 # set by eval
  [ -n "$value" ] || { echo "Missing secret: $name (see docs/releasing.md)" >&2; exit 1; }
done

payload=$(mktemp -d "$RUNNER_TEMP/kingside-signing.XXXXXX")
trap 'rm -rf "$payload"' EXIT

security create-keychain -p "$KEYCHAIN_SECRET" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$KEYCHAIN_SECRET" "$keychain"
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"

printf '%s' "$CERT_BASE64" | base64 --decode >"$payload/cert.p12"
security import "$payload/cert.p12" -f pkcs12 -k "$keychain" -P "$CERT_SECRET" \
  -T /usr/bin/codesign -T /usr/bin/security >&2
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_SECRET" \
  "$keychain" >/dev/null

printf '%s' "$PROFILE_BASE64" | base64 --decode >"$payload/profile"
security cms -D -i "$payload/profile" >"$payload/profile.plist"
uuid=$(plutil -extract UUID raw "$payload/profile.plist")
# Xcode 16 and later read profiles from here.
profiles="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$profiles"
case $(plutil -extract Platform.0 raw "$payload/profile.plist") in
  OSX) cp "$payload/profile" "$profiles/$uuid.provisionprofile" ;;
  *) cp "$payload/profile" "$profiles/$uuid.mobileprovision" ;;
esac

echo "Imported $(plutil -extract Name raw "$payload/profile.plist") ($uuid)" >&2
security find-identity -v -p codesigning "$keychain" | sed -n 's/^ *[0-9]*) [0-9A-F]* //p' >&2
echo "$uuid"
