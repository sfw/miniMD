import AppKit
import QuickLookUI
import UniformTypeIdentifiers
import WebKit

@MainActor
final class MainWindowController: NSWindowController, WKNavigationDelegate, NSMenuItemValidation, NSTextViewDelegate {
    private let titleLabel = NSTextField(labelWithString: "miniMD")
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let openButton = NSButton()
    private let saveButton = NSButton()
    private let exportButton = NSButton()
    private let modeControl = NSSegmentedControl(labels: ["Preview", "Edit"], trackingMode: .selectOne, target: nil, action: nil)
    private let formattingBar = NSVisualEffectView()
    private let contentContainer = NSView()
    private let editorScrollView = NSScrollView()
    private let editorTextView = NSTextView()
    private let previewView = QLPreviewView(frame: .zero, style: .normal)!
    private let fallbackTextView = NSTextView()
    private let printWebView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())

    private var currentFileURL: URL?
    private var currentMarkdown: String?
    private var lastRenderedHTML: String = ""
    private var isEditingMarkdown = false
    private var isDirty = false
    private var isUpdatingEditor = false
    private var pendingPDFOutputURL: URL?
    private var pendingPDFLayout: PDFLayout = .paginated
    private var pdfExportWindow: NSWindow?
    private var previewScratchURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("MarkdownQuickLook-live-preview.md")
    private var editorWidthConstraint: NSLayoutConstraint?
    private var previewLeadingToContainerConstraint: NSLayoutConstraint?
    private var previewLeadingToEditorConstraint: NSLayoutConstraint?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "miniMD"
        window.minSize = NSSize(width: 640, height: 460)
        window.isReleasedWhenClosed = false
        self.init(window: window)
        configureWindow()
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        load(rendered: MarkdownRenderer.emptyDocument(), baseURL: nil, sourceURL: nil)
    }

    @discardableResult
    func openMarkdownFile(at url: URL) -> Bool {
        do {
            currentMarkdown = try MarkdownRenderer.markdownSource(at: url)
            let rendered = try MarkdownRenderer.renderFile(at: url)
            load(rendered: rendered, baseURL: url.deletingLastPathComponent(), sourceURL: url)
            NotificationCenter.default.post(name: .miniMDDidOpenMarkdownFile, object: self, userInfo: ["url": url])
            return true
        } catch {
            presentError(error)
            return false
        }
    }

    private func configureWindow() {
        guard let window else { return }

        let rootView = DropView()
        rootView.onFileURLsDropped = { [weak self] urls in
            self?.openFirstMarkdownURL(from: urls)
        }
        rootView.translatesAutoresizingMaskIntoConstraints = false

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let toolbar = makeToolbar()
        configureFormattingBar()
        configurePreview()

        stackView.addArrangedSubview(toolbar)
        stackView.addArrangedSubview(formattingBar)
        stackView.addArrangedSubview(contentContainer)
        rootView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: rootView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 54),
            formattingBar.heightAnchor.constraint(equalToConstant: 44),
            contentContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 360)
        ])

        window.contentView = rootView
        updateMode(animated: false)
    }

    private func configurePreview() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        editorScrollView.borderType = .noBorder
        editorScrollView.hasVerticalScroller = true
        editorScrollView.autohidesScrollers = true
        editorScrollView.drawsBackground = true
        editorScrollView.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.06, green: 0.07, blue: 0.08, alpha: 1)
                : NSColor(red: 0.98, green: 0.98, blue: 0.97, alpha: 1)
        }

        editorTextView.delegate = self
        editorTextView.isAutomaticQuoteSubstitutionEnabled = false
        editorTextView.isAutomaticDashSubstitutionEnabled = false
        editorTextView.isAutomaticTextReplacementEnabled = false
        editorTextView.isRichText = false
        editorTextView.importsGraphics = false
        editorTextView.allowsUndo = true
        editorTextView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        editorTextView.textColor = .labelColor
        editorTextView.backgroundColor = editorScrollView.backgroundColor
        editorTextView.insertionPointColor = .controlAccentColor
        editorTextView.textContainerInset = NSSize(width: 18, height: 18)
        editorTextView.isHorizontallyResizable = false
        editorTextView.isVerticallyResizable = true
        editorTextView.autoresizingMask = [.width]
        editorTextView.frame = NSRect(x: 0, y: 0, width: 480, height: 1200)
        editorTextView.minSize = NSSize(width: 0, height: 0)
        editorTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editorTextView.textContainer?.widthTracksTextView = true
        editorTextView.textContainer?.heightTracksTextView = false
        editorTextView.textContainer?.containerSize = NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude)
        editorScrollView.documentView = editorTextView

        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.autostarts = true
        previewView.shouldCloseWithWindow = false

        contentContainer.addSubview(editorScrollView)
        contentContainer.addSubview(previewView)
        configurePDFExportView()

        editorScrollView.translatesAutoresizingMaskIntoConstraints = false
        editorWidthConstraint = editorScrollView.widthAnchor.constraint(equalTo: contentContainer.widthAnchor, multiplier: 0.5)
        previewLeadingToContainerConstraint = previewView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor)
        previewLeadingToEditorConstraint = previewView.leadingAnchor.constraint(equalTo: editorScrollView.trailingAnchor)

        NSLayoutConstraint.activate([
            editorScrollView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            editorScrollView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            editorScrollView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            previewView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            previewView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
    }

    private func configurePDFExportView() {
        let pageSize = NSSize(width: 612, height: 792)
        printWebView.navigationDelegate = self
        printWebView.frame = NSRect(origin: .zero, size: pageSize)

        let exportWindow = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: pageSize.width, height: pageSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        exportWindow.isReleasedWhenClosed = false
        exportWindow.contentView = printWebView
        exportWindow.orderBack(nil)
        pdfExportWindow = exportWindow
    }

    private func makeToolbar() -> NSView {
        let toolbar = NSVisualEffectView()
        toolbar.material = .headerView
        toolbar.blendingMode = .withinWindow
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureToolbarButton(openButton, symbolName: "folder", tooltip: "Open Markdown", action: #selector(openDocument(_:)))
        configureToolbarButton(saveButton, symbolName: "square.and.arrow.down.on.square", tooltip: "Save Markdown", action: #selector(saveDocument(_:)))
        configureToolbarButton(exportButton, symbolName: "square.and.arrow.down", tooltip: "Export PDF", action: #selector(exportPDF(_:)))
        saveButton.isEnabled = false
        exportButton.isEnabled = false
        modeControl.selectedSegment = 0
        modeControl.target = self
        modeControl.action = #selector(changeMode(_:))
        modeControl.setWidth(76, forSegment: 0)
        modeControl.setWidth(58, forSegment: 1)
        modeControl.toolTip = "Switch between preview and editing"

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let labels = NSStackView(views: [titleLabel, statusLabel])
        labels.orientation = .vertical
        labels.spacing = 1

        stack.addArrangedSubview(labels)
        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(modeControl)
        stack.addArrangedSubview(openButton)
        stack.addArrangedSubview(saveButton)
        stack.addArrangedSubview(exportButton)
        toolbar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: toolbar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
            modeControl.heightAnchor.constraint(equalToConstant: 30),
            openButton.widthAnchor.constraint(equalToConstant: 34),
            openButton.heightAnchor.constraint(equalToConstant: 30),
            saveButton.widthAnchor.constraint(equalToConstant: 34),
            saveButton.heightAnchor.constraint(equalToConstant: 30),
            exportButton.widthAnchor.constraint(equalToConstant: 34),
            exportButton.heightAnchor.constraint(equalToConstant: 30)
        ])

        return toolbar
    }

    private func configureToolbarButton(_ button: NSButton, symbolName: String, tooltip: String, action: Selector) {
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureFormattingBar() {
        formattingBar.material = .headerView
        formattingBar.blendingMode = .withinWindow
        formattingBar.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        [
            makeFormatButton(title: "H1", tooltip: "Heading", action: #selector(formatHeading1(_:))),
            makeFormatButton(title: "H2", tooltip: "Subheading", action: #selector(formatHeading2(_:))),
            makeFormatButton(symbolName: "bold", tooltip: "Bold", action: #selector(formatBold(_:))),
            makeFormatButton(symbolName: "italic", tooltip: "Italic", action: #selector(formatItalic(_:))),
            makeFormatButton(symbolName: "link", tooltip: "Link", action: #selector(formatLink(_:))),
            makeFormatButton(symbolName: "list.bullet", tooltip: "Bulleted List", action: #selector(formatBulletedList(_:))),
            makeFormatButton(symbolName: "checklist", tooltip: "Checklist", action: #selector(formatChecklist(_:))),
            makeFormatButton(symbolName: "text.quote", tooltip: "Quote", action: #selector(formatQuote(_:))),
            makeFormatButton(symbolName: "curlybraces.square", tooltip: "Code Block", action: #selector(formatCodeBlock(_:))),
            makeFormatButton(symbolName: "tablecells", tooltip: "Table", action: #selector(formatTable(_:)))
        ].forEach { stack.addArrangedSubview($0) }

        let hint = NSTextField(labelWithString: "Live preview updates as you type")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(hint)
        formattingBar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: formattingBar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: formattingBar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: formattingBar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: formattingBar.bottomAnchor)
        ])
    }

    private func makeFormatButton(title: String? = nil, symbolName: String? = nil, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false

        if let symbolName {
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)
            button.imagePosition = .imageOnly
        } else if let title {
            button.title = title
            button.font = .systemFont(ofSize: 12, weight: .semibold)
        }

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])
        return button
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.markdownTypes()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if let window, window.isVisible {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                self?.openMarkdownFile(at: url)
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
            openMarkdownFile(at: url)
        }
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let window, let currentFileURL else {
            NSSound.beep()
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = currentFileURL.deletingPathExtension().lastPathComponent + ".pdf"
        let layoutPopup = makePDFLayoutPopup()
        panel.accessoryView = makePDFExportAccessory(layoutPopup: layoutPopup)

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let outputURL = panel.url else { return }
            let layout = PDFLayout(rawValue: layoutPopup.selectedItem?.representedObject as? String ?? "") ?? .paginated
            UserDefaults.standard.set(layout.rawValue, forKey: Self.pdfLayoutDefaultsKey)
            self?.writePDF(to: outputURL, layout: layout)
        }
    }

    @objc private func changeMode(_ sender: NSSegmentedControl) {
        isEditingMarkdown = sender.selectedSegment == 1
        updateMode(animated: true)
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let currentFileURL else {
            saveDocumentAs(sender)
            return
        }

        writeMarkdown(to: currentFileURL, updateCurrentURL: false)
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        guard let window else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = Self.markdownTypes()
        panel.nameFieldStringValue = currentFileURL?.lastPathComponent ?? "Untitled.md"

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let outputURL = panel.url else { return }
            self?.writeMarkdown(to: outputURL, updateCurrentURL: true)
        }
    }

    private func load(rendered: RenderedMarkdown, baseURL: URL?, sourceURL: URL?) {
        currentFileURL = sourceURL
        lastRenderedHTML = rendered.html
        titleLabel.stringValue = rendered.title
        statusLabel.stringValue = sourceURL?.path ?? "Ready"
        isDirty = false
        if let currentMarkdown {
            isUpdatingEditor = true
            editorTextView.string = currentMarkdown
            isUpdatingEditor = false
            editorTextView.undoManager?.removeAllActions()
        }
        updateDocumentControls()
        refreshPreview(markdown: currentMarkdown, sourceURL: sourceURL)
    }

    private func writeMarkdown(to outputURL: URL, updateCurrentURL: Bool) {
        guard let currentMarkdown else {
            NSSound.beep()
            return
        }

        do {
            try currentMarkdown.data(using: .utf8)?.write(to: outputURL, options: [.atomic])
            isDirty = false
            statusLabel.stringValue = "Saved \(outputURL.lastPathComponent)"

            if updateCurrentURL {
                currentFileURL = outputURL
                titleLabel.stringValue = outputURL.deletingPathExtension().lastPathComponent
                statusLabel.stringValue = outputURL.path
                renderCurrentMarkdown(baseURL: outputURL.deletingLastPathComponent(), title: titleLabel.stringValue)
            }
            updateDocumentControls()
        } catch {
            presentError(error)
        }
    }

    private func updateMode(animated: Bool) {
        modeControl.selectedSegment = isEditingMarkdown ? 1 : 0
        formattingBar.isHidden = !isEditingMarkdown
        editorScrollView.isHidden = !isEditingMarkdown

        if isEditingMarkdown {
            editorTextView.window?.makeFirstResponder(editorTextView)
        } else {
            window?.makeFirstResponder(previewView)
        }

        layoutContentMode()
        updateDocumentControls()
    }

    private func layoutContentMode() {
        if isEditingMarkdown {
            editorScrollView.isHidden = false
            previewLeadingToContainerConstraint?.isActive = false
            editorWidthConstraint?.isActive = true
            previewLeadingToEditorConstraint?.isActive = true
            contentContainer.layoutSubtreeIfNeeded()
            editorTextView.frame.size.width = max(320, editorScrollView.bounds.width)
            editorTextView.textContainer?.containerSize = NSSize(
                width: editorTextView.frame.width,
                height: CGFloat.greatestFiniteMagnitude
            )
        } else {
            previewLeadingToEditorConstraint?.isActive = false
            editorWidthConstraint?.isActive = false
            editorScrollView.isHidden = true
            previewLeadingToContainerConstraint?.isActive = true
        }
    }

    private func updateDocumentControls() {
        let hasMarkdown = currentMarkdown != nil
        let displayPath = currentFileURL?.path ?? "Ready"
        let dirtyMark = isDirty ? " - Edited" : ""
        statusLabel.stringValue = hasMarkdown ? displayPath + dirtyMark : displayPath
        saveButton.isEnabled = hasMarkdown && isDirty
        exportButton.isEnabled = hasMarkdown
        window?.title = isDirty ? "miniMD - Edited" : "miniMD"
    }

    private func renderCurrentMarkdown(baseURL: URL? = nil, title: String? = nil) {
        guard let currentMarkdown else { return }
        let rendered = MarkdownRenderer.render(
            markdown: currentMarkdown,
            title: title ?? currentFileURL?.deletingPathExtension().lastPathComponent ?? "Untitled",
            baseURL: baseURL ?? currentFileURL?.deletingLastPathComponent()
        )
        lastRenderedHTML = rendered.html
        titleLabel.stringValue = rendered.title
        refreshPreview(markdown: currentMarkdown, sourceURL: currentFileURL)
    }

    private func refreshPreview(markdown: String?, sourceURL: URL?) {
        if let sourceURL, !isDirty {
            previewView.previewItem = sourceURL as NSURL
            previewView.refreshPreviewItem()
            return
        }

        guard let markdown else {
            previewView.previewItem = nil
            return
        }

        do {
            try markdown.data(using: .utf8)?.write(to: previewScratchURL, options: [.atomic])
            previewView.previewItem = previewScratchURL as NSURL
            previewView.refreshPreviewItem()
            fallbackTextView.string = markdown
        } catch {
            presentError(error)
        }
    }

    func textDidChange(_ notification: Notification) {
        guard !isUpdatingEditor else { return }
        currentMarkdown = editorTextView.string
        isDirty = true
        renderCurrentMarkdown()
        updateDocumentControls()
    }

    @objc func formatHeading1(_ sender: Any?) {
        applyLinePrefix("# ", replacingHeading: true)
    }

    @objc func formatHeading2(_ sender: Any?) {
        applyLinePrefix("## ", replacingHeading: true)
    }

    @objc func formatBold(_ sender: Any?) {
        wrapSelection(prefix: "**", suffix: "**", placeholder: "bold text")
    }

    @objc func formatItalic(_ sender: Any?) {
        wrapSelection(prefix: "*", suffix: "*", placeholder: "italic text")
    }

    @objc func formatLink(_ sender: Any?) {
        let selected = selectedString(defaultValue: "link text")
        replaceSelection(with: "[\(selected)](https://example.com)", selectedOffset: selected.count + 3, selectedLength: 19)
    }

    @objc func formatBulletedList(_ sender: Any?) {
        applyLinePrefix("- ", replacingHeading: false)
    }

    @objc func formatChecklist(_ sender: Any?) {
        applyLinePrefix("- [ ] ", replacingHeading: false)
    }

    @objc func formatQuote(_ sender: Any?) {
        applyLinePrefix("> ", replacingHeading: false)
    }

    @objc func formatCodeBlock(_ sender: Any?) {
        let selected = selectedString(defaultValue: "code")
        replaceSelection(with: "```\n\(selected)\n```", selectedOffset: 4, selectedLength: selected.count)
    }

    @objc func formatTable(_ sender: Any?) {
        let table = """
        | Column | Notes |
        | :-- | :-- |
        | Item | Details |
        """
        replaceSelection(with: table, selectedOffset: 0, selectedLength: table.count)
    }

    private func selectedString(defaultValue: String) -> String {
        let range = editorTextView.selectedRange()
        guard range.length > 0, let swiftRange = Range(range, in: editorTextView.string) else {
            return defaultValue
        }
        return String(editorTextView.string[swiftRange])
    }

    private func wrapSelection(prefix: String, suffix: String, placeholder: String) {
        let range = editorTextView.selectedRange()
        let selected = selectedString(defaultValue: placeholder)
        replaceSelection(with: prefix + selected + suffix, selectedOffset: prefix.count, selectedLength: selected.count)
        if range.length > 0 {
            editorTextView.setSelectedRange(NSRange(location: range.location, length: prefix.count + selected.count + suffix.count))
        }
    }

    private func applyLinePrefix(_ prefix: String, replacingHeading: Bool) {
        let nsString = editorTextView.string as NSString
        let selectedRange = editorTextView.selectedRange()
        let lineRange = nsString.lineRange(for: selectedRange)
        let selectedLines = nsString.substring(with: lineRange)
        let hasTrailingNewline = selectedLines.hasSuffix("\n")
        let rawLines = selectedLines.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let lines = rawLines.enumerated().map { index, line in
            if index == rawLines.count - 1 && line.isEmpty && hasTrailingNewline {
                return line
            }

            var body = line
            if replacingHeading {
                body = body.replacingOccurrences(
                    of: #"^\s{0,3}#{1,6}\s+"#,
                    with: "",
                    options: .regularExpression
                )
            }
            return body.isEmpty ? prefix.trimmingCharacters(in: .whitespaces) : prefix + body
        }

        replace(range: lineRange, with: lines.joined(separator: "\n"), selectedRange: NSRange(location: lineRange.location, length: lines.joined(separator: "\n").count))
    }

    private func replaceSelection(with text: String, selectedOffset: Int, selectedLength: Int) {
        let range = editorTextView.selectedRange()
        replace(range: range, with: text, selectedRange: NSRange(location: range.location + selectedOffset, length: selectedLength))
    }

    private func replace(range: NSRange, with text: String, selectedRange: NSRange) {
        guard editorTextView.shouldChangeText(in: range, replacementString: text) else { return }
        editorTextView.textStorage?.replaceCharacters(in: range, with: text)
        editorTextView.didChangeText()
        editorTextView.setSelectedRange(selectedRange)
        editorTextView.window?.makeFirstResponder(editorTextView)
    }

    private func makePDFLayoutPopup() -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.addItem(withTitle: "Paginated")
        popup.lastItem?.representedObject = PDFLayout.paginated.rawValue
        popup.addItem(withTitle: "Continuous")
        popup.lastItem?.representedObject = PDFLayout.continuous.rawValue

        let savedLayout = PDFLayout(rawValue: UserDefaults.standard.string(forKey: Self.pdfLayoutDefaultsKey) ?? "") ?? .paginated
        popup.selectItem(withTitle: savedLayout.title)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(equalToConstant: 170).isActive = true
        return popup
    }

    private func makePDFExportAccessory(layoutPopup: NSPopUpButton) -> NSView {
        let label = NSTextField(labelWithString: "Layout:")
        label.alignment = .right

        let stack = NSStackView(views: [label, layoutPopup])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        return stack
    }

    private func writePDF(to outputURL: URL, layout: PDFLayout) {
        guard !lastRenderedHTML.isEmpty else {
            NSSound.beep()
            return
        }

        statusLabel.stringValue = "Exporting \(outputURL.lastPathComponent)"

        pendingPDFOutputURL = outputURL
        pendingPDFLayout = layout
        printWebView.loadHTMLString(lastRenderedHTML, baseURL: currentFileURL?.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === printWebView else { return }

        DispatchQueue.main.async { [weak self] in
            self?.finishPDFExport()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === printWebView else { return }
        cancelPDFExport(with: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === printWebView else { return }
        cancelPDFExport(with: error)
    }

    private func finishPDFExport() {
        guard let outputURL = pendingPDFOutputURL else {
            return
        }

        let script = Self.pdfMetricsScript(for: pendingPDFLayout)

        printWebView.evaluateJavaScript(script) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.cancelPDFExport(with: error)
                    return
                }

                let measuredSize = self.pdfDocumentSize(from: result)
                self.createPDF(at: outputURL, documentSize: measuredSize, layout: self.pendingPDFLayout)
            }
        }
    }

    private static func pdfMetricsScript(for layout: PDFLayout) -> String {
        switch layout {
        case .paginated:
            return paginatedPDFPreparationScript
        case .continuous:
            return pdfMeasurementScript
        }
    }

    private static let pdfMeasurementScript = """
    (() => {
      document.documentElement.classList.add('mini-md-pdf-export');
      document.body.classList.add('mini-md-pdf-export');

      const dimensions = () => {
        const body = document.body;
        const html = document.documentElement;
        return {
          width: Math.ceil(Math.max(body.scrollWidth, body.offsetWidth, html.clientWidth, html.scrollWidth, html.offsetWidth)),
          height: Math.ceil(Math.max(body.scrollHeight, body.offsetHeight, html.clientHeight, html.scrollHeight, html.offsetHeight))
        };
      };

      return JSON.stringify(dimensions());
    })();
    """

    private static let paginatedPDFPreparationScript = """
    (() => {
      document.documentElement.classList.add('mini-md-pdf-export');
      document.body.classList.add('mini-md-pdf-export');

      const pageWidth = 612;
      const pageHeight = 792;
      const horizontalPageMargin = 18;
      const verticalPageMargin = 18;
      const contentHeight = pageHeight - verticalPageMargin * 2;
      const dimensions = () => {
        const body = document.body;
        const html = document.documentElement;
        return {
          width: Math.ceil(Math.max(body.scrollWidth, body.offsetWidth, html.clientWidth, html.scrollWidth, html.offsetWidth)),
          height: Math.ceil(Math.max(body.scrollHeight, body.offsetHeight, html.clientHeight, html.scrollHeight, html.offsetHeight))
        };
      };
      const nextContentSibling = (element) => {
        let sibling = element.nextElementSibling;
        while (sibling && sibling.matches('[data-mini-md-pdf-spacer="true"]')) {
          sibling = sibling.nextElementSibling;
        }
        return sibling;
      };
      const textOf = (element) => (element.textContent || '').trim();
      const isCandidateHeading = (element) => /^\\d+\\.\\s+/.test(textOf(element));
      const startsWith = (element, prefix) => textOf(element).startsWith(prefix);
      const insertSpacer = (element, spacerHeight) => {
        if (element.tagName === 'TR') {
          const table = element.closest('table');
          const columnCount = table?.rows[0]?.cells.length || element.cells.length || 1;
          const row = document.createElement('tr');
          const cell = document.createElement('td');
          row.className = 'pdf-page-spacer';
          row.dataset.miniMdPdfSpacer = 'true';
          row.style.height = `${spacerHeight}px`;
          cell.colSpan = columnCount;
          cell.style.height = `${spacerHeight}px`;
          cell.style.padding = '0';
          cell.style.border = '0';
          cell.style.background = 'transparent';
          cell.style.lineHeight = '0';
          row.appendChild(cell);
          element.parentNode.insertBefore(row, element);
          return;
        }

        const spacer = document.createElement('div');
        spacer.className = 'pdf-page-spacer';
        spacer.dataset.miniMdPdfSpacer = 'true';
        spacer.style.height = `${spacerHeight}px`;
        spacer.style.margin = '0';
        spacer.style.padding = '0';
        spacer.style.border = '0';
        spacer.style.display = 'block';
        element.parentNode.insertBefore(spacer, element);
      };
      const maybeInsertPageSpacer = (element, bottom) => {
        const rect = element.getBoundingClientRect();
        if (rect.height <= 0) { return; }

        const top = rect.top + window.scrollY;
        const blockHeight = bottom - top;
        if (blockHeight >= sliceHeight * 0.82) { return; }

        const pageStart = Math.floor(top / sliceHeight) * sliceHeight;
        const pageEnd = pageStart + sliceHeight;
        if (top <= pageStart + topGuard) { return; }
        if (bottom <= pageEnd - bottomGuard) { return; }

        const spacerHeight = Math.ceil(pageEnd - top);
        if (spacerHeight <= 4) { return; }

        insertSpacer(element, spacerHeight);
      };
      const includeSiblingPreview = (element, bottom, maxPreviewHeight) => {
        let sibling = nextContentSibling(element);
        let previewBottom = bottom;
        const limit = bottom + maxPreviewHeight;
        while (sibling) {
          const siblingRect = sibling.getBoundingClientRect();
          if (siblingRect.height > 0) {
            const siblingTop = siblingRect.top + window.scrollY;
            previewBottom = Math.max(previewBottom, siblingTop + siblingRect.height);
            if (previewBottom >= limit) { break; }
          }
          sibling = nextContentSibling(sibling);
        }
        return Math.min(previewBottom, limit);
      };

      document.querySelectorAll('[data-mini-md-pdf-spacer="true"]').forEach((spacer) => spacer.remove());

      const firstDimensions = dimensions();
      const scale = Math.min(0.85, (pageWidth - horizontalPageMargin * 2) / Math.max(pageWidth, firstDimensions.width));
      const sliceHeight = contentHeight / scale;
      const bottomGuard = 18 / scale;
      const topGuard = 28 / scale;
      const selector = 'h1,h2,h3,h4,h5,h6,p,blockquote,ul,ol,table,pre,details,img,hr';
      const candidates = Array.from(document.querySelectorAll(selector));

      for (const element of candidates) {
        if (!element.isConnected) { continue; }
        if (element.closest('[data-mini-md-pdf-spacer="true"]')) { continue; }

        const rect = element.getBoundingClientRect();
        if (rect.height <= 0) { continue; }

        const top = rect.top + window.scrollY;
        let bottom = top + rect.height;
        if (/^H[1-6]$/.test(element.tagName)) {
          const previewHeight = isCandidateHeading(element) || textOf(element).includes('Side')
            ? sliceHeight * 0.24
            : sliceHeight * 0.18;
          bottom = includeSiblingPreview(element, bottom, previewHeight);
        } else if (startsWith(element, 'Interview Angle:')) {
          const sibling = nextContentSibling(element);
          if (sibling && startsWith(sibling, 'First Contact:')) {
            const siblingRect = sibling.getBoundingClientRect();
            if (siblingRect.height > 0) {
              bottom = Math.max(bottom, siblingRect.top + window.scrollY + siblingRect.height);
            }
          }
        }

        maybeInsertPageSpacer(element, bottom);
      }

      for (const row of Array.from(document.querySelectorAll('tbody tr'))) {
        if (!row.isConnected) { continue; }
        if (row.closest('[data-mini-md-pdf-spacer="true"]')) { continue; }

        const rect = row.getBoundingClientRect();
        if (rect.height <= 0) { continue; }

        const top = rect.top + window.scrollY;
        maybeInsertPageSpacer(row, top + rect.height);
      }

      return JSON.stringify(dimensions());
    })();
    """

    private func pdfDocumentSize(from result: Any?) -> NSSize {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792

        guard let dimensions = Self.pdfDimensions(from: result) else {
            return NSSize(width: pageWidth, height: pageHeight)
        }

        let measuredWidth = Self.cgFloatValue(dimensions["width"]) ?? pageWidth
        let measuredHeight = Self.cgFloatValue(dimensions["height"]) ?? pageHeight
        return NSSize(
            width: max(pageWidth, measuredWidth),
            height: max(pageHeight, measuredHeight)
        )
    }

    private func createPDF(at outputURL: URL, documentSize: NSSize, layout: PDFLayout) {
        printWebView.setFrameSize(documentSize)
        pdfExportWindow?.setContentSize(documentSize)
        printWebView.layoutSubtreeIfNeeded()

        let configuration = WKPDFConfiguration()
        configuration.rect = NSRect(origin: .zero, size: documentSize)

        printWebView.createPDF(configuration: configuration) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.pendingPDFOutputURL = nil

                switch result {
                case .success(let data):
                    do {
                        let outputData = layout == .paginated ? try Self.paginatedPDFData(from: data) : data
                        try outputData.write(to: outputURL, options: [.atomic])
                        self.statusLabel.stringValue = "Exported \(outputURL.lastPathComponent)"
                    } catch {
                        self.cancelPDFExport(with: error)
                    }
                case .failure(let error):
                    self.cancelPDFExport(with: error)
                }
            }
        }
    }

    private func cancelPDFExport(with error: Error) {
        pendingPDFOutputURL = nil
        statusLabel.stringValue = "Export failed"
        presentError(error)
    }

    private static func cgFloatValue(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber {
            return CGFloat(truncating: number)
        }
        if let double = value as? Double {
            return CGFloat(double)
        }
        if let int = value as? Int {
            return CGFloat(int)
        }
        return nil
    }

    private static func pdfDimensions(from result: Any?) -> [String: Any]? {
        if let dimensions = result as? [String: Any] {
            return dimensions
        }

        guard
            let json = result as? String,
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return object
    }

    private static func paginatedPDFData(from data: Data) throws -> Data {
        struct SourcePage {
            let page: CGPDFPage
            let box: CGRect
            let yOffset: CGFloat
        }

        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider) else {
            throw PDFExportError.unreadableSourcePDF
        }

        var sourcePages: [SourcePage] = []
        var sourceHeight: CGFloat = 0
        var sourceWidth: CGFloat = 0

        for pageNumber in stride(from: document.numberOfPages, through: 1, by: -1) {
            guard let page = document.page(at: pageNumber) else { continue }

            let box = page.getBoxRect(.mediaBox)
            guard box.width > 0, box.height > 0 else { continue }

            sourcePages.append(SourcePage(page: page, box: box, yOffset: sourceHeight))
            sourceHeight += box.height
            sourceWidth = max(sourceWidth, box.width)
        }

        guard !sourcePages.isEmpty, sourceWidth > 0, sourceHeight > 0 else {
            throw PDFExportError.unreadableSourcePDF
        }

        let pageSize = CGSize(width: 612, height: 792)
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData), let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PDFExportError.couldNotCreatePDF
        }

        let horizontalPageMargin: CGFloat = 18
        let verticalPageMargin: CGFloat = 18
        let contentHeight = pageSize.height - verticalPageMargin * 2
        let scale = min(0.85, (pageSize.width - horizontalPageMargin * 2) / sourceWidth)
        let sourceSliceHeight = contentHeight / scale
        let pageCount = max(1, Int(ceil(sourceHeight / sourceSliceHeight)))
        for pageIndex in 0..<pageCount {
            context.beginPDFPage(nil)
            context.saveGState()

            let sourceTop = sourceHeight - CGFloat(pageIndex) * sourceSliceHeight
            let sourceBottom = max(0, sourceTop - sourceSliceHeight)
            let visibleSourceHeight = sourceTop - sourceBottom
            let visibleContentHeight = visibleSourceHeight * scale
            let xOffset = (pageSize.width - sourceWidth * scale) / 2
            let yOffset = pageSize.height - verticalPageMargin - sourceTop * scale
            let clipRect = CGRect(
                x: horizontalPageMargin,
                y: pageSize.height - verticalPageMargin - visibleContentHeight,
                width: pageSize.width - horizontalPageMargin * 2,
                height: visibleContentHeight
            )

            context.clip(to: clipRect)

            for sourcePage in sourcePages {
                let pageBottom = sourcePage.yOffset
                let pageTop = pageBottom + sourcePage.box.height
                guard sourceBottom < pageTop, sourceTop > pageBottom else { continue }

                let overlapBottom = max(sourceBottom, pageBottom)
                let overlapTop = min(sourceTop, pageTop)
                let overlapRect = CGRect(
                    x: horizontalPageMargin,
                    y: yOffset + overlapBottom * scale,
                    width: pageSize.width - horizontalPageMargin * 2,
                    height: (overlapTop - overlapBottom) * scale
                )
                let pageXOffset = xOffset + ((sourceWidth - sourcePage.box.width) * scale / 2)
                context.saveGState()
                context.clip(to: overlapRect)
                context.translateBy(x: pageXOffset, y: yOffset + sourcePage.yOffset * scale)
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: -sourcePage.box.minX, y: -sourcePage.box.minY)
                context.drawPDFPage(sourcePage.page)
                context.restoreGState()
            }

            context.restoreGState()
            context.endPDFPage()
        }

        context.closePDF()
        return output as Data
    }

    @discardableResult
    private func openFirstMarkdownURL(from urls: [URL]) -> Bool {
        guard let markdownURL = urls.first(where: { Self.isMarkdownURL($0) }) else {
            NSSound.beep()
            return false
        }
        openMarkdownFile(at: markdownURL)
        return true
    }

    private static func isMarkdownURL(_ url: URL) -> Bool {
        let markdownExtensions = ["md", "markdown", "mdown", "mkd", "mkdn"]
        return markdownExtensions.contains(url.pathExtension.lowercased())
    }

    private static func markdownTypes() -> [UTType] {
        var types: [UTType] = []
        if let markdown = UTType("net.daringfireball.markdown") {
            types.append(markdown)
        }
        types.append(contentsOf: ["md", "markdown", "mdown", "mkd", "mkdn"].compactMap { UTType(filenameExtension: $0) })
        return types
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(openDocument(_:)):
            return true
        case #selector(saveDocument(_:)), #selector(saveDocumentAs(_:)):
            return currentMarkdown != nil && (menuItem.action == #selector(saveDocumentAs(_:)) || isDirty)
        case #selector(exportPDF(_:)):
            return currentMarkdown != nil
        case #selector(formatHeading1(_:)),
            #selector(formatHeading2(_:)),
            #selector(formatBold(_:)),
            #selector(formatItalic(_:)),
            #selector(formatLink(_:)),
            #selector(formatBulletedList(_:)),
            #selector(formatChecklist(_:)),
            #selector(formatQuote(_:)),
            #selector(formatCodeBlock(_:)),
            #selector(formatTable(_:)):
            return isEditingMarkdown && currentMarkdown != nil
        default:
            return true
        }
    }

    private static let pdfLayoutDefaultsKey = "PDFExportLayout"
}

extension Notification.Name {
    static let miniMDDidOpenMarkdownFile = Notification.Name("miniMDDidOpenMarkdownFile")
}

private enum PDFLayout: String {
    case paginated
    case continuous

    var title: String {
        switch self {
        case .paginated:
            return "Paginated"
        case .continuous:
            return "Continuous"
        }
    }
}

private enum PDFExportError: LocalizedError {
    case unreadableSourcePDF
    case couldNotCreatePDF

    var errorDescription: String? {
        switch self {
        case .unreadableSourcePDF:
            return "Could not read the rendered PDF for pagination."
        case .couldNotCreatePDF:
            return "Could not create the paginated PDF."
        }
    }
}
