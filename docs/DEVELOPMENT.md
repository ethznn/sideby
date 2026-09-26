# Development

This file keeps only the practical setup notes needed to work on Sideby.

## Requirements

- macOS 14 or later.
- Xcode with a Swift 6 toolchain.

## Commands

Run tests:

```bash
swift test
```

Before building a local product bundle, read the current published
[Sparkle feed](https://github.com/ethznn/sideby/releases/latest/download/appcast.xml)
and set `SIDEBY_BUILD_NUMBER` to its latest `sparkle:version` plus one. If the
published build number cannot be verified, check GitHub release metadata before
building. Do not rely on the script's default build number after a public release.

Also set `SIDEBY_VERSION` to the version being verified. With both environment
variables set, build local app bundles:

```bash
scripts/build_app_bundle.sh
scripts/build_dev_app_bundle.sh
```

`build_app_bundle.sh` defaults to a release build. Override with `SIDEBY_BUILD_CONFIGURATION=debug` when you need a faster local product build. `build_dev_app_bundle.sh` defaults to debug.
The bundle scripts use a local Developer ID or Apple Development signing identity when one is available, and otherwise sign ad-hoc for local testing.

To keep local apps out of Spotlight results, direct build products and bundles to
absolute paths inside a `.noindex` directory. These overrides are shared by the
app, development app, DMG, and Sparkle preparation scripts:

```bash
export SIDEBY_BUILD_PATH=/tmp/sideby-build.noindex/build
export SIDEBY_OUTPUT_DIR=/tmp/sideby-build.noindex/output
```

Without overrides, SwiftPM uses `.build` and bundles/assets use `dist` in the
checkout. Do not launch a development copy from `dist` when verifying the installed
app. The README renderer also accepts `SIDEBY_BUILD_PATH`; media intermediates
default to its `readme-media` subdirectory.

Build a Sparkle-enabled release DMG with explicit release metadata. Set
`SIDEBY_VERSION` to the intended release and `SIDEBY_BUILD_NUMBER` to a number
higher than the published feed, then run:

```bash
scripts/validate_release_metadata.sh "$SIDEBY_VERSION" "$SIDEBY_BUILD_NUMBER"
scripts/build_release_dmg.sh
```

The DMG script is included so release packaging stays reproducible. It requires
both values, verifies that the built app's `CFBundleShortVersionString` and
`CFBundleVersion` match them, and signs the DMG when a local signing identity is
available.

Release notarization is maintainer-local: submit the generated DMG to Apple's
notary service using credentials stored in your local Keychain, then staple the
accepted ticket to the DMG. Do not commit Apple ID credentials, App Store
Connect keys, certificates, provisioning profiles, keychain profile names, or
notarization output logs.

After the signed DMG is notarized and stapled, prepare the signed Sparkle assets:

```bash
# Submit the DMG to Apple's notary service, then staple it locally.

SIDEBY_RELEASE_NOTES_PATH="docs/releases/$SIDEBY_VERSION.md" \
scripts/prepare_sparkle_release.sh
```

The preparation script verifies the Apple-anchored Developer ID Application
requirement and the stapled ticket before using Sparkle's `sideby-sparkle`
Keychain account. It then requires exactly one appcast item whose version,
build number, DMG URL, and release-notes URL match the requested release before
printing the three asset paths. Upload the versioned DMG, version-specific
Markdown release notes, and signed `appcast.xml` to a draft GitHub release
before publishing it.

## Update System

Sideby uses Sparkle 2 for updates after the first Sparkle-enabled release. Users
of 0.6.0 and earlier must install that first release manually; later releases can
be discovered, downloaded, verified, installed, and relaunched from the app.

The product app owns one `SPUStandardUpdaterController`. It starts with the app,
uses Sparkle's standard update UI, and exposes a manual **Check for Updates...**
action in **Settings → General**. Sparkle asks whether
to enable automatic checks on the second launch. If the user opts in,
scheduled checks run once per day. Scheduled checks stay quiet when there is no
update or the network is unavailable; manual checks show Sparkle's standard
result or error UI. Download, installation, and relaunch always require user
approval.

The updater reads a signed appcast from:

```text
https://github.com/ethznn/sideby/releases/latest/download/appcast.xml
```

Each published GitHub release contains the notarized DMG, version-specific
Markdown release notes, and `appcast.xml`. The appcast points to the immutable,
versioned release assets rather than another `latest` download URL. The app and
update feed require HTTPS, Developer ID signing, notarization, and Sparkle EdDSA
signatures. The EdDSA private key stays in the maintainer's login Keychain; only
the public key is embedded in `Sideby.app`. Signed-feed verification and archive
verification occur before extraction. Invalid or damaged updates are rejected
without replacing the installed app.

Sideby uses an increasing numeric `CFBundleVersion` as Sparkle's machine version
and `CFBundleShortVersionString` as the user-facing release version. A release
build must receive both values explicitly and must not reuse a previous build
number. The local validator establishes the first Sparkle release baseline by
requiring a build number greater than the shipped build `1`; before every later
release, maintainers must compare the requested build number with published
releases and choose a strictly higher value. The initial implementation ships
full-DMG updates only; binary delta updates and prerelease channels remain out
of scope.

The existing local release flow remains authoritative:

1. Build the app and DMG with explicit release and build versions.
2. Sign with Developer ID, submit for notarization, and staple the accepted
   ticket to the DMG.
3. Use Sparkle's release tools to sign the DMG and release notes and generate a
   signed `appcast.xml` with versioned GitHub asset URLs.
4. Upload all three assets to a draft GitHub release.
5. Verify the appcast, asset URLs, Apple signatures, notarization ticket, and
   Sparkle signatures before publishing the release.

Automated checks cover updater action wiring, localized labels, required bundle
metadata, framework embedding, the first-release build-number baseline,
public-document hygiene, and bundle signature structure. Before publishing the
first Sparkle-enabled release, perform one end-to-end update between two genuine
Developer ID signed and notarized builds using a temporary signed test feed.

Open the package in Xcode:

```bash
xed Package.swift
```

Use `SidebyApp` for the product app and `SidebyDevApp` for local probes. Probe-only helpers live in `SidebyDevSupport` so the product app does not carry command-line experiment runners.

## Verification before release

Run the full test suite and packaging guards:

```bash
swift test
bash scripts/test_check_public_docs.sh
bash scripts/check_public_docs.sh
bash scripts/test_validate_release_metadata.sh
bash scripts/test_verify_sparkle_bundle.sh
```

The public-document guard checks tracked and nonignored new files, including
files not staged yet. Keep internal plans, real display identifiers, personal
paths, and probe logs outside the public tree. Inspect newly added media as well;
a text scan cannot establish whether an image or video contains personal data.

In a graphical macOS session, run the opt-in native window checks with
`SIDEBY_NATIVE_EVIDENCE=1 swift test`. Use `SIDEBY_NATIVE_EVIDENCE_OUTPUT` to send
their screenshots to a local `.noindex` directory. These tests use sample data;
before publishing, also verify real desktop switching, shortcut release, and
menu interaction on the supported macOS versions and display setups available
to the maintainer.

After updating README assets, run `swift scripts/verify_readme_media.swift` as
described in [README media](media/README.md). The repository keeps the images
and GIFs used by the documentation; promotional MP4s and their production
pipeline stay in the Git-ignored `marketing/` directory (see
[README media](media/README.md#marketing-workspace-and-publishing)). CI does not require those local production files.
When publishing the corresponding release, upload the four linked brand-film
MP4s as release attachments and verify their downloads. Remove the release
draft label and update both READMEs' version and download-availability notes.

## Repository Shape

```text
Sources/
  SidebyApp/       product app
  SidebyDevApp/    local development harness
  SidebyDevSupport/ local probe helpers
  SidebyCore/      domain models and pure logic
  SidebySystem/    macOS system adapters
  SidebyUI/        reusable SwiftUI views
Tests/
  SidebyCoreTests/
  SidebySystemTests/
  SidebyUITests/
```

## Pull Requests

- Keep changes focused.
- Add or update tests for logic changes.
- Run `swift test` before opening a pull request.
- For macOS permission, global input, synthetic input, bundle signing, or distribution changes, open an issue first so the tradeoffs are clear.
