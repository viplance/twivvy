import SwiftUI
import UIKit

/// Dark, readable ink on white and pastel surfaces. System rounded type supports
/// every app language and follows the user's Dynamic Type setting.
enum LabTheme {
    static let canvas = Color.white
    static let ink = Color(UIColor(lab: 0x263D49))
    static let secondaryInk = Color(UIColor(lab: 0x536575))
    static let teal = Color(UIColor(lab: 0x126B60))
    static let berry = Color(UIColor(lab: 0xAD3D59))
    static let amberInk = Color(UIColor(lab: 0x916000))
    static let sunshine = Color(UIColor(lab: 0xFFDA78))
    static let mint = Color(UIColor(lab: 0xE3F5ED))
    static let peach = Color(UIColor(lab: 0xFFF0DB))
    static let border = Color(UIColor(lab: 0xCBDDD5))
}
