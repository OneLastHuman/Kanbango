import AppKit
import SwiftUI
import GhosttyKit
import GhosttyRuntime

// Create the Kanbango app instance (shared across the app)
var ghosttyApp: GhosttyApp!

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    private var fontSizeMonitor: Any?
    private var appearanceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ghostty_init must be called before creating Ghostty.App
        let initResult = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        if initResult != GHOSTTY_SUCCESS {
            fputs("ghostty_init failed\n", stderr)
            exit(1)
        }
        ghostty_cli_try_action()

        ghosttyApp = GhosttyApp()
        ThemeConfigManager.ensureThemeFilesExist()

        // Observe macOS system appearance changes (light/dark mode)
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleSystemAppearanceChange()
            }
        }

        // Register local keyboard event monitor for font size shortcuts.
        fontSizeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command) else { return event }
            switch event.charactersIgnoringModifiers {
            case "+", "=":
                FontSizeManager.shared.increase()
            case "-":
                FontSizeManager.shared.decrease()
            case "0":
                FontSizeManager.shared.reset()
            default:
                return event
            }
            return nil  // Consume the event so GhosttySurfaceView doesn't also handle it
        }

        let contentView = ContentView()
            .environmentObject(ghosttyApp)
            .environmentObject(FontSizeManager.shared)

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1350, height: 900)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1350, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Kanbango"
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.window = window
        setupMenuBar()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @MainActor
    private func setupMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Kanbango", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())

        // Theme submenu
        let themeMenuItem = NSMenuItem()
        themeMenuItem.title = "Theme"
        let themeSubmenu = NSMenu(title: "Theme")
        themeSubmenu.addItem(withTitle: "Day", action: #selector(setLightTheme(_:)), keyEquivalent: "")
        themeSubmenu.addItem(withTitle: "Night", action: #selector(setDarkTheme(_:)), keyEquivalent: "")
        themeMenuItem.submenu = themeSubmenu
        appMenu.addItem(themeMenuItem)

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Kanbango", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Project menu
        let projectMenuItem = NSMenuItem()
        mainMenu.addItem(projectMenuItem)
        let projectMenu = NSMenu(title: "Project")
        projectMenuItem.submenu = projectMenu
        projectMenu.addItem(withTitle: "Open Workspace...",
                            action: #selector(openWorkspace(_:)),
                            keyEquivalent: "o")

        // Edit menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @MainActor
    @objc private func openWorkspace(_ sender: Any?) {
        BoardState.shared.selectWorkspace()
    }

    @MainActor
    @objc private func setLightTheme(_ sender: Any?) {
        BoardState.shared.setTheme(dark: false)
    }

    @MainActor
    @objc private func setDarkTheme(_ sender: Any?) {
        BoardState.shared.setTheme(dark: true)
    }

    @MainActor
    private func handleSystemAppearanceChange() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        BoardState.shared.setTheme(dark: isDark)
    }
}
