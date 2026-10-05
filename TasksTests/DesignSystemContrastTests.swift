import SwiftUI
import Testing
import UIKit

@testable import Tasks

@Suite
@MainActor
struct DesignSystemContrastTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func textAndControlsMeetContrastRequirements(scheme: ColorScheme) {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme

        for background in [Theme.background, Theme.surface, Theme.surfaceSecondary] {
            for foreground in [Theme.textPrimary, Theme.textSecondary, Theme.accent, Theme.success, Theme.warning, Theme.error] {
                #expect(contrast(foreground, background, in: environment) >= 4.5)
            }
        }
        for foreground in [Theme.textPrimary, Theme.textSecondary, Theme.accent] {
            #expect(contrast(foreground, Theme.selectedSurface, in: environment, over: Theme.background) >= 4.5)
            #expect(contrast(foreground, Theme.selectedSurface, in: environment, over: Theme.surface) >= 4.5)
        }
        #expect(contrast(Theme.onAccent, Theme.actionBackground, in: environment) >= 4.5)
        #expect(contrast(Theme.navigationContent, Theme.navigationBackground, in: environment) >= 4.5)
        #expect(contrast(Theme.lime, Theme.navigationBackground, in: environment) >= 3)
        #expect(contrast(.white, Theme.nativeSelection, in: environment) >= 4.5)
        #expect(contrast(.white, Theme.nativeDestructive, in: environment) >= 4.5)
        #expect(contrast(Theme.nativeSelection, Theme.background, in: environment) >= 3)
        #expect(contrast(Theme.textSecondary, Theme.border, in: environment) >= 4.5)

        for background in [Theme.warningBackground, Theme.errorBackground] {
            #expect(contrast(Theme.textPrimary, background, in: environment, over: Theme.background) >= 4.5)
        }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func taskCardsKeepReadableContent(scheme: ColorScheme) {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let card = Theme.TaskPalette.cardBackground
        for foreground in [Theme.TaskPalette.content, Theme.TaskPalette.secondaryContent, Theme.TaskPalette.overdue] {
            #expect(contrast(foreground, card, in: environment) >= 4.5)
        }
        for category in TaskIcon.allCases {
            #expect(contrast(Theme.CategoryPalette.content, Theme.CategoryPalette.background(for: category), in: environment) >= 4.5)
        }
        #expect(contrast(Theme.Planner.selectedDayContent, Theme.Planner.selectedDay, in: environment) >= 4.5)
        #expect(contrast(Theme.textSecondary, Theme.surface, in: environment) >= 4.5)
    }

    @Test(arguments: [UIUserInterfaceStyle.light, .dark], [UIAccessibilityContrast.normal, .high])
    func assetVariantsKeepReadableContent(style: UIUserInterfaceStyle, accessibilityContrast: UIAccessibilityContrast) throws {
        let traits = UITraitCollection {
            $0.userInterfaceStyle = style
            $0.accessibilityContrast = accessibilityContrast
        }
        var environment = EnvironmentValues()
        environment.colorScheme = style == .dark ? .dark : .light

        func asset(_ name: String) throws -> Color {
            let color = try #require(UIColor(named: name, in: .main, compatibleWith: traits))
            return Color(uiColor: color.resolvedColor(with: traits))
        }

        for surface in ["ThemeBackground", "ThemeSurface", "ThemeSurfaceSecondary"] {
            for content in ["ThemeTextPrimary", "ThemeTextSecondary", "ThemeAccent", "ThemeSuccess", "ThemeWarning", "ThemeError"] {
                #expect(try contrast(asset(content), asset(surface), in: environment) >= 4.5)
            }
        }
        #expect(try contrast(asset("ThemeOnAccent"), asset("ThemeActionBackground"), in: environment) >= 4.5)
        for background in ["ThemeLime", "ThemeGradientStart", "ThemeGradientEnd", "ThemeCyan"] {
            #expect(try contrast(asset("ThemeHighlightContent"), asset(background), in: environment) >= 4.5)
        }
        #expect(try contrast(asset("ThemeNavigationContent"), asset("ThemeNavigationBackground"), in: environment) >= 4.5)
        #expect(try contrast(asset("ThemeLime"), asset("ThemeNavigationBackground"), in: environment) >= 3)
        for background in ["ThemeNativeSelection", "ThemeNativeDestructive"] {
            #expect(try contrast(.white, asset(background), in: environment) >= 4.5)
        }
        for background in ["PastelSage", "TaskBlue", "TaskLavender", "TaskPeach", "TaskPink", "TaskYellow", "TaskMint", "PastelCoral"] {
            #expect(try contrast(asset("CategoryContent"), asset(background), in: environment) >= 4.5)
        }
    }

    private func contrast(_ foreground: Color, _ background: Color, in environment: EnvironmentValues, over base: Color? = nil) -> Double {
        func luminance(_ color: Color.Resolved) -> Double {
            0.2126 * Double(color.linearRed)
            + 0.7152 * Double(color.linearGreen)
            + 0.0722 * Double(color.linearBlue)
        }
        let front = luminance(foreground.resolve(in: environment))
        let back = background.resolve(in: environment)
        let alpha = Double(back.opacity)
        let backing = base.map { luminance($0.resolve(in: environment)) } ?? 0
        let blended = luminance(back) * alpha + backing * (1 - alpha)
        return (max(front, blended) + 0.05) / (min(front, blended) + 0.05)
    }
}
