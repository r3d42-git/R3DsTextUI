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
    static let background = color("background", dark: 0x273449, light: 0xF7F9FC)
    static let foreground = color("foreground", dark: 0xB9C5D6, light: 0x354258)
    static let gutter = color("gutter", dark: 0x72869F, light: 0x8592A6)
    static let currentLine = color("currentLine", dark: 0x2E4058, light: 0xEDF1F8)
    static let currentNumber = color("currentNumber", dark: 0xC5D1E3, light: 0x354258)
    static let currentGutter = color("currentGutter", dark: 0x40546F, light: 0xDBE5F4)
    static let selection = color("selection", dark: 0x4A6386, light: 0xBDD8FA)
    static let cyan = color("cyan", dark: 0x22DDEC, light: 0x007D91)
    static let orange = color("orange", dark: 0xFFAE57, light: 0xA45100)
    static let green = color("green", dark: 0xB6E770, light: 0x48751B)
    static let red = color("red", dark: 0xFF5370, light: 0xB62E4C)
    static let purple = color("purple", dark: 0xCBA6F7, light: 0x8053B0)
    static let comment = color("comment", dark: 0x8C9DB6, light: 0x78859A)
    static let chrome = color("chrome", dark: 0x222E40, light: 0xE9EEF6)
    static let windowChrome = color("windowChrome", dark: 0x364154, light: 0xEEF1F6)
    static let tabTop = color("tabTop", dark: 0x435168, light: 0xE3E9F2)
    static let tabBottom = color("tabBottom", dark: 0x39465A, light: 0xD6DFEB)
    static let tabBorder = color("tabBorder", dark: 0x596A82, light: 0xB8C5D6)
    static let tabSelectedTop = color("tabSelectedTop", dark: 0x566983, light: 0xFFFFFF)
    static let tabSelectedBottom = color("tabSelectedBottom", dark: 0x46576F, light: 0xF4F7FC)
    static let tabSelectedBorder = color("tabSelectedBorder", dark: 0x8C9DB5, light: 0x95A8C0)

    static func font(size: CGFloat) -> NSFont {
        NSFont(name: "Menlo-Regular", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
