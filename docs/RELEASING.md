# Releasing Chamfer

Chamfer ships outside the App Store, so it updates itself. The shape of it:

```
git push          →  CI: build + test. Ships nothing.
git tag v1.2.0    →  Release: build, sign, notarise, publish, update the feed.
                     Installed copies see it on their next daily check.
```

Tags ship and pushes do not, deliberately. An afternoon's unfinished work on a
branch cannot reach anybody's Mac by being pushed.

## Cutting a release

```bash
git tag v1.2.0
git push origin v1.2.0
```

That is the whole procedure. The workflow runs the suite first and stops if it
fails, so a tag on a broken commit publishes nothing.

To rebuild a version without moving the tag, run the Release workflow manually
from the Actions tab and give it the version number.

## One-time setup

None of this can be done from a workflow, and until it is done the Release
workflow fails at the first missing value rather than publishing something
unsigned.

### 1. Sparkle signing keys

Sparkle verifies every download against a key compiled into the app. Generate
the pair once:

```bash
swift build   # fetches Sparkle
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

It writes the private key to your login Keychain and prints the public key.
Then export the private key so CI can have it:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key.txt
```

Keep that file somewhere safe and out of the repository. **If it is lost,
existing installs can never be updated again** — they will only accept
downloads signed by the key they shipped with.

### 2. Apple Developer ID

Notarisation needs a paid Apple Developer account. From it you need a
**Developer ID Application** certificate, exported from Keychain Access as a
`.p12` with a password, then base64-encoded:

```bash
base64 -i DeveloperID.p12 | pbcopy
```

You also need an **app-specific password** for your Apple ID, created at
appleid.apple.com, not your account password.

### 3. GitHub Pages, for the feed

The appcast has to live at a stable URL. The workflow commits it to a
`gh-pages` branch; enable Pages for that branch in the repository settings. The
feed is then:

```
https://<owner>.github.io/Chamfer/appcast.xml
```

### 4. Repository secrets and variables

**Settings → Secrets and variables → Actions.**

| Secret | What it is |
|---|---|
| `SPARKLE_PRIVATE_KEY` | Contents of the exported private key file |
| `DEVELOPER_ID_P12_BASE64` | The base64 of your `.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | Password you gave the `.p12` on export |
| `DEVELOPER_ID_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `KEYCHAIN_PASSWORD` | Any string; it unlocks the throwaway CI keychain |
| `APPLE_ID` | The Apple ID email for notarisation |
| `APPLE_TEAM_ID` | Ten-character team identifier |
| `APPLE_APP_PASSWORD` | The app-specific password from step 2 |

| Variable | What it is |
|---|---|
| `SPARKLE_FEED_URL` | The Pages URL from step 3 |
| `SPARKLE_PUBLIC_KEY` | The public key printed by `generate_keys` |

Variables rather than secrets for the last two: both are baked into every
shipped `Info.plist` and are public by construction. Storing them as secrets
would only make them harder to check.

## What a build without keys does

Nothing, and on purpose. `Scripts/package.sh` writes no feed URL and no public
key unless `SPARKLE_FEED_URL` and `SPARKLE_PUBLIC_KEY` are in the environment,
and `AppUpdates` creates no updater without both. A locally built `Chamfer.app`
has "Check for Updates…" greyed out and never contacts anything — which is what
should happen when you run the thing you are working on.

## Building a bundle locally

```bash
Scripts/package.sh 1.2.0 41       # → .build/artifacts/Chamfer.app
```

Unsigned, so Gatekeeper will complain on any Mac but this one. It is for
checking that the bundle is right, not for giving to anybody.

## Versioning

`CFBundleShortVersionString` is the tag without its `v`. `CFBundleVersion` is
the commit count, which only ever goes up — Sparkle compares builds, and two
releases sharing a number is the one way to make an update invisible.
