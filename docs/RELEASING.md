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
