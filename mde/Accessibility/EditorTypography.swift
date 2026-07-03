//
//  EditorTypography.swift
//  MDE
//

import SwiftUI

enum EditorTypography {
    /// Maximum Dynamic Type used in the editor for layout stability.
    static let maxEditorDynamicType: DynamicTypeSize = .accessibility3

    static func baseFontSize(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        baseFontSizePoints(for: cappedDynamicType(dynamicTypeSize))
    }

    private static func cappedDynamicType(_ size: DynamicTypeSize) -> DynamicTypeSize {
        switch size {
        case .accessibility4, .accessibility5:
            return maxEditorDynamicType
        default:
            return size
        }
    }

    private static func baseFontSizePoints(for cappedSize: DynamicTypeSize) -> CGFloat {
        switch cappedSize {
        case .xSmall: 13
        case .small: 14
        case .medium: 15
        case .large: 17
        case .xLarge: 19
        case .xxLarge: 21
        case .xxxLarge: 23
        case .accessibility1: 25
        case .accessibility2: 27
        case .accessibility3: 29
        case .accessibility4: 31
        case .accessibility5: 33
        @unknown default: 15
        }
    }

    static func headingSize(level: Int, baseSize: CGFloat) -> CGFloat {
        switch min(level, 6) {
        case 1: baseSize + 13
        case 2: baseSize + 7
        case 3: baseSize + 3
        default: baseSize
        }
    }
}
