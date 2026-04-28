# miniMD

miniMD is a self-contained macOS app with an embedded Quick Look Preview Extension for Markdown files. It gives Finder a polished spacebar preview for Markdown documents and includes a small host app for opening, editing, saving, and exporting Markdown.

## Features

- Finder spacebar previews through `com.apple.quicklook.preview`
- Host app for opening, dropping, editing, saving, and saving as Markdown
- GitHub-style Markdown rendering with dark and light color support
- PDF export with `Paginated` or `Continuous` layout choices
- File > Open Recent menu with the last five opened Markdown files
- View > Appearance menu with `Automatic`, `Light`, and `Dark`
- Markdown formatting helpers from the Insert menu
- No third-party runtime dependencies

Supported filename extensions: `.md`, `.markdown`, `.mdown`, `.mkd`, and `.mkdn`.

## Build

```sh
make build
```

The built app lands at:

```sh
.build/DerivedData/Build/Products/Release/miniMD.app
```

The equivalent Xcode command is:

```sh
xcodebuild \
  -project MarkdownQuickLook.xcodeproj \
  -scheme MarkdownQuickLook \
  -configuration Release \
  -derivedDataPath .build/DerivedData \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-"
```

## Package a DMG

```sh
make dmg
```

The distributable image lands at:

```sh
dist/miniMD.dmg
```

`dist/` is intentionally ignored by Git so release artifacts do not get committed.

## Install Locally

Move `miniMD.app` to `/Applications`, then launch it once so Launch Services sees the Markdown document type and the embedded extension.

If Finder still shows an old preview, refresh Quick Look:

```sh
make refresh-quicklook
```

You can inspect registered Quick Look preview extensions with:

```sh
pluginkit -m -p com.apple.quicklook.preview
```

## PDF Export

Open a Markdown file in miniMD, then choose File > Export PDF... or use the export button in the toolbar.

The export sheet includes a Layout option:

- `Paginated`: letter-sized PDF pages, suitable for sharing or printing
- `Continuous`: one long page, useful for archival or visual capture

The app renders with WebKit and uses direct PDF generation instead of the macOS print operation, which avoids blank output from offscreen print jobs.

## Distribution Notes

Local development uses ad-hoc signing. For distribution to other users, sign with a Developer ID Application certificate, notarize the app, and staple the result before publishing a DMG.

The project currently uses placeholder bundle identifiers:

- `com.example.MarkdownQuickLook`
- `com.example.MarkdownQuickLook.PreviewExtension`

Before a public release, change those identifiers to your own reverse-DNS namespace.

## GitHub

Target repository:

```sh
https://github.com/sfw/miniMD.git
```
