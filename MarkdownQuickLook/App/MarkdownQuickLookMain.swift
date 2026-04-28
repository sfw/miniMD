import AppKit

@main
enum MarkdownQuickLookMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()

        application.setActivationPolicy(.regular)
        application.delegate = appDelegate
        application.mainMenu = appDelegate.makeMainMenu()
        application.run()
    }
}
