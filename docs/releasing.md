# Releasing Kingside

Pushing a version tag runs [`.github/workflows/release.yml`](../.github/workflows/release.yml):

- **macOS:** a DMG signed with Developer ID, notarized, and stapled, attached to a **draft** GitHub
  release. Anyone can install it once you publish the draft.
- **iOS, iPadOS, and tvOS:** builds signed for the App Store and uploaded to App Store Connect,
  where they appear in TestFlight.

The workflow needs signing files from your Apple Developer account as GitHub Actions secrets. This
guide creates them once; `Tools/release-secrets.sh` checks them and stores them.

## Contents

- [What you need](#what-you-need)
- [1. Register the App ID](#1-register-the-app-id)
- [2. Create the app in App Store Connect](#2-create-the-app-in-app-store-connect)
- [3. Export the signing certificates](#3-export-the-signing-certificates)
- [4. Create the provisioning profiles](#4-create-the-provisioning-profiles)
- [5. Create an App Store Connect API key](#5-create-an-app-store-connect-api-key)
- [6. Check the files and store the secrets](#6-check-the-files-and-store-the-secrets)
- [7. Release a version](#7-release-a-version)
- [Renew or replace signing files](#renew-or-replace-signing-files)
- [Troubleshooting](#troubleshooting)

## What you need

- A paid Apple Developer Program membership for team `9PQP6CDMQT`, the team in
  `AppStore/ExportOptions.plist`. Only the Account Holder can create a Developer ID certificate.
- Admin access to the GitHub repository, and `gh` signed in (`gh auth status`).
- A folder outside the repository for the files, for example `~/KingsideSigning`. Every file below
  goes there under the name shown. The `.p12` files and the `.p8` key are secret: never commit them.

## 1. Register the App ID

1. Open [Identifiers](https://developer.apple.com/account/resources/identifiers/list) in
   Certificates, Identifiers & Profiles.
1. If `io.github.xsyetopz.Kingside` is listed, open it. Otherwise choose **+**, then **App IDs**,
   then **App**, enter the description `Kingside` and the explicit bundle ID
   `io.github.xsyetopz.Kingside`.
1. Under **Capabilities**, turn on **Game Center**, then save.

The old `io.github.xsyetopz.OpenChess` App ID does not cover Kingside.

## 2. Create the app in App Store Connect

TestFlight uploads need an app record with the same bundle ID.

1. In [App Store Connect](https://appstoreconnect.apple.com/apps), choose **+**, then **New App**.
1. Select the **iOS** and **tvOS** platforms, the name `Kingside`, a primary language, the bundle ID
   `io.github.xsyetopz.Kingside`, and any SKU, such as `kingside`.
1. To let testers install builds, add them under **TestFlight** after the first upload.

## 3. Export the signing certificates

The workflow signs macOS with a **Developer ID Application** certificate and iOS and tvOS with an
**Apple Distribution** certificate. List the ones on this Mac:

```sh
security find-identity -v -p codesigning
```

If either is missing, create it in Xcode: **Settings**, **Accounts**, select the team, **Manage
Certificates**, **+**, then **Developer ID Application** or **Apple Distribution**.

Export each one with its private key:

1. Open Keychain Access and select **My Certificates** in the login keychain.
1. Right-click **Developer ID Application: …** (the row that expands to show a private key) and
   choose **Export**.
1. Save it as `DeveloperID.p12` in your folder and set a password.
1. Repeat for **Apple Distribution: …** and save it as `AppleDistribution.p12`.

## 4. Create the provisioning profiles

Create three profiles in
[Profiles](https://developer.apple.com/account/resources/profiles/list). For each, choose **+**,
pick the type, select the `io.github.xsyetopz.Kingside` App ID and the certificate you exported in
step 3, name the profile, generate it, and download it.

| Type (under Distribution) | Platform | Name | Save as |
| --- | --- | --- | --- |
| Developer ID | macOS | `Kingside macOS Developer ID` | `Kingside_macOS_DeveloperID.provisionprofile` |
| App Store Connect | iOS | `Kingside iOS App Store` | `Kingside_iOS_AppStore.mobileprovision` |
| App Store Connect | tvOS | `Kingside tvOS App Store` | `Kingside_tvOS_AppStore.mobileprovision` |

A profile records the App ID's capabilities and the certificate at the time you generate it. After
you change either one, regenerate the profiles and store the secrets again.

## 5. Create an App Store Connect API key

The workflow uses one key to notarize the macOS app and to upload the iOS and tvOS builds.

1. In App Store Connect, open **Users and Access**, then **Integrations**, then **App Store Connect
   API**, then **Team Keys**.
1. Choose **+**, name the key `Kingside CI`, and give it the **App Manager** role.
1. Download the key. Apple names it `AuthKey_<KEY ID>.p8` and lets you download it only once. Put
   it in your folder without renaming it.
1. Note the **Issuer ID** shown above the list of keys.

## 6. Check the files and store the secrets

From the repository root, check everything first. The script asks for the two `.p12` passwords and
the Issuer ID, and asks App Store Connect whether it accepts the key:

```sh
Tools/release-secrets.sh check ~/KingsideSigning
```

Each `FAIL` line names the file and the problem. Fix it with the step above that made the file,
then run the check again. When it prints `All checks passed.`, store the secrets:

```sh
Tools/release-secrets.sh upload ~/KingsideSigning
```

`upload` runs the same checks, then sets these repository secrets with `gh secret set`. Set
`GH_REPO=xsyetopz/Kingside` if `gh` picks another repository.

| Secret | Contents |
| --- | --- |
| `DEVELOPER_ID_APPLICATION_CERT_BASE64` | `DeveloperID.p12`, base64 |
| `DEVELOPER_ID_APPLICATION_CERT_SECRET` | Its password |
| `APPLE_DISTRIBUTION_CERT_BASE64` | `AppleDistribution.p12`, base64 |
| `APPLE_DISTRIBUTION_CERT_SECRET` | Its password |
| `KINGSIDE_MACOS_PROFILE_BASE64` | The macOS Developer ID profile, base64 |
| `KINGSIDE_IOS_PROFILE_BASE64` | The iOS App Store profile, base64 |
| `KINGSIDE_TVOS_PROFILE_BASE64` | The tvOS App Store profile, base64 |
| `APP_STORE_CONNECT_KEY_BASE64` | The `.p8` key, base64 |
| `APP_STORE_CONNECT_KEY_ID` | The key ID from the file name |
| `APP_STORE_CONNECT_ISSUER_ID` | The Issuer ID |
| `KEYCHAIN_SECRET` | A random password for the temporary keychain in CI |

Afterwards, move the folder to a safe place, such as an encrypted disk image, or delete it.

## 7. Release a version

Tag the commit and push the tag:

```sh
git tag 1.0.0
git push origin 1.0.0
```

Or run the **Release** workflow from the Actions tab and enter the version; it builds the commit you
run it on, and publishing the draft creates the tag.

- Tags are `MAJOR.MINOR.PATCH` with an optional `-alpha.N`, `-beta.N`, or `-rc.N`. A suffix marks
  the GitHub release as a prerelease.
- The app's version is the tag without the suffix, because the App Store accepts only numbers. Its
  build number is the workflow run number, which grows with each run.
- When the run finishes, open **Releases** on GitHub, review the draft and its DMG, and publish it.
  The iOS and tvOS builds appear in TestFlight after Apple finishes processing them.

## Renew or replace signing files

Certificates and profiles expire; Certificates, Identifiers & Profiles shows each date. To renew,
create the replacement certificate (step 3), regenerate the profiles with it (step 4), and run
`Tools/release-secrets.sh upload` again. If a `.p12` or the `.p8` key leaks, revoke it in the
developer account or App Store Connect first.

## Troubleshooting

- **`Missing secret: …` in the workflow:** run step 6.
- **`No profile for team … matching …` when archiving:** the profile does not include the
  certificate in the keychain. Regenerate it with that certificate (step 4).
- **Notarization prints `Invalid`:** the log after it lists each file Apple rejected and why.
- **App Store Connect rejects an upload because the version or build exists:** tag a higher
  version, or rerun the workflow to get a new build number.
