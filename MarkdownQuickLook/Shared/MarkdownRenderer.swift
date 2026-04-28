import Foundation

struct RenderedMarkdown {
    let title: String
    let html: String
}

enum MarkdownRenderer {
    static func renderFile(at url: URL) throws -> RenderedMarkdown {
        let markdown = try markdownSource(at: url)
        let title = documentTitle(from: markdown) ?? url.deletingPathExtension().lastPathComponent
        return render(markdown: markdown, title: title, baseURL: url.deletingLastPathComponent())
    }

    static func markdownSource(at url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return decodeMarkdown(data)
    }

    static func render(markdown: String, title: String, baseURL: URL? = nil) -> RenderedMarkdown {
        var parser = MarkdownBlockParser(markdown: markdown, baseURL: baseURL)
        let body = parser.render()
        return RenderedMarkdown(title: title, html: htmlDocument(title: title, body: body))
    }

    static func emptyDocument() -> RenderedMarkdown {
        render(
            markdown: """
            # miniMD

            Open or drop a Markdown file to preview it here.
            """,
            title: "miniMD"
        )
    }

    private static func decodeMarkdown(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8.trimmingPrefix("\u{feff}")
        }

        if let utf16 = String(data: data, encoding: .utf16) {
            return utf16.trimmingPrefix("\u{feff}")
        }

