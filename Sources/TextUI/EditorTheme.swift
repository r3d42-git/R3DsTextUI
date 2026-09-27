import AppKit

/// A restrained editor palette inspired by the supplied reference; no theme assets or dependencies.
enum EditorTheme {
    private static func color(_ name: String, dark: UInt32, light: UInt32) -> NSColor {
        NSColor(name: NSColor.Name("TextUI.\(name)")) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }
    static let background = color("background", dark: 0x1D293B, light: 0xF7F9FC)
    static let foreground = color("foreground", dark: 0xABB6C8, light: 0x354258)
    static let gutter = color("gutter", dark: 0x4C5F79, light: 0x8592A6)
    static let currentLine = color("currentLine", dark: 0x223147, light: 0xEDF1F8)
    static let currentNumber = color("currentNumber", dark: 0xB7C4D8, light: 0x354258)
    static let currentGutter = color("currentGutter", dark: 0x30415B, light: 0xDBE5F4)
    static let selection = color("selection", dark: 0x3C5274, light: 0xBDD8FA)
    static let cyan = color("cyan", dark: 0x22DDEC, light: 0x007D91)
    static let orange = color("orange", dark: 0xFFAE57, light: 0xA45100)
    static let green = color("green", dark: 0xB6E770, light: 0x48751B)
    static let red = color("red", dark: 0xFF5370, light: 0xB62E4C)
    static let purple = color("purple", dark: 0xCBA6F7, light: 0x8053B0)
    static let comment = color("comment", dark: 0x687C98, light: 0x78859A)
    static let chrome = color("chrome", dark: 0x172131, light: 0xE9EEF6)

    static func font(size: CGFloat) -> NSFont {
        NSFont(name: "Menlo-Regular", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
