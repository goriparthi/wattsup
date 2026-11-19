# Releasing

A release is a notarized DMG on GitHub. Every installed copy is offered it by the updater, so
confirm before publishing.

## Once per machine

- A **Developer ID Application** certificate in the keychain (`security find-identity -v -p codesigning`).
- A notarytool keychain profile, e.g. `xcrun notarytool store-credentials redline ...`. The
  Apple developer agreement must be current, or notarization returns HTTP 403.

## Each release

1. Set `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Write `notes/releases/<version>.md` for people, not as a commit log.
3. `make ci`, commit, push. `gh release create` tags the remote's HEAD, so push first.
4. `NOTARY_PROFILE=redline make release`. It refuses a dirty tree, an unpushed HEAD, an existing tag,
   missing notes, failing tests, or a DMG that is not notarized.
5. `gh release list --limit 3` to confirm it is there.

`make dmg` alone builds `dist/Wattsup-<version>.dmg`: signed when a Developer ID is present, and
notarized when `NOTARY_PROFILE` is set. A DMG in `dist/` is not a release.

The site deploys separately from `site/` on every push to `main`.

## From GitHub Actions

Actions, **Release**, Run workflow, enter the version. It runs the same `scripts/release.sh` on a
clean macOS runner. It needs these repository secrets (Settings, Secrets and variables, Actions):

| Secret | What it is |
| --- | --- |
| `DEVELOPER_ID_P12` | The Developer ID Application certificate and private key, exported from Keychain Access as .p12, then `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_P12_PASSWORD` | The password chosen when exporting the .p12 |
| `NOTARY_KEY_P8` | An App Store Connect API key (Users and Access, Integrations, Developer role) as `base64 -i AuthKey_XXXX.p8` |
| `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | The key's ID and the issuer ID shown on the same page |

The certificate lives only in a temporary keychain that is deleted when the job ends.
