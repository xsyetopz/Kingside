#!/bin/sh
# Checks the release signing files that docs/releasing.md has you download, and stores them as
# GitHub Actions secrets for .github/workflows/release.yml.
#
# Usage: Tools/release-secrets.sh check|upload DIR   (run from the package root)
#   check   validates every file, the .p12 passwords, and the App Store Connect key.
#   upload  runs check, then sets the secrets with `gh secret set` (repository from gh or GH_REPO).
# DIR must hold:
#   DeveloperID.p12                               Developer ID Application certificate and key
#   AppleDistribution.p12                         Apple Distribution certificate and key
#   Kingside_macOS_DeveloperID.provisionprofile   Developer ID profile for the app
#   Kingside_iOS_AppStore.mobileprovision         iOS App Store profile for the app
#   Kingside_tvOS_AppStore.mobileprovision        tvOS App Store profile for the app
#   AuthKey_<KEY ID>.p8                           App Store Connect API key (exactly one)
# Environment: APP_STORE_CONNECT_ISSUER_ID (asked for when unset). The .p12 passwords are asked for.
# Exit status: 0 done, 1 a check or upload failed, 2 usage error.

set -eu

usage() { echo "usage: $0 check|upload DIR" >&2; exit 2; }
[ $# -eq 2 ] || usage
case $1 in check | upload) mode=$1 ;; *) usage ;; esac
[ -d "$2" ] || { echo "$2: not a directory" >&2; exit 2; }
dir=$(CDPATH='' cd -- "$2" && pwd)
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
bundle_id=io.github.xsyetopz.Kingside
team=$(plutil -extract teamID raw "$root/AppStore/ExportOptions.plist")
# Keychain exports use algorithms that OpenSSL 3 rejects without -legacy; the system LibreSSL reads them.
openssl=/usr/bin/openssl
work=$(mktemp -d)
trap 'stty echo 2>/dev/null || true; rm -rf "$work"' EXIT INT TERM
failures=0

fail() { echo "  FAIL: $*"; failures=$((failures + 1)); }

ask_secret() { # prompt -> stdout, without echo
  stty -echo </dev/tty
  printf '%s: ' "$1" >/dev/tty
  IFS= read -r answer </dev/tty
  stty echo </dev/tty
  printf '\n' >/dev/tty
  printf '%s' "$answer"
}

# Checks a .p12 opens with its password, holds a private key, and is the expected certificate type.
# Writes its SHA-1 fingerprint to $work/NAME.sha1.
check_p12() { # name file subject-prefix password
  echo "$2"
  [ -f "$dir/$2" ] || { fail "missing"; return; }
  if ! P12_PASS=$4 $openssl pkcs12 -in "$dir/$2" -nokeys -clcerts -passin env:P12_PASS \
    >"$work/$1.pem" 2>/dev/null; then
    fail "cannot open; wrong password or not a .p12"
    return
  fi
  P12_PASS=$4 $openssl pkcs12 -in "$dir/$2" -nocerts -nodes -passin env:P12_PASS 2>/dev/null \
    | grep -q 'PRIVATE KEY' || fail "has no private key; export the identity, not the certificate"
  subject=$($openssl x509 -in "$work/$1.pem" -noout -subject -nameopt multiline \
    | sed -n 's/^ *commonName *= //p')
  case $subject in "$3"*) echo "  $subject" ;; *) fail "is '$subject', expected '$3...'" ;; esac
  $openssl x509 -in "$work/$1.pem" -noout -checkend 0 >/dev/null || fail "certificate has expired"
  $openssl x509 -in "$work/$1.pem" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g' >"$work/$1.sha1"
}

