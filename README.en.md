# TextUI

[Deutsch](README.md) · **English**

A lightweight native text editor for macOS 15 and later on Apple Silicon.
TextUI focuses on `.txt`, `.md`, and `.html` files, multiple documents in tabs, and reliable recovery of unsaved work.

**Status: early release 0.1.1.** A public project licensed under **GPL-3.0-or-later**. Display name: **TextUI**; bundle name: **R3Ds TextUI**; stable bundle identifier: `com.r3d42.textui`.

[Downloads and release notes](https://github.com/r3d42-git/R3DsTextUI/releases) · [License](LICENSE) · [Licensing scope and third-party components](LICENSING.md)

To install, extract the release ZIP and drag `TextUI.app` into Applications. Only Apple Silicon Macs running macOS 15 or later are supported. Public release packages use Developer ID signing with Hardened Runtime, are notarized by Apple, and contain the app with its notarization ticket stapled to it.

## Current features

- Native AppKit text editing, automatic format detection by file extension, and DokuWiki detection based on the contents of `.txt` files. Syntax highlighting for Markdown, DokuWiki, and HTML, including embedded CSS. A dark blue editor palette in dark mode and a matching light palette in light mode.
- Multiple documents in tabs, line numbers, cursor position, and selection size.
- Go to line, document outline, font size controls, and line wrapping.
- Find and replace with case sensitivity, whole-word matching, and regular expressions.
- Explicit saving with `⌘S`, continuous local draft recovery, and optional automatic saving for files that already have a name and location.
- Optional Markdown, DokuWiki, and HTML preview (⌥⌘P) alongside the source. Markdown supports tables, task lists, and code blocks, among other features. The preview updates after a short pause in typing; document scripts and network access are disabled. Web links open in the default browser only after confirmation, and copy buttons let you copy code.

49 automated core and editor tests pass. Launch, basic editing, search, draft recovery, and an HTML document with 2,500 lines have been checked locally. Further details and outstanding checks are documented in `PROJECT_SUMMARY.md` (German).

Draft recovery does not replace an external backup. File conflicts, recovery after crashes, and user interactions remain areas for further testing.

## Saving and closing

`⌘S` writes changes to the selected file. For new documents, a file dialog lets you choose a name and location. Draft recovery independently preserves your working state in your local user profile.

When closing a modified tab, TextUI asks you to **Save**, **Discard**, or **Cancel**. Discarding also removes that tab's saved draft. Closing the window or quitting the app preserves the open session for restoration. Automatic saving is disabled by default.

## Local development

Requirements: Apple Silicon, macOS 15 or later, and Xcode with a Swift 6-capable toolchain. SwiftPM downloads the Markdown dependencies pinned in `Package.resolved`.

```sh
./script/build_and_run.sh
```

The script asks any running TextUI instance to quit normally, builds for `arm64`, creates `dist/TextUI.app`, applies a local ad hoc signature, and opens the app. It does not force-terminate the process. The local signature is neither Developer ID signing nor notarization for distribution to other Macs.

```sh
./script/build_and_run.sh --build-only
./script/build_and_run.sh --verify
swift test --arch arm64
```

`--verify` only checks whether the process is running after launch. Additional modes are `--debug`, `--logs`, and `--telemetry`. GitHub Actions runs tests and builds a local app bundle. Signing and publication run separately on the local machine through the release scripts.

## Project structure

- `Sources/TextUI`: AppKit application and editor interface.
- `Sources/TextUICore`: text and session logic that can be tested independently of the interface.
- `Tests/TextUICoreTests`: automated core tests.
- `Resources/Info.plist`: app metadata and supported file extensions.
- `script/build_and_run.sh`: local build and launch script.
- `PROJECT_SUMMARY.md`: decisions, project handoff, and outstanding checks (German).

## Privacy and publication

Source code and documentation do not require private credentials, private signing material, or absolute personal file paths. Build products and local development data do not belong in the repository. User documents, real drafts, and local session data must not be committed as test fixtures or issue attachments.

TextUI is licensed under GPL-3.0-or-later; third-party notices are preserved. See `LICENSING.md` (German) for details.

## Known limitations

Dragging tabs to reorder them is planned; tabs can currently be moved through the navigation menu. The preview loads neither external nor local image/CSS files and does not execute scripts from the document. The app's own copy buttons run separately from the document. Supported encodings are UTF-8 and UTF-16 with a BOM; other encodings are explicitly rejected. Regular-expression replacements treat replacement text literally.

Sessions, including unsaved text, are stored locally at `~/Library/Application Support/com.r3d42.textui/Session.json`. They are not uploaded.

## Markdown parser

The preview uses Swift Markdown 0.7.3 and swift-cmark 0.9.0. Versions and revisions are recorded in `Package.resolved`. Their license and copyright notices are stored in `Resources/ThirdPartyNotices` and included in the app bundle. SwiftPM downloads these dependencies during the first build; the preview itself works offline.

## DokuWiki documents

TextUI automatically recognizes typical DokuWiki content in `.txt` files and files without an extension by looking for multiple indicators within the first 32,768 characters. `.wiki` and `.dokuwiki` are recognized directly; explicit Markdown/HTML extensions take precedence. A single matching string or code example is deliberately not enough to trigger detection. The status bar shows the detected format.

Preview, syntax highlighting, and document outlines support common basic syntax: headings marked with equals signs, code/file blocks, forced line breaks, emphasis, wiki links, lists, tables, and quotes. Code and Nowiki regions are excluded from heading detection. Wiki plugins, server features, and media resolution are not included; internal wiki destinations are displayed as labels. Viewing a document does not change its source text, extension, or encoding.

## Building and verifying a release

On a Mac with an existing Developer ID signing identity and a configured `notarytool` keychain profile named `TextUI`:

```sh
./script/release.sh 0.1.1
./script/verify_release.sh 0.1.1 dist/release/0.1.1/TextUI-0.1.1-macOS-arm64.zip
git push -u origin main
# Wait for the GitHub CI run for this commit to succeed.
./script/publish_release.sh --dry-run 0.1.1
./script/publish_release.sh 0.1.1
```

`release.sh` requires a clean, committed source tree, runs all tests, creates an optimized build, signs and notarizes the app, and staples the ticket before creating the ZIP. `SIGNING_IDENTITY` and `NOTARY_PROFILE` support local overrides. Credentials remain exclusively in the keychain. An existing release output directory is never overwritten. If notarization is interrupted, first check the existing submission using its submission ID or the notarization history; do not upload it again.

`verify_release.sh` extracts the supplied ZIP into a fresh directory and checks the version, bundle identifier, architecture, license files, signature, Hardened Runtime, ticket, and Gatekeeper assessment. `publish_release.sh` requires a clean `main` branch, a matching source commit, a successful GitHub CI run for that commit, a public target repository, and an unused tag. After uploading, it downloads the ZIP and checksum again, compares the GitHub digest, and verifies the downloaded app. The scripts need access to the network, keychain, and macOS security services; a restricted sandbox may block those services.
