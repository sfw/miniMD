---
title: miniMD Sample
---

# miniMD Sample

This file exercises the bundled renderer used by the Finder Quick Look extension and the host app.

## Common Markdown

- Fast Finder previews for `.md`, `.markdown`, `.mdown`, `.mkd`, and `.mkdn`
- **Bold**, *italic*, `inline code`, and [links](https://developer.apple.com/documentation/quicklookui)
- Task items:
  - [x] Render Markdown to HTML
  - [ ] Tune the styles

> The extension returns HTML through `QLPreviewReply`, so Finder gets a native Quick Look preview without shipping a browser runtime.

```swift
let rendered = try MarkdownRenderer.renderFile(at: markdownURL)
reply.title = rendered.title
return Data(rendered.html.utf8)
```

| Feature | Status |
| :-- | --: |
| Finder spacebar preview | Ready |
| Host app PDF export | Ready |
| External dependencies | 0 |

---

The PDF exporter uses WebKit printing from the host app, which keeps the extension focused on previews.