        return String(decoding: data, as: UTF8.self).trimmingPrefix("\u{feff}")
    }

    private static func documentTitle(from markdown: String) -> String? {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        if let frontMatterTitle = frontMatterTitle(in: lines) {
            return frontMatterTitle
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { continue }

            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            guard (1...6).contains(hashes) else { continue }

            let afterHashes = trimmed.dropFirst(hashes)
            guard afterHashes.first == " " else { continue }

            let title = afterHashes.trimmingCharacters(in: .whitespacesAndNewlines).trimmingTrailingHashes()
            return title.isEmpty ? nil : title
        }

        return nil
    }

    private static func frontMatterTitle(in lines: [String]) -> String? {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." {
                return nil
            }

            let lowercased = trimmed.lowercased()
            if lowercased.hasPrefix("title:") {
                let value = trimmed.dropFirst("title:".count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingMatchingQuotes()
                return value.isEmpty ? nil : value
            }
        }

        return nil
    }

    private static func htmlDocument(title: String, body: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapeHTML(title))</title>
          <style>
            :root {
              color-scheme: light dark;
              --canvas: #ffffff;
              --canvas-subtle: #f6f8fa;
              --fg: #24292f;
              --fg-muted: #57606a;
              --border: #d0d7de;
              --border-muted: #d8dee4;
              --accent: #0969da;
              --code-bg: rgba(175, 184, 193, 0.2);
              --row: #f6f8fa;
              --kbd-shadow: rgba(27, 31, 36, 0.12);
            }

            @media (prefers-color-scheme: dark) {
              :root {
                --canvas: #0d1117;
                --canvas-subtle: #161b22;
                --fg: #e6edf3;
                --fg-muted: #8b949e;
                --border: #30363d;
                --border-muted: #21262d;
                --accent: #58a6ff;
                --code-bg: rgba(110, 118, 129, 0.4);
                --row: #161b22;
                --kbd-shadow: rgba(110, 118, 129, 0.2);
              }
            }

            * {
              box-sizing: border-box;
            }

            html {
              background: var(--canvas);
              color: var(--fg);
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
              font-size: 16px;
              line-height: 1.5;
              -webkit-text-size-adjust: 100%;
            }

            body {
              margin: 0;
              min-height: 100vh;
              padding: 32px;
            }

            .markdown-body {
              margin: 0 auto;
              max-width: 980px;
              min-width: 200px;
              overflow-wrap: break-word;
            }

            h1, h2, h3, h4, h5, h6 {
              color: var(--fg);
              font-weight: 600;
              letter-spacing: 0;
              line-height: 1.25;
              margin: 24px 0 16px;
            }

            h1:first-child,
            h2:first-child,
            h3:first-child {
              margin-top: 0;
            }

            h1 {
              border-bottom: 1px solid var(--border-muted);
              font-size: 2em;
              padding-bottom: 0.3em;
            }

            h2 {
              border-bottom: 1px solid var(--border-muted);
              font-size: 1.5em;
              padding-bottom: 0.3em;
            }

            h3 { font-size: 1.25em; }
            h4 { font-size: 1em; }
            h5 { font-size: 0.875em; }
            h6 {
              color: var(--fg-muted);
              font-size: 0.85em;
            }

            p,
            blockquote,
            ul,
            ol,
            dl,
            table,
            pre,
            details {
              margin: 0 0 16px;
            }

            a {
              color: var(--accent);
              text-decoration: none;
            }

            a:hover {
              text-decoration: underline;
            }

            strong {
              font-weight: 600;
            }

            code {
              background: var(--code-bg);
              border-radius: 6px;
              font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
              font-size: 85%;
              padding: 0.2em 0.4em;
            }

            pre {
              background: var(--canvas-subtle);
              border-radius: 6px;
              line-height: 1.45;
              overflow-x: auto;
              padding: 16px;
            }

            pre code {
              background: transparent;
              border-radius: 0;
              display: block;
              font-size: 85%;
              padding: 0;
              white-space: pre;
            }

            blockquote {
              border-left: 0.25em solid var(--border);
              color: var(--fg-muted);
              padding: 0 1em;
            }

            blockquote > :last-child {
              margin-bottom: 0;
            }

            hr {
              background-color: var(--border-muted);
              border: 0;
              height: 0.25em;
              margin: 24px 0;
              padding: 0;
            }

            img {
              border-radius: 8px;
              display: block;
              height: auto;
              margin: 1rem 0;
              max-width: 100%;
            }

            ul, ol {
              padding-left: 2em;
            }

            li + li {
              margin-top: 0.25em;
            }

            li > p {
              margin-top: 16px;
            }

            li.task {
              list-style: none;
              margin-left: -1.4em;
            }

            .task-marker {
              color: var(--fg-muted);
              display: inline-block;
              font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
              margin-right: 0.4em;
              width: 1em;
            }

            table {
              border-collapse: collapse;
              display: block;
              overflow-x: auto;
              width: 100%;
            }

            th, td {
              border: 1px solid var(--border);
              padding: 6px 13px;
              text-align: left;
              vertical-align: top;
            }

            th {
              font-weight: 650;
            }

            tr:nth-child(even) td {
              background: var(--row);
            }

            html.mini-md-pdf-export {
              --canvas: #ffffff;
              --canvas-subtle: #f6f8fa;
              --fg: #24292f;
              --fg-muted: #57606a;
              --border: #d0d7de;
              --border-muted: #d8dee4;
              --accent: #0969da;
              --code-bg: rgba(175, 184, 193, 0.2);
              --row: #f6f8fa;
              --kbd-shadow: rgba(27, 31, 36, 0.12);
              background: white;
              color: #111;
              color-scheme: light;
            }

            html.mini-md-pdf-export body {
              background: white;
              color: #111;
              padding: 0;
            }

            html.mini-md-pdf-export .markdown-body {
              max-width: none;
            }

            html.mini-md-pdf-export h1,
            html.mini-md-pdf-export h2,
            html.mini-md-pdf-export h3,
            html.mini-md-pdf-export h4,
            html.mini-md-pdf-export h5,
            html.mini-md-pdf-export h6 {
              break-after: avoid;
              page-break-after: avoid;
            }

            html.mini-md-pdf-export h1,
            html.mini-md-pdf-export h2,
            html.mini-md-pdf-export h3,
            html.mini-md-pdf-export blockquote,
            html.mini-md-pdf-export details,
            html.mini-md-pdf-export figure,
            html.mini-md-pdf-export img,
            html.mini-md-pdf-export li,
            html.mini-md-pdf-export pre,
            html.mini-md-pdf-export table,
            html.mini-md-pdf-export tr {
              break-inside: avoid;
              page-break-inside: avoid;
            }

            html.mini-md-pdf-export thead {
              display: table-header-group;
            }

            html.mini-md-pdf-export div.pdf-page-spacer {
              display: block;
            }

            html.mini-md-pdf-export a {
              color: #075f63;
            }

            @media print {
              @page {
                size: letter;
                margin: 0;
              }

              html, body {
                background: white;
                color: #111;
              }

              body {
                padding: 0;
              }

              main {
                max-width: none;
              }

              h1, h2, h3, h4, h5, h6 {
                break-after: avoid;
                page-break-after: avoid;
              }

              h1, h2, h3,
              blockquote,
              details,
              figure,
              img,
              li,
              pre,
              table,
              tr {
                break-inside: avoid;
                page-break-inside: avoid;
              }

              thead {
                display: table-header-group;
              }

              div.pdf-page-spacer {
                display: block;
              }

              a {
                color: #075f63;
              }
            }
          </style>
        </head>
        <body>
          <main class="markdown-body">
        \(body)
          </main>
        </body>
        </html>
        """
    }
}

private struct MarkdownBlockParser {
    private let lines: [String]
    private let baseURL: URL?
    private var index = 0

    init(markdown: String, baseURL: URL?) {
        self.lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        self.baseURL = baseURL
    }

    mutating func render() -> String {
        skipFrontMatter()

        var blocks: [String] = []
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
            } else if let code = parseFencedCode() {
                blocks.append(code)
            } else if let heading = parseHeading() {
                blocks.append(heading)
            } else if let rule = parseHorizontalRule() {
                blocks.append(rule)
            } else if let quote = parseBlockquote() {
                blocks.append(quote)
            } else if let table = parseTable() {
                blocks.append(table)
            } else if let list = parseList() {
                blocks.append(list)
            } else {
                blocks.append(parseParagraph())
            }
        }

        return blocks.joined(separator: "\n")
    }

    private mutating func skipFrontMatter() {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return }

        for candidate in 1..<lines.count {
            let trimmed = lines[candidate].trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." {
                index = candidate + 1
                return
            }
        }
    }

    private func beginsBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty
            || fencedCodeMarker(trimmed) != nil
            || headingLevel(trimmed) != nil
            || isHorizontalRule(trimmed)
            || trimmed.hasPrefix(">")
            || listMarker(in: line) != nil
    }

    private mutating func parseHeading() -> String? {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        guard let level = headingLevel(trimmed) else { return nil }

        let rawText = String(trimmed.dropFirst(level))
            .trimmingCharacters(in: .whitespaces)
            .trimmingTrailingHashes()
        index += 1

        return "<h\(level)>\(MarkdownInlineRenderer.html(for: rawText, baseURL: baseURL))</h\(level)>"
    }

    private mutating func parseHorizontalRule() -> String? {
        guard isHorizontalRule(lines[index].trimmingCharacters(in: .whitespaces)) else { return nil }
        index += 1
        return "<hr>"
    }

    private mutating func parseFencedCode() -> String? {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        guard let marker = fencedCodeMarker(trimmed) else { return nil }

        let language = trimmed.dropFirst(marker.count)
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .first ?? ""
        index += 1

        var codeLines: [String] = []
        while index < lines.count {
            let candidate = lines[index].trimmingCharacters(in: .whitespaces)
            if candidate.hasPrefix(marker) {
                index += 1
                break
            }

            codeLines.append(lines[index])
            index += 1
        }

        let classAttribute = language.isEmpty ? "" : " class=\"language-\(escapeAttribute(language))\""
        return "<pre><code\(classAttribute)>\(escapeHTML(codeLines.joined(separator: "\n")))</code></pre>"
    }

    private mutating func parseBlockquote() -> String? {
        guard lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") else { return nil }

        var quoteLines: [String] = []
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }

            var stripped = String(trimmed.dropFirst())
            if stripped.hasPrefix(" ") {
                stripped.removeFirst()
            }
            quoteLines.append(stripped)
            index += 1
        }

        var nested = MarkdownBlockParser(markdown: quoteLines.joined(separator: "\n"), baseURL: baseURL)
        return "<blockquote>\n\(nested.render())\n</blockquote>"
    }

    private mutating func parseTable() -> String? {
        guard index + 1 < lines.count else { return nil }
        guard lines[index].contains("|"), tableSeparatorCells(in: lines[index + 1]) != nil else { return nil }

        let headers = tableCells(in: lines[index])
        let alignments = tableSeparatorCells(in: lines[index + 1]) ?? []
        guard !headers.isEmpty else { return nil }

        index += 2
        var rows: [[String]] = []
        while index < lines.count {
            let line = lines[index]
            guard line.contains("|"), !line.trimmingCharacters(in: .whitespaces).isEmpty else { break }
            rows.append(tableCells(in: line))
            index += 1
        }

        let headerHTML = headers.enumerated().map { column, value in
            let style = tableAlignmentStyle(at: column, alignments: alignments)
            return "<th\(style)>\(MarkdownInlineRenderer.html(for: value, baseURL: baseURL))</th>"
        }.joined()

        let bodyHTML = rows.map { row in
            let cells = headers.indices.map { column in
                let value = column < row.count ? row[column] : ""
                let style = tableAlignmentStyle(at: column, alignments: alignments)
                return "<td\(style)>\(MarkdownInlineRenderer.html(for: value, baseURL: baseURL))</td>"
            }.joined()
            return "<tr>\(cells)</tr>"
        }.joined(separator: "\n")

        return """
        <table>
          <thead><tr>\(headerHTML)</tr></thead>
          <tbody>
        \(bodyHTML)
          </tbody>
        </table>
        """
    }

    private mutating func parseList() -> String? {
        guard let firstMarker = listMarker(in: lines[index]) else { return nil }

        let tag = firstMarker.ordered ? "ol" : "ul"
        var items: [String] = []

        while index < lines.count, let marker = listMarker(in: lines[index]), marker.ordered == firstMarker.ordered {
            var text = marker.text
            index += 1

            while index < lines.count {
                let line = lines[index]
                if line.trimmingCharacters(in: .whitespaces).isEmpty || listMarker(in: line) != nil || beginsBlock(line) {
                    break
                }

                text += " " + line.trimmingCharacters(in: .whitespaces)
                index += 1
            }

            let renderedItem = MarkdownInlineRenderer.html(for: text, baseURL: baseURL)
            items.append(renderListItem(renderedItem, source: text))
        }

        return "<\(tag)>\n\(items.joined(separator: "\n"))\n</\(tag)>"
    }

    private func renderListItem(_ renderedItem: String, source: String) -> String {
        if source.hasPrefix("[ ] ") {
            let body = MarkdownInlineRenderer.html(for: String(source.dropFirst(4)), baseURL: baseURL)
            return "<li class=\"task\"><span class=\"task-marker\">&#x2610;</span>\(body)</li>"
        }

        if source.lowercased().hasPrefix("[x] ") {
            let body = MarkdownInlineRenderer.html(for: String(source.dropFirst(4)), baseURL: baseURL)
            return "<li class=\"task\"><span class=\"task-marker\">&#x2611;</span>\(body)</li>"
        }

        return "<li>\(renderedItem)</li>"
    }

    private mutating func parseParagraph() -> String {
        var paragraphLines: [String] = []

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                break
            }

            if !paragraphLines.isEmpty && (beginsBlock(line) || parseTableLookahead()) {
                break
            }

            paragraphLines.append(line.trimmingCharacters(in: .whitespaces))
            index += 1
        }

        let text = paragraphLines.joined(separator: " ")
        return "<p>\(MarkdownInlineRenderer.html(for: text, baseURL: baseURL))</p>"
    }

    private func parseTableLookahead() -> Bool {
        guard index + 1 < lines.count else { return false }
        return lines[index].contains("|") && tableSeparatorCells(in: lines[index + 1]) != nil
    }

    private func headingLevel(_ trimmed: String) -> Int? {
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        guard trimmed.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private func fencedCodeMarker(_ trimmed: String) -> String? {
        if trimmed.hasPrefix("```") { return "```" }
        if trimmed.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private func isHorizontalRule(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == "-" }
            || compact.allSatisfy { $0 == "*" }
            || compact.allSatisfy { $0 == "_" }
    }

    private func listMarker(in line: String) -> (ordered: Bool, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 2 else { return nil }

        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return (false, String(trimmed.dropFirst(marker.count)))
        }

        var digitCount = 0
        for character in trimmed {
            if character.isNumber {
                digitCount += 1
            } else {
                break
            }
        }

        guard digitCount > 0, digitCount + 1 < trimmed.count else { return nil }
        let markerIndex = trimmed.index(trimmed.startIndex, offsetBy: digitCount)
        let separator = trimmed[markerIndex]
        guard separator == "." || separator == ")" else { return nil }

        let afterSeparator = trimmed.index(after: markerIndex)
        guard afterSeparator < trimmed.endIndex, trimmed[afterSeparator] == " " else { return nil }
        return (true, String(trimmed[trimmed.index(after: afterSeparator)...]))
    }

    private func tableCells(in line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }

        return trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func tableSeparatorCells(in line: String) -> [String]? {
        let cells = tableCells(in: line)
        guard !cells.isEmpty else { return nil }

        let valid = cells.allSatisfy { cell in
            let compact = cell.replacingOccurrences(of: " ", with: "")
            let trimmed = compact.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return compact.count >= 3 && trimmed.allSatisfy { $0 == "-" }
        }

        return valid ? cells : nil
    }

    private func tableAlignmentStyle(at column: Int, alignments: [String]) -> String {
        guard column < alignments.count else { return "" }
        let compact = alignments[column].replacingOccurrences(of: " ", with: "")
        if compact.hasPrefix(":") && compact.hasSuffix(":") {
            return " style=\"text-align: center\""
        }
        if compact.hasSuffix(":") {
            return " style=\"text-align: right\""
        }
        return ""
    }
}

private enum MarkdownInlineRenderer {
    static func html(for text: String, baseURL: URL?) -> String {
        var renderer = InlineScanner(text: text, baseURL: baseURL)
        return renderer.render(until: nil)
    }

    private struct InlineScanner {
        let text: String
        let baseURL: URL?
        var index: String.Index

        init(text: String, baseURL: URL?) {
            self.text = text
            self.baseURL = baseURL
            self.index = text.startIndex
        }

        mutating func render(until delimiter: String?) -> String {
            var output = ""

            while index < text.endIndex {
                if let delimiter, hasPrefix(delimiter, at: index) {
                    break
                }

                if let code = parseCodeSpan() {
                    output += code
                } else if let image = parseImage() {
                    output += image
                } else if let link = parseLink() {
                    output += link
                } else if let strong = parseDelimited("**", tag: "strong") {
                    output += strong
                } else if let strong = parseDelimited("__", tag: "strong") {
                    output += strong
                } else if let strike = parseDelimited("~~", tag: "del") {
                    output += strike
                } else if let emphasis = parseDelimited("*", tag: "em") {
                    output += emphasis
                } else if let emphasis = parseDelimited("_", tag: "em") {
                    output += emphasis
                } else {
                    output += escapeHTML(String(text[index]))
                    index = text.index(after: index)
                }
            }

            return output
        }

        private mutating func parseCodeSpan() -> String? {
            guard text[index] == "`" else { return nil }
            let contentStart = text.index(after: index)
            guard let end = text[contentStart...].firstIndex(of: "`") else { return nil }

            let content = String(text[contentStart..<end])
            index = text.index(after: end)
            return "<code>\(escapeHTML(content))</code>"
        }

        private mutating func parseImage() -> String? {
            guard text[index] == "!", text.index(after: index) < text.endIndex, text[text.index(after: index)] == "[" else {
                return nil
            }

            let originalIndex = index
            let altStart = text.index(index, offsetBy: 2)
            guard let altEnd = text[altStart...].firstIndex(of: "]") else { return nil }
            let afterAlt = text.index(after: altEnd)
            guard afterAlt < text.endIndex, text[afterAlt] == "(" else { return nil }
            guard let destinationEnd = text[text.index(after: afterAlt)...].firstIndex(of: ")") else { return nil }

            let alt = String(text[altStart..<altEnd])
            let rawDestination = String(text[text.index(after: afterAlt)..<destinationEnd])
            index = text.index(after: destinationEnd)

            guard let source = imageSource(for: rawDestination) else {
                index = originalIndex
                return nil
            }

            return "<img src=\"\(escapeAttribute(source))\" alt=\"\(escapeAttribute(alt))\">"
        }

        private mutating func parseLink() -> String? {
            guard text[index] == "[" else { return nil }

            let labelStart = text.index(after: index)
            guard let labelEnd = text[labelStart...].firstIndex(of: "]") else { return nil }
            let afterLabel = text.index(after: labelEnd)
            guard afterLabel < text.endIndex, text[afterLabel] == "(" else { return nil }
            guard let destinationEnd = text[text.index(after: afterLabel)...].firstIndex(of: ")") else { return nil }

            let label = String(text[labelStart..<labelEnd])
            let destination = String(text[text.index(after: afterLabel)..<destinationEnd])
            index = text.index(after: destinationEnd)

            let href = safeHref(destination)
            var nested = InlineScanner(text: label, baseURL: baseURL)
            return "<a href=\"\(escapeAttribute(href))\">\(nested.render(until: nil))</a>"
        }

        private mutating func parseDelimited(_ delimiter: String, tag: String) -> String? {
            guard hasPrefix(delimiter, at: index) else { return nil }

            let contentStart = text.index(index, offsetBy: delimiter.count)
            guard let end = rangeOf(delimiter, from: contentStart) else { return nil }

            let content = String(text[contentStart..<end])
            index = text.index(end, offsetBy: delimiter.count)

            var nested = InlineScanner(text: content, baseURL: baseURL)
            return "<\(tag)>\(nested.render(until: nil))</\(tag)>"
        }

        private func hasPrefix(_ prefix: String, at candidate: String.Index) -> Bool {
            guard let end = text.index(candidate, offsetBy: prefix.count, limitedBy: text.endIndex) else { return false }
            return text[candidate..<end] == prefix
        }

        private func rangeOf(_ needle: String, from start: String.Index) -> String.Index? {
            text[start...].range(of: needle)?.lowerBound
        }

        private func safeHref(_ raw: String) -> String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = trimmed.lowercased()
            if lowercased.hasPrefix("javascript:") || lowercased.hasPrefix("data:") {
                return "#"
            }
            return trimmed
        }

        private func imageSource(for raw: String) -> String? {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let remote = URL(string: trimmed), remote.scheme != nil {
                let scheme = remote.scheme?.lowercased()
                return (scheme == "http" || scheme == "https") ? trimmed : nil
            }

            guard let baseURL else { return trimmed }

            let fileURL = URL(fileURLWithPath: trimmed, relativeTo: baseURL).standardizedFileURL
            guard let data = try? Data(contentsOf: fileURL), data.count <= 6_000_000 else {
                return trimmed
            }

            return "data:\(mimeType(for: fileURL));base64,\(data.base64EncodedString())"
        }

        private func mimeType(for url: URL) -> String {
            switch url.pathExtension.lowercased() {
            case "jpg", "jpeg": return "image/jpeg"
            case "gif": return "image/gif"
            case "svg": return "image/svg+xml"
            case "webp": return "image/webp"
            default: return "image/png"
            }
        }
    }
}

private func escapeHTML(_ value: String) -> String {
    var escaped = ""
    escaped.reserveCapacity(value.count)

    for character in value {
        switch character {
        case "&": escaped += "&amp;"
        case "<": escaped += "&lt;"
        case ">": escaped += "&gt;"
        case "\"": escaped += "&quot;"
        case "'": escaped += "&#39;"
        default: escaped.append(character)
        }
    }

    return escaped
}

private func escapeAttribute(_ value: String) -> String {
    escapeHTML(value).replacingOccurrences(of: "\n", with: " ")
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }

    func trimmingTrailingHashes() -> String {
        var result = trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasSuffix("#") {
            result.removeLast()
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func trimmingMatchingQuotes() -> String {
        guard count >= 2 else { return self }
        if (hasPrefix("\"") && hasSuffix("\"")) || (hasPrefix("'") && hasSuffix("'")) {
            return String(dropFirst().dropLast())
        }
        return self
    }
}
