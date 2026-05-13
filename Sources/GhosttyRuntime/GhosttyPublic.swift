// Public API facade for the GhosttyRuntime module.
// This exposes only the types needed by the Kanbango target.

import AppKit
import SwiftUI
import Combine
import GhosttyKit

// Re-export GhosttyKit so consumers get ghostty_app_t etc.
@_exported import struct GhosttyKit.ghostty_app_t

public final class GhosttyApp: ObservableObject {
    private let inner: Ghostty.App

    public init(configPath: String? = nil) {
        inner = Ghostty.App(configPath: configPath)
    }

    public var app: ghostty_app_t? { inner.app }

    public func changeFontSize(surface: ghostty_surface_t, _ change: Ghostty.App.FontSizeModification) {
        inner.changeFontSize(surface: surface, change)
    }

    public func setColorScheme(_ scheme: ghostty_color_scheme_e) {
        guard let app = inner.app else { return }
        ghostty_app_set_color_scheme(app, scheme)
    }

    public func reloadConfigWithTheme(themePath: String) {
        inner.reloadConfigWithTheme(themePath: themePath)
    }

    // Forward ObservableObject
    public let objectWillChange = ObservableObjectPublisher()
}

public final class GhosttySurfaceView: NSView, ObservableObject {
    private let inner: Ghostty.SurfaceView
    private let _scrollView: SurfaceScrollView

    @Published public private(set) var title: String = ""

    private var titleCancellable: Any?

    public init(_ app: ghostty_app_t) {
        inner = Ghostty.SurfaceView(app)
        _scrollView = SurfaceScrollView(contentSize: CGSize(width: 800, height: 600), surfaceView: inner)
        super.init(frame: .zero)
        addSubview(_scrollView)
        _scrollView.autoresizingMask = [.width, .height]
        titleCancellable = inner.$title.sink { [weak self] newTitle in
            self?.title = newTitle
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    public func sendText(_ text: String) {
        inner.surfaceModel?.sendText(text)
    }

    public func sendEnter() {
        let event = Ghostty.Input.KeyEvent(key: .enter, action: .press)
        inner.surfaceModel?.sendKeyEvent(event)
    }

    public var surface: ghostty_surface_t? {
        inner.surface
    }

    public var surfaceNSView: NSView { inner }

    public func focusDidChange(_ focused: Bool) {
        inner.focusDidChange(focused)
    }

    public func setColorScheme(_ scheme: ghostty_color_scheme_e) {
        guard let surface = inner.surface else { return }
        ghostty_surface_set_color_scheme(surface, scheme)
    }

    public override func layout() {
        super.layout()
        _scrollView.frame = bounds
    }
}
