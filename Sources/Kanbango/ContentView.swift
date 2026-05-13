import SwiftUI
import AppKit
import GhosttyRuntime
import GhosttyKit

// MARK: - Main Layout

struct ContentView: View {
    @EnvironmentObject private var ghostty: GhosttyApp
    @EnvironmentObject private var fontManager: FontSizeManager
    @StateObject private var tabManager = TerminalTabManager()
    @StateObject private var boardState = BoardState.shared
    @StateObject private var sessionManager = SessionManager.shared

    // JsonlWatcher is kept alive by this @State reference
    @State private var jsonlWatcher: JsonlWatcher?

    var body: some View {
        HSplitView {
            KanbanView(
                boardState: boardState,
                sessionManager: sessionManager,
                tabManager: tabManager,
                ghosttyApp: ghostty.app!
            )
            .frame(minWidth: Status.columnMinWidth + Status.columnHPadding,
                   idealWidth: Status.columnMinWidth * 1.5 + Status.columnHPadding)
            .layoutPriority(0)

            // Right: tab bar + terminal
            VStack(spacing: 0) {
                // Tab Bar (hidden when only one tab)
                if tabManager.showTabBar {
                    TabBarView(tabManager: tabManager, sessionManager: sessionManager)
                        .environmentObject(boardState)
                }

                // Terminal area (only render active tab to save GPU)
                ZStack {
                    Color.black
                    if let activeTab = tabManager.activeTab {
                        SurfaceViewWrapper(surfaceView: activeTab.surfaceView)
                            .id(activeTab.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(minWidth: 400, idealWidth: 600)
            .layoutPriority(1)
        }
        .frame(minWidth: 900, minHeight: 500)
        .environment(\.themeColors, ThemeColors.colors(isDark: boardState.isDarkMode))
        .preferredColorScheme(boardState.isDarkMode ? .dark : .light)
        .onReceive(NotificationCenter.default.publisher(for: .themeDidChange)) { _ in
            let themePath = boardState.isDarkMode
                ? ThemeConfigManager.darkThemePath
                : ThemeConfigManager.lightThemePath
            ghostty.reloadConfigWithTheme(themePath: themePath)
            // Also set color scheme preference
            let scheme: ghostty_color_scheme_e = boardState.isDarkMode ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
            ghostty.setColorScheme(scheme)
            tabManager.setColorSchemeForAllTabs(scheme)
        }
        .onAppear {
            // Compute workspace prefix BEFORE the app block so it's available
            // to sessionManager and JsonlWatcher downstream.
            let claudeProjects = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects").path
            let workspacePrefix: String
            let watchPath: String
            if let ws = boardState.workspacePath {
                let encoded = ws.replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ".", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
                    .replacingOccurrences(of: " ", with: "-")
                workspacePrefix = encoded
                watchPath = claudeProjects  // Watch parent so we catch worktree subdirs
            } else {
                workspacePrefix = ""
                watchPath = claudeProjects
            }

            if let app = ghostty.app {
                if tabManager.tabs.isEmpty {
                    tabManager.newTab(app: app)
                }

                // Apply system appearance theme to terminal on launch
                let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                boardState.isDarkMode = isDark
                UserDefaults.standard.set(isDark, forKey: "kanban-dark-mode")
                let themePath = isDark ? ThemeConfigManager.darkThemePath : ThemeConfigManager.lightThemePath
                ghostty.reloadConfigWithTheme(themePath: themePath)
                let scheme: ghostty_color_scheme_e = isDark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
                ghostty.setColorScheme(scheme)
                tabManager.setColorSchemeForAllTabs(scheme)

                sessionManager.configure(tabManager: tabManager, app: app)
                sessionManager.workspacePrefix = workspacePrefix
                boardState.configure(sessionManager: sessionManager)

                // If workspace is set, cd the initial terminal into it
                if let ws = boardState.workspacePath, let tab = tabManager.activeTab {
                    tab.surfaceView.sendText("cd \(ws)")
                    tab.surfaceView.sendEnter()
                }
            }

            let sessionWatcher = JsonlWatcher(path: watchPath, workspacePrefix: workspacePrefix)
            sessionWatcher.start(
                onChange: { [sessionManager] parsedSessions in
                    for (_, parsed) in parsedSessions {
                        sessionManager.updateSession(from: parsed)
                    }
                },
                onNewSessionId: { [sessionManager] sessionId, parsedSession in
                    sessionManager.matchNewSessionId(sessionId, from: parsedSession)
                }
            )
            jsonlWatcher = sessionWatcher

            // Set up terminal font size sync: when Cmd+/Cmd-/Cmd+0 changes UI font size,
            // also change the terminal font size via the active surface.
            fontManager.onTerminalFontSizeChange = { [weak tabManager, weak ghostty] change in
                guard let tabManager = tabManager,
                      let ghostty = ghostty,
                      let surface = tabManager.activeTab?.surfaceView.surface else { return }
                ghostty.changeFontSize(surface: surface, change)
            }
        }
    }

}

// MARK: - Tab Bar

struct TabBarView: View {
    @EnvironmentObject private var ghostty: GhosttyApp
    @EnvironmentObject private var boardState: BoardState
    @EnvironmentObject private var fontManager: FontSizeManager
    @ObservedObject var tabManager: TerminalTabManager
    @ObservedObject var sessionManager: SessionManager

    var body: some View {
        HStack(spacing: 0) {
            // Draggable tab list — expands to fill available width
            ForEach(tabManager.tabs) { tab in
                TabButton(
                    title: tab.title,
                    isActive: tab.id == tabManager.activeTabID,
                    canClose: tabManager.tabs.count > 1,
                    bodySize: fontManager.bodySize,
                    microSize: fontManager.microSize,
                    onSelect: { tabManager.selectTab(id: tab.id) },
                    onClose: {
                        tabManager.closeTab(id: tab.id)
                        sessionManager.unlinkTab(tabID: tab.id)
                    }
                )
                .frame(maxWidth: .infinity)
                .onDrag {
                    NSItemProvider(object: tab.id.uuidString as NSString)
                }
                .onDrop(of: [.text], delegate: TabDropDelegate(
                    tab: tab,
                    tabManager: tabManager
                ))
            }

            // "+" button — always fixed at the far right
            Button(action: {
                if let app = ghostty.app {
                    tabManager.newTab(app: app, workspacePath: boardState.workspacePath)
                }
            }) {
                Image(systemName: "plus")
                    .font(fontManager.microFont(weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 20)
            }
            .buttonStyle(.plain)
            .help("New Tab")
        }
        .frame(height: 28)
        .background(Color(.controlBackgroundColor).opacity(0.8))
        .overlay(Divider(), alignment: .bottom)
    }
}

struct TabButton: NSViewRepresentable {
    let title: String
    let isActive: Bool
    let canClose: Bool
    let bodySize: CGFloat
    let microSize: CGFloat
    let onSelect: () -> Void
    let onClose: () -> Void

    func makeNSView(context: Context) -> TabButtonNS {
        let v = TabButtonNS()
        v.onSelect = onSelect
        v.onClose = onClose
        v.update(title: title, isActive: isActive, canClose: canClose, bodySize: bodySize, microSize: microSize)
        return v
    }

    func updateNSView(_ nsView: TabButtonNS, context: Context) {
        nsView.onSelect = onSelect
        nsView.onClose = onClose
        nsView.update(title: title, isActive: isActive, canClose: canClose, bodySize: bodySize, microSize: microSize)
    }
}

class TabButtonNS: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var isActive = false
    private var canClose = false
    private var bodySize: CGFloat = 13
    private var microSize: CGFloat = 10

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        titleLabel.font = NSFont.systemFont(ofSize: bodySize)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        closeButton.bezelStyle = .inline
        closeButton.title = "x"
        closeButton.font = NSFont.systemFont(ofSize: microSize, weight: .bold)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            closeButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeButton.widthAnchor.constraint(equalToConstant: 14),
            closeButton.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    func update(title: String, isActive: Bool, canClose: Bool, bodySize: CGFloat, microSize: CGFloat) {
        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: bodySize)
        closeButton.font = NSFont.systemFont(ofSize: microSize, weight: .bold)
        self.isActive = isActive
        self.canClose = canClose
        closeButton.isHidden = !canClose
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isActive {
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
            let path = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
            path.fill()
        }
        super.draw(dirtyRect)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 || event.buttonNumber == 2 {
            // Double-click or middle-click → close
            onClose?()
        } else {
            onSelect?()
        }
    }

    @objc private func closeClicked() {
        onClose?()
    }
}

struct TabDropDelegate: DropDelegate {
    let tab: TerminalTabManager.Tab
    let tabManager: TerminalTabManager

    func performDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
        guard let items = info.itemProviders(for: [.text]).first else { return }
        _ = items.loadObject(ofClass: NSString.self) { reading, _ in
            guard let uuidString = reading as? String,
                  let sourceID = UUID(uuidString: uuidString),
                  sourceID != tab.id else { return }
            DispatchQueue.main.async {
                guard let sourceIndex = tabManager.tabs.firstIndex(where: { $0.id == sourceID }),
                      let destIndex = tabManager.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
                withAnimation {
                    tabManager.tabs.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destIndex > sourceIndex ? destIndex + 1 : destIndex)
                }
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Terminal View Wrapper

/// Matches Ghostty's SurfaceWrapper (SurfaceView.swift:35-160).
/// Uses @ObservedObject for SwiftUI diffing, @FocusState for keyboard
/// routing, and window focus notifications for correct focus state.
struct SurfaceViewWrapper: View {
    @ObservedObject var surfaceView: GhosttySurfaceView

    @FocusState private var surfaceFocus: Bool
    @State private var windowFocus: Bool = true

    var body: some View {
        let center = NotificationCenter.default

        GeometryReader { geo in
            #if canImport(AppKit)
            let pubBecomeKey = center.publisher(for: NSWindow.didBecomeKeyNotification)
            let pubResign = center.publisher(for: NSWindow.didResignKeyNotification)
            #endif

            SurfaceRepresentable(surfaceView: surfaceView, size: geo.size)
                .focused($surfaceFocus)
            #if canImport(AppKit)
                .onReceive(pubBecomeKey) { notification in
                    guard let window = notification.object as? NSWindow else { return }
                    guard let surfaceWindow = surfaceView.surfaceNSView.window else { return }
                    windowFocus = surfaceWindow == window
                }
                .onReceive(pubResign) { notification in
                    guard let window = notification.object as? NSWindow else { return }
                    guard let surfaceWindow = surfaceView.surfaceNSView.window else { return }
                    if surfaceWindow == window {
                        windowFocus = false
                    }
                }
            #endif
        }
    }
}

/// Matches Ghostty's SurfaceRepresentable (SurfaceView.swift:570-609).
/// Returns GhosttySurfaceView which internally manages SurfaceScrollView.
/// Size guard compares against the correct view bounds.
private struct SurfaceRepresentable: NSViewRepresentable {
    let surfaceView: GhosttySurfaceView
    let size: CGSize

    func makeNSView(context: Context) -> GhosttySurfaceView {
        surfaceView
    }

    func updateNSView(_ nsView: GhosttySurfaceView, context: Context) {
        guard nsView.bounds.size != size else { return }
        nsView.needsLayout = true
    }
}
