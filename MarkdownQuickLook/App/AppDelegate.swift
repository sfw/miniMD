import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let windowController = MainWindowController()
    private var openRecentMenu: NSMenu?
    private var appearanceItems: [AppearanceMode: NSMenuItem] = [:]

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        applyAppearanceMode(savedAppearanceMode())
        NSApp.mainMenu = makeMainMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(markdownFileDidOpen(_:)),
            name: .miniMDDidOpenMarkdownFile,
            object: nil
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showViewer()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openFirstMarkdownURL(urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openFirstMarkdownURL([URL(fileURLWithPath: filename)])
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let didOpen = openFirstMarkdownURL(filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: didOpen ? .success : .failure)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showViewer()
        }
        return true
    }

    @discardableResult
    private func openFirstMarkdownURL(_ urls: [URL]) -> Bool {
        guard let url = urls.first else { return false }
        return openMarkdownURL(url)
    }

    @discardableResult
    private func openMarkdownURL(_ url: URL) -> Bool {
        showViewer()
        return windowController.openMarkdownFile(at: url)
    }

    private func showViewer() {
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem(title: "miniMD", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "miniMD")
        appMenuItem.submenu = appMenu
        appMenu.addItem(NSMenuItem(
            title: "About miniMD",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: "Quit miniMD",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        let openItem = NSMenuItem(
            title: "Open...",
            action: #selector(MainWindowController.openDocument(_:)),
            keyEquivalent: "o"
        )
        openItem.target = windowController

        let openRecentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let openRecentMenu = NSMenu(title: "Open Recent")
        openRecentItem.submenu = openRecentMenu
        self.openRecentMenu = openRecentMenu

        let saveItem = NSMenuItem(
            title: "Save",
            action: #selector(MainWindowController.saveDocument(_:)),
            keyEquivalent: "s"
        )
        saveItem.target = windowController

        let saveAsItem = NSMenuItem(
            title: "Save As...",
            action: #selector(MainWindowController.saveDocumentAs(_:)),
            keyEquivalent: "S"
        )
        saveAsItem.target = windowController

        let exportItem = NSMenuItem(
            title: "Export PDF...",
            action: #selector(MainWindowController.exportPDF(_:)),
            keyEquivalent: "e"
        )
        exportItem.target = windowController

        fileMenu.addItem(openItem)
        fileMenu.addItem(openRecentItem)
        fileMenu.addItem(.separator())
        fileMenu.addItem(saveItem)
        fileMenu.addItem(saveAsItem)
        fileMenu.addItem(.separator())
        fileMenu.addItem(exportItem)

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let insertMenuItem = NSMenuItem(title: "Insert", action: nil, keyEquivalent: "")
        let insertMenu = NSMenu(title: "Insert")
        insertMenuItem.submenu = insertMenu

        let headingItem = NSMenuItem(
            title: "Heading",
            action: #selector(MainWindowController.formatHeading1(_:)),
            keyEquivalent: "1"
        )
        headingItem.target = windowController
        headingItem.keyEquivalentModifierMask = [.command, .option]

        let subheadingItem = NSMenuItem(
            title: "Subheading",
            action: #selector(MainWindowController.formatHeading2(_:)),
            keyEquivalent: "2"
        )
        subheadingItem.target = windowController
        subheadingItem.keyEquivalentModifierMask = [.command, .option]

        let boldItem = NSMenuItem(
            title: "Bold",
            action: #selector(MainWindowController.formatBold(_:)),
            keyEquivalent: "b"
        )
        boldItem.target = windowController

        let italicItem = NSMenuItem(
            title: "Italic",
            action: #selector(MainWindowController.formatItalic(_:)),
            keyEquivalent: "i"
        )
        italicItem.target = windowController

        let linkItem = NSMenuItem(
            title: "Link",
            action: #selector(MainWindowController.formatLink(_:)),
            keyEquivalent: "k"
        )
        linkItem.target = windowController

        let bulletItem = NSMenuItem(
            title: "Bulleted List",
            action: #selector(MainWindowController.formatBulletedList(_:)),
            keyEquivalent: "8"
        )
        bulletItem.target = windowController
        bulletItem.keyEquivalentModifierMask = [.command, .shift]

        let checklistItem = NSMenuItem(
            title: "Checklist",
            action: #selector(MainWindowController.formatChecklist(_:)),
            keyEquivalent: "9"
        )
        checklistItem.target = windowController
        checklistItem.keyEquivalentModifierMask = [.command, .shift]

        let quoteItem = NSMenuItem(
            title: "Quote",
            action: #selector(MainWindowController.formatQuote(_:)),
            keyEquivalent: ">"
        )
        quoteItem.target = windowController
        quoteItem.keyEquivalentModifierMask = [.command]

        let codeItem = NSMenuItem(
            title: "Code Block",
            action: #selector(MainWindowController.formatCodeBlock(_:)),
            keyEquivalent: "`"
        )
        codeItem.target = windowController
        codeItem.keyEquivalentModifierMask = [.command, .option]

        let tableItem = NSMenuItem(
            title: "Table",
            action: #selector(MainWindowController.formatTable(_:)),
            keyEquivalent: "t"
        )
        tableItem.target = windowController
        tableItem.keyEquivalentModifierMask = [.command, .option]

        [headingItem, subheadingItem, boldItem, italicItem, linkItem, bulletItem, checklistItem, quoteItem, codeItem, tableItem].forEach {
            insertMenu.addItem($0)
        }

        let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu

        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu(title: "Appearance")
        appearanceItem.submenu = appearanceMenu

        AppearanceMode.allCases.forEach { mode in
            let item = NSMenuItem(title: mode.title, action: #selector(setAppearanceMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            appearanceItems[mode] = item
            appearanceMenu.addItem(item)
        }
        viewMenu.addItem(appearanceItem)

        mainMenu.addItem(appMenuItem)
        mainMenu.addItem(fileMenuItem)
        mainMenu.addItem(editMenuItem)
        mainMenu.addItem(insertMenuItem)
        mainMenu.addItem(viewMenuItem)
        updateOpenRecentMenu()
        updateAppearanceMenu()
        return mainMenu
    }

    @objc private func markdownFileDidOpen(_ notification: Notification) {
        guard let url = notification.userInfo?["url"] as? URL else { return }
        recordRecentFile(url)
    }

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        guard let recentFile = sender.representedObject as? RecentMarkdownFile else { return }

        do {
            let resolved = try recentFile.resolvedURL()
            defer {
                if resolved.didAccessSecurityScope {
                    resolved.url.stopAccessingSecurityScopedResource()
                }
            }

            if !openMarkdownURL(resolved.url) {
                removeRecentFile(path: recentFile.path)
            }
        } catch {
            removeRecentFile(path: recentFile.path)
            windowController.presentError(error)
        }
    }

    @objc private func clearRecentDocuments(_ sender: Any?) {
        UserDefaults.standard.removeObject(forKey: Self.recentFilesDefaultsKey)
        updateOpenRecentMenu()
    }

    @objc private func setAppearanceMode(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let mode = AppearanceMode(rawValue: rawValue)
        else { return }

        UserDefaults.standard.set(mode.rawValue, forKey: Self.appearanceModeDefaultsKey)
        applyAppearanceMode(mode)
        updateAppearanceMenu()
    }

    private func recordRecentFile(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        var files = recentFiles().filter { $0.path != standardizedURL.path }
        files.insert(RecentMarkdownFile(url: standardizedURL), at: 0)
        saveRecentFiles(Array(files.prefix(Self.recentFilesLimit)))
        updateOpenRecentMenu()
    }

    private func removeRecentFile(path: String) {
        saveRecentFiles(recentFiles().filter { $0.path != path })
        updateOpenRecentMenu()
    }

    private func updateOpenRecentMenu() {
        guard let openRecentMenu else { return }
        openRecentMenu.removeAllItems()

        let files = recentFiles()
        guard !files.isEmpty else {
            let emptyItem = NSMenuItem(title: "No Recent Documents", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            openRecentMenu.addItem(emptyItem)
            return
        }

        files.forEach { file in
            let item = NSMenuItem(title: file.displayName, action: #selector(openRecentDocument(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = file
            item.toolTip = file.path
            openRecentMenu.addItem(item)
        }

        openRecentMenu.addItem(.separator())
        let clearItem = NSMenuItem(title: "Clear Menu", action: #selector(clearRecentDocuments(_:)), keyEquivalent: "")
        clearItem.target = self
        openRecentMenu.addItem(clearItem)
    }

    private func recentFiles() -> [RecentMarkdownFile] {
        guard
            let data = UserDefaults.standard.data(forKey: Self.recentFilesDefaultsKey),
            let files = try? JSONDecoder().decode([RecentMarkdownFile].self, from: data)
        else {
            return []
        }

        return Array(files.prefix(Self.recentFilesLimit))
    }

    private func saveRecentFiles(_ files: [RecentMarkdownFile]) {
        guard let data = try? JSONEncoder().encode(Array(files.prefix(Self.recentFilesLimit))) else { return }
        UserDefaults.standard.set(data, forKey: Self.recentFilesDefaultsKey)
    }

    private func savedAppearanceMode() -> AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: Self.appearanceModeDefaultsKey) ?? "") ?? .automatic
    }

    private func applyAppearanceMode(_ mode: AppearanceMode) {
        switch mode {
        case .automatic:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func updateAppearanceMenu() {
        let selectedMode = savedAppearanceMode()
        appearanceItems.forEach { mode, item in
            item.state = mode == selectedMode ? .on : .off
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let rawValue = menuItem.representedObject as? String, AppearanceMode(rawValue: rawValue) != nil {
            menuItem.state = rawValue == savedAppearanceMode().rawValue ? .on : .off
        }
        return true
    }

    private static let recentFilesDefaultsKey = "RecentMarkdownFiles"
    private static let recentFilesLimit = 5
    private static let appearanceModeDefaultsKey = "AppearanceMode"
}

private struct RecentMarkdownFile: Codable {
    let path: String
    let displayName: String
    let bookmarkData: Data?

    init(url: URL) {
        path = url.path
        displayName = url.lastPathComponent
        bookmarkData = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolvedURL() throws -> (url: URL, didAccessSecurityScope: Bool) {
        guard let bookmarkData else {
            return (URL(fileURLWithPath: path), false)
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, url.startAccessingSecurityScopedResource())
    }
}

private enum AppearanceMode: String, CaseIterable {
    case automatic
    case light
    case dark

    var title: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}
