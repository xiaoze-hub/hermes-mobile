# Android App online updates

The App Update page reads the latest GitHub Release asset `update.json`, downloads the APK referenced by `apkUrl`, verifies its SHA-256, then opens Android's package installer. Android still asks the user to confirm installation.

## Keep the install signature stable

Every APK installed over an existing build must use the same signing key. The current locally built APK is signed with this workstation's Android debug key (`%USERPROFILE%\.android\debug.keystore`). The first tagged release must use that same key if it must update this build. After that, keep the key permanently; losing it prevents in-place updates.

Configure these GitHub Actions repository secrets before pushing a release tag:

- `ANDROID_KEYSTORE_BASE64`: base64 contents of the signing keystore
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

The publish workflow checks that the tag version matches `version:` in `pubspec.yaml`, signs the APK, calculates its SHA-256, and uploads `hermes-mobile.apk` plus `update.json` to a GitHub Release. To publish, update `pubspec.yaml`, add release notes as needed, and push a matching `vX.Y.Z` tag. Do not commit `android/key.properties` or the keystore.

Example manifest:

```json
{
  "version": "1.1.0",
  "buildNumber": 2,
  "apkUrl": "https://github.com/xiaoze-hub/hermes-mobile/releases/latest/download/hermes-mobile.apk",
  "sha256": "64 lowercase hex characters",
  "notes": "Release notes shown in the App"
}
```