# Checks a profile is for this app and team, of the right kind, with Game Center, unexpired, and
# lists the certificate in $work/CERT.sha1.
check_profile() { # file platform kind(developer-id|app-store) cert-name
  echo "$1"
  [ -f "$dir/$1" ] || { fail "missing"; return; }
  plist="$work/profile.plist"
  security cms -D -i "$dir/$1" >"$plist" 2>/dev/null || { fail "not a provisioning profile"; return; }
  get() { plutil -extract "$1" raw "$plist" 2>/dev/null || true; }
  echo "  $(get Name) ($(get UUID))"
  [ "$(get TeamIdentifier.0)" = "$team" ] || fail "team is $(get TeamIdentifier.0), expected $team"
  plutil -extract Platform json -o - "$plist" | grep -q "\"$2\"" \
    || fail "platform is $(plutil -extract Platform json -o - "$plist"), expected $2"
  app_id=$(get 'Entitlements.application-identifier')
  [ -n "$app_id" ] || app_id=$(get 'Entitlements.com\.apple\.application-identifier')
  [ "$app_id" = "$team.$bundle_id" ] || fail "App ID is $app_id, expected $team.$bundle_id"
  [ "$(get 'Entitlements.com\.apple\.developer\.game-center')" = true ] \
    || fail "has no Game Center entitlement; enable Game Center on the App ID and regenerate it"
  devices=$(get ProvisionedDevices)
  case $3 in
    developer-id)
      [ "$(get ProvisionsAllDevices)" = true ] || fail "is not a Developer ID profile" ;;
    app-store)
      { [ -z "$devices" ] && [ -z "$(get ProvisionsAllDevices)" ] \
        && [ "$(get 'Entitlements.get-task-allow')" != true ]; } \
        || fail "is not an App Store profile (it lists devices or allows debugging)" ;;
  esac
  expires=$(get ExpirationDate | tr -dc 0-9)
  [ "${expires:-0}" -gt "$(date -u +%Y%m%d%H%M%S)" ] || fail "expired on $(get ExpirationDate)"
  [ -f "$work/$4.sha1" ] || return 0
  count=$(get DeveloperCertificates)
  i=0 found=no
  while [ "$i" -lt "${count:-0}" ]; do
    sha1=$(get "DeveloperCertificates.$i" | base64 --decode \
      | $openssl x509 -inform DER -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')
    [ "$sha1" = "$(cat "$work/$4.sha1")" ] && found=yes
    i=$((i + 1))
  done
  [ "$found" = yes ] || fail "does not include the certificate in the .p12; regenerate it with that certificate"
}

devid_pass=$(ask_secret 'Password for DeveloperID.p12')
dist_pass=$(ask_secret 'Password for AppleDistribution.p12')
check_p12 devid DeveloperID.p12 'Developer ID Application:' "$devid_pass"
check_p12 dist AppleDistribution.p12 'Apple Distribution:' "$dist_pass"
check_profile Kingside_macOS_DeveloperID.provisionprofile OSX developer-id devid
check_profile Kingside_iOS_AppStore.mobileprovision iOS app-store dist
check_profile Kingside_tvOS_AppStore.mobileprovision tvOS app-store dist

set -- "$dir"/AuthKey_*.p8
key=$1
echo "App Store Connect API key"
if [ $# -ne 1 ] || [ ! -f "$key" ]; then
  fail "expected exactly one AuthKey_<KEY ID>.p8 in $dir"
else
  key_id=$(basename "$key" .p8)
  key_id=${key_id#AuthKey_}
  issuer=${APP_STORE_CONNECT_ISSUER_ID:-}
  [ -n "$issuer" ] || { printf 'Issuer ID: ' >/dev/tty; IFS= read -r issuer </dev/tty; }
  echo "  key $key_id, issuer $issuer"
  xcrun notarytool history --key "$key" --key-id "$key_id" --issuer "$issuer" >/dev/null 2>"$work/notary.err" \
    || fail "App Store Connect rejected the key: $(tail -1 "$work/notary.err")"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures checks failed; see docs/releasing.md."
  exit 1
fi
echo "All checks passed."
[ "$mode" = upload ] || exit 0

command -v gh >/dev/null || { echo "gh is not installed" >&2; exit 1; }
put() { printf '%s' "$2" | gh secret set "$1" && echo "  set $1"; }
echo "Setting secrets in $(gh repo view --json nameWithOwner -q .nameWithOwner)"
put DEVELOPER_ID_APPLICATION_CERT_BASE64 "$(base64 -i "$dir/DeveloperID.p12")"
put DEVELOPER_ID_APPLICATION_CERT_SECRET "$devid_pass"
put APPLE_DISTRIBUTION_CERT_BASE64 "$(base64 -i "$dir/AppleDistribution.p12")"
put APPLE_DISTRIBUTION_CERT_SECRET "$dist_pass"
put KINGSIDE_MACOS_PROFILE_BASE64 "$(base64 -i "$dir/Kingside_macOS_DeveloperID.provisionprofile")"
put KINGSIDE_IOS_PROFILE_BASE64 "$(base64 -i "$dir/Kingside_iOS_AppStore.mobileprovision")"
put KINGSIDE_TVOS_PROFILE_BASE64 "$(base64 -i "$dir/Kingside_tvOS_AppStore.mobileprovision")"
put APP_STORE_CONNECT_KEY_BASE64 "$(base64 -i "$key")"
put APP_STORE_CONNECT_KEY_ID "$key_id"
put APP_STORE_CONNECT_ISSUER_ID "$issuer"
put KEYCHAIN_SECRET "$($openssl rand -hex 24)"
echo "Done. Delete $dir or move it somewhere safe; the .p12 files and the .p8 key are secret."
