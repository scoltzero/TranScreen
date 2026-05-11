# Releasing TranScreen

Two ways to ship a signed and notarized `.dmg`:

- **Local**: run `./build.sh` on a Mac that has a Developer ID certificate and a `notarytool` keychain profile.
- **CI**: push a `v*` tag (or run the `Release` workflow manually) and GitHub Actions builds, signs, notarizes, and drafts a GitHub Release.

## Local build

Prerequisites (one-time):

1. Enroll in the Apple Developer Program and install a **Developer ID Application** certificate in your login keychain
   (Xcode → Settings → Accounts → Manage Certificates → +).
2. Generate an [App-Specific Password](https://account.apple.com/account/manage)
   and store it in the keychain so `notarytool` can upload submissions without re-prompting:

   ```bash
   xcrun notarytool store-credentials transcreen-notary \
       --apple-id "<your-apple-id-email>" \
       --team-id "<YOUR_TEAM_ID>"
   ```

Then:

```bash
TEAM_ID=<YOUR_TEAM_ID> ./build.sh
```

Output: `build/TranScreen-<version>.dmg` — already signed, notarized, and stapled. The full pass takes 5–15 minutes (mostly Apple's notarization queue).

Override the keychain profile name with `NOTARY_PROFILE=...` if you used a different label.

## CI build (GitHub Actions)

The `Release` workflow (`.github/workflows/release.yml`) runs the same `build.sh` on a `macos-15` runner. It needs six repository secrets:

| Secret | What it is | How to get it |
|---|---|---|
| `BUILD_CERTIFICATE_BASE64` | Base64-encoded `.p12` export of the Developer ID Application certificate (including its private key) | Keychain Access → right-click the certificate → Export → `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `P12_PASSWORD` | Password you set when exporting the `.p12` | You set it during export |
| `KEYCHAIN_PASSWORD` | Any random string; used only inside the runner | Generate with `openssl rand -base64 24` |
| `NOTARY_APPLE_ID` | Apple ID email used for notarization | Your developer account email |
| `NOTARY_PASSWORD` | App-Specific Password (`xxxx-xxxx-xxxx-xxxx`) | https://account.apple.com → App-Specific Passwords |
| `NOTARY_TEAM_ID` | 10-character Team ID | https://developer.apple.com/account → top-right |

Add each at **Settings → Secrets and variables → Actions → New repository secret**.

### Trigger a release

Bump `MARKETING_VERSION` in the Xcode project, commit, then:

```bash
git tag v1.2.0
git push origin v1.2.0
```

Or use the Actions tab → Release → Run workflow → enter a tag name.

The workflow produces a **draft** GitHub Release with the `.dmg` attached. Review the auto-generated notes, then click Publish.
