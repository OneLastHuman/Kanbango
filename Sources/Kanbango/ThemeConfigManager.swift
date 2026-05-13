import Foundation

enum ThemeConfigManager {
    static let appSupportDir: String = {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("Kanbango")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }()

    static var darkThemePath: String {
        appSupportDir + "/theme-dark.conf"
    }

    static var lightThemePath: String {
        appSupportDir + "/theme-light.conf"
    }

    static func ensureThemeFilesExist() {
        writeIfMissing(path: darkThemePath, content: darkThemeContent)
        writeIfMissing(path: lightThemePath, content: lightThemeContent)
    }

    private static func writeIfMissing(path: String, content: String) {
        guard !FileManager.default.fileExists(atPath: path) else { return }
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // Apple System Colors (Dark)
    private static let darkThemeContent = """
    palette = 0=#1a1a1a
    palette = 1=#cc372e
    palette = 2=#26a439
    palette = 3=#cdac08
    palette = 4=#0869cb
    palette = 5=#9647bf
    palette = 6=#479ec2
    palette = 7=#98989d
    palette = 8=#464646
    palette = 9=#ff453a
    palette = 10=#32d74b
    palette = 11=#ffd60a
    palette = 12=#0a84ff
    palette = 13=#bf5af2
    palette = 14=#76d6ff
    palette = 15=#ffffff
    background = #1e1e1e
    foreground = #ffffff
    cursor-color = #98989d
    cursor-text = #ffffff
    selection-background = #3f638b
    selection-foreground = #ffffff
    """

    // Apple System Colors Light
    private static let lightThemeContent = """
    palette = 0=#1a1a1a
    palette = 1=#cc372e
    palette = 2=#26a439
    palette = 3=#cdac08
    palette = 4=#0869cb
    palette = 5=#9647bf
    palette = 6=#479ec2
    palette = 7=#98989d
    palette = 8=#464646
    palette = 9=#ff453a
    palette = 10=#32d74b
    palette = 11=#e5bc00
    palette = 12=#0a84ff
    palette = 13=#bf5af2
    palette = 14=#69c9f2
    palette = 15=#ffffff
    background = #feffff
    foreground = #000000
    cursor-color = #98989d
    cursor-text = #ffffff
    selection-background = #abd8ff
    selection-foreground = #000000
    """
}
