import XCTest
import SwiftUI
import UIKit
@testable import YouthAISubsidy

final class AppThemeTests: XCTestCase {
    func testInkIsLighterInDarkMode() {
        XCTAssertGreaterThan(luminance(of: AppTheme.ink, style: .dark), luminance(of: AppTheme.ink, style: .light))
    }

    func testBackgroundIsDarkerInDarkMode() {
        XCTAssertGreaterThan(luminance(of: AppTheme.background, style: .light), luminance(of: AppTheme.background, style: .dark))
    }

    func testCardDiffersFromBackgroundInBothSchemes() {
        XCTAssertNotEqual(
            resolved(AppTheme.card, style: .light),
            resolved(AppTheme.background, style: .light)
        )
        XCTAssertNotEqual(
            resolved(AppTheme.card, style: .dark),
            resolved(AppTheme.background, style: .dark)
        )
    }

    private func resolved(_ color: Color, style: UIUserInterfaceStyle) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    private func luminance(of color: Color, style: UIUserInterfaceStyle) -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolved(color, style: style).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}
