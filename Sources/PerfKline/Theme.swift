import AppKit
import SwiftUI

/// 配色：深色外观用方向 B「石墨」，浅色外观用方向 C「浅色」，数值照搬 design/方向对比.html。
enum Theme {
    static func dyn(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(nsColor: dynNS(dark, light))
    }

    static func dynNS(_ dark: UInt32, _ light: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? hex(dark) : hex(light)
        }
    }

    static func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255,
                blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }

    static let bg = dyn(0x1c1c1e, 0xf6f6f4)
    static let panel = dyn(0x1c1c1e, 0xffffff)
    static let panel2 = dyn(0x232326, 0xf6f6f4)
    static let line = dyn(0x313134, 0xe3e2de)
    static let line2 = dyn(0x262629, 0xeeede9)
    static let text = dyn(0xebe9e4, 0x1d1d1f)
    static let muted = dyn(0x8e8c87, 0x86857f)
    static let accent = dyn(0xd6a24a, 0x1d1d1f)
    static let accentInk = dyn(0x1c1c1e, 0xffffff)
    static let sel = dyn(0x2c2c30, 0xefeeea)
    static let tag = dyn(0x2a2a2d, 0xf0efeb)
    static let ma5 = dyn(0xebe9e4, 0x1d1d1f)
    static let ma10 = dyn(0xd6a24a, 0xc98a1b)
    static let ma20 = dyn(0x8f8bd6, 0x6f6ac9)
    static let red = dyn(0xe5544b, 0xd63a31)
    static let green = dyn(0x3fae74, 0x1e9659)
    static let redNS = dynNS(0xe5544b, 0xd63a31)
    static let greenNS = dynNS(0x3fae74, 0x1e9659)

    static let ui = Font.system(size: 13)
}

/// 涨跌配色。默认红涨绿跌（国内行情软件习惯），可切换为绿涨红跌。
struct Colors {
    var redUp: Bool
    var up: Color { redUp ? Theme.red : Theme.green }
    var down: Color { redUp ? Theme.green : Theme.red }
    var upNS: NSColor { redUp ? Theme.redNS : Theme.greenNS }
    var downNS: NSColor { redUp ? Theme.greenNS : Theme.redNS }

    func tone(_ v: Double) -> Color { v > 0 ? up : (v < 0 ? down : Theme.muted) }
}

extension View {
    /// 数字用等宽数字，跳动时不左右晃。
    func num(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        font(.system(size: size, weight: weight)).monospacedDigit()
    }
}
