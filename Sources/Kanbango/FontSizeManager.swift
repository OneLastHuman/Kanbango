import SwiftUI
import Combine
import GhosttyRuntime

/// Central font size manager. All UI font sizes derive from `baseFontSize`.
/// Default is 15pt to match the terminal.
final class FontSizeManager: ObservableObject {
    static let shared = FontSizeManager()

    private enum Keys {
        static let baseFontSize = "kanban-base-font-size"
    }

    /// The base font size in points. All other sizes are derived from this.
    @Published var baseFontSize: CGFloat {
        didSet {
            UserDefaults.standard.set(baseFontSize, forKey: Keys.baseFontSize)
        }
    }

    /// Callback invoked when font size changes, passing the modification type for terminal sync.
    var onTerminalFontSizeChange: ((Ghostty.App.FontSizeModification) -> Void)?

    /// Minimum allowed base font size
    let minFontSize: CGFloat = 10

    /// Maximum allowed base font size
    let maxFontSize: CGFloat = 30

    /// Increment/decrement step
    let step: CGFloat = 1

    init() {
        // Load persisted font size, default to 15
        let saved = UserDefaults.standard.double(forKey: Keys.baseFontSize)
        self.baseFontSize = saved > 0 ? CGFloat(saved) : 15
    }

    // MARK: - Scaled Sizes

    /// L1 Title: task titles, column headers, tab titles
    var titleSize: CGFloat { baseFontSize }

    /// L2 Body: task descriptions, tab names
    var bodySize: CGFloat { (baseFontSize * 0.81).rounded() }

    /// L3 Caption: tags, task counts, timestamps
    var captionSize: CGFloat { (baseFontSize * 0.69).rounded() }

    /// L4 Micro: close buttons, small icons, badges
    var microSize: CGFloat { (baseFontSize * 0.62).rounded() }

    // MARK: - Font Helpers

    func titleFont(weight: Font.Weight = .medium) -> Font {
        .system(size: titleSize, weight: weight)
    }

    func bodyFont(weight: Font.Weight = .regular) -> Font {
        .system(size: bodySize, weight: weight)
    }

    func captionFont(weight: Font.Weight = .medium) -> Font {
        .system(size: captionSize, weight: weight)
    }

    func microFont(weight: Font.Weight = .bold) -> Font {
        .system(size: microSize, weight: weight)
    }

    // MARK: - Adjust

    func increase() {
        let new = baseFontSize + step
        if new <= maxFontSize {
            baseFontSize = new
            onTerminalFontSizeChange?(.increase(1))
        }
    }

    func decrease() {
        let new = baseFontSize - step
        if new >= minFontSize {
            baseFontSize = new
            onTerminalFontSizeChange?(.decrease(1))
        }
    }

    func reset() {
        baseFontSize = 15
        onTerminalFontSizeChange?(.reset)
    }
}
