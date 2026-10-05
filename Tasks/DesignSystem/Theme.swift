import SwiftUI

enum Theme {
    static let accent = Color("ThemeAccent")
    static let lime = Color("ThemeLime")
    static let highlightContent = Color("ThemeHighlightContent")
    static let actionBackground = Color("ThemeActionBackground")
    static let cyan = Color("ThemeCyan")
    static let gradientStart = Color("ThemeGradientStart")
    static let gradientEnd = Color("ThemeGradientEnd")
    static let secondaryGradient = LinearGradient(colors: [gradientStart, gradientEnd], startPoint: .top, endPoint: .bottom)
    static let navigationBackground = Color("ThemeNavigationBackground")
    static let navigationContent = Color("ThemeNavigationContent")
    static let nativeDestructive = Color("ThemeNativeDestructive")
    static let nativeSelection = Color("ThemeNativeSelection")
    static let onAccent = Color("ThemeOnAccent")
    static let background = Color("ThemeBackground")
    static let surface = Color("ThemeSurface")
    static let surfaceSecondary = Color("ThemeSurfaceSecondary")
    static let textPrimary = Color("ThemeTextPrimary")
    static let textSecondary = Color("ThemeTextSecondary")
    static let border = Color("ThemeBorder")
    static let success = Color("ThemeSuccess")
    static let warning = Color("ThemeWarning")
    static let error = Color("ThemeError")
    static let accentBackground = actionBackground.opacity(Feedback.statusBackgroundOpacity)
    static let warningBackground = warning.opacity(Feedback.statusBackgroundOpacity)
    static let errorBackground = error.opacity(Feedback.statusBackgroundOpacity)

    static let plannerSurface = surface
    static let plannerLine = border
    static let selectedSurface = accent.opacity(Feedback.selectionBackgroundOpacity)

    enum Pastel {
        static let sage = Color("PastelSage")
        static let blue = Color("TaskBlue")
        static let lavender = Color("TaskLavender")
        static let peach = Color("TaskPeach")
        static let pink = Color("TaskPink")
        static let yellow = Color("TaskYellow")
        static let mint = Color("TaskMint")
        static let coral = Color("PastelCoral")
    }

    enum TaskPalette {
        static let content = textPrimary
        static let secondaryContent = textSecondary
        static let overdue = error
        static let cardBackground = surface
        static let searchHighlight = content.opacity(Feedback.statusBackgroundOpacity)
    }

    enum CategoryPalette {
        static let content = Color("CategoryContent")

        static func foreground(for category: TaskIcon?) -> Color {
            category == nil ? textPrimary : content
        }

        static func background(for category: TaskIcon?) -> Color {
            switch category {
            case .exercise: Pastel.sage
            case .study: Pastel.lavender
            case .work: Pastel.blue
            case .shopping: Pastel.peach
            case .walking: Pastel.mint
            case .health: Pastel.pink
            case .home: Pastel.yellow
            case .music: Pastel.coral
            case nil: surfaceSecondary
            }
        }
    }

    enum Home {
        static let navigationMaxWidth: CGFloat = 360
        static let progressFillDuration = 0.65
        static let taskCardWidth: CGFloat = 208
        static let taskCardMinHeight: CGFloat = 184
    }

    enum Editor {
        static let quickSheetHeight: CGFloat = 460
        static let toolbarTouchTarget = Metrics.minTouchTarget
        static let mediaWidth: CGFloat = 240
        static let mediaMaximumWidth: CGFloat = 640
        static let mediaHeight: CGFloat = 168
        static let captionHeight: CGFloat = 40
    }

    enum Planner {
        static let selectedDay = actionBackground
        static let selectedDayContent = onAccent
        static let timeColumnWidth: CGFloat = 80
        static let taskColumnMinWidth: CGFloat = 128
        static let hourMinHeight: CGFloat = 64
        static let eventMarkerWidth: CGFloat = 3
        static let dayMinWidth: CGFloat = 44
        static let dayHeight: CGFloat = 84
    }

    enum Typography {
        static let homeSectionTitle = Font.title3.weight(.semibold)
        static let screenTitle = Font.largeTitle.bold()
        static let editorTitle = Font.title2.weight(.semibold)
        static let taskTitle = Font.body
        static let sectionTitle = Font.title2.bold()
        static let headline = Font.headline
        static let toolbarIcon = Font.title3.weight(.medium)
        static let body = Font.body
        static let callout = Font.callout
        static let metadata = Font.subheadline
        static let metadataEmphasis = Font.subheadline.weight(.semibold)
        static let footnote = Font.footnote
        static let sectionLabel = Font.footnote.weight(.semibold)
        static let numeric = Font.subheadline.monospacedDigit()
        static let checkmark = Font.caption.bold()
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Layout {
        static let cardInset = Spacing.md
        static let sectionSpacing = Spacing.xl
        static let rowSpacing = Spacing.xs
        static let iconSpacing = Spacing.sm
        static let headerActionSize = Metrics.minTouchTarget + Spacing.xs
    }

    static let pageMargin = Spacing.lg
    static let listRowInsets = EdgeInsets(top: Spacing.xs, leading: Spacing.md,
                                         bottom: Spacing.xs, trailing: Spacing.md)
    static let contentRowInsets = EdgeInsets()

    enum Radius {
        static let icon: CGFloat = 8
        static let card: CGFloat = 20
        static let banner: CGFloat = 16
        static let composer: CGFloat = 28
        static let sheetTop: CGFloat = 32
        static let button: CGFloat = 28
    }

    enum Metrics {
        static let minTouchTarget: CGFloat = 44
        static let floatingActionSize: CGFloat = 56
        static let highlightCardMinHeight = rowMinHeight * 2 + Spacing.md
        static let rowMinHeight: CGFloat = 56
        static let checkboxSize: CGFloat = 24
        static let taskIconSize: CGFloat = 28
        static let profileAvatarSize: CGFloat = 72
        static let checkboxStroke: CGFloat = 2
        static let borderStroke: CGFloat = 1
    }

    enum Icon {
        static let failure = "exclamationmark.triangle"
        static let checkmark = "checkmark"
        static let add = "plus"
        static let close = "xmark"
    }

    enum Feedback {
        static let completionIconDuration: Duration = .milliseconds(450)
        static let selectionBackgroundOpacity = 0.06
        static let statusBackgroundOpacity = 0.12
        static let pressedOpacity = 0.8
        static let stateChange = Animation.easeInOut(duration: 0.2)
    }
}

struct PrimaryActionStyle: ButtonStyle {
    enum Shape { case rounded, circle }
    var shape: Shape = .rounded
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .frame(minWidth: Theme.Metrics.minTouchTarget, minHeight: Theme.Metrics.minTouchTarget)
            .foregroundStyle(isEnabled ? Theme.onAccent : Theme.textSecondary)
            .background {
                if shape == .circle {
                    Circle().fill(isEnabled ? Theme.actionBackground : Theme.surface)
                } else {
                    RoundedRectangle(cornerRadius: Theme.Radius.button)
                        .fill(isEnabled ? Theme.actionBackground : Theme.surface)
                }
            }
            .opacity(configuration.isPressed ? Theme.Feedback.pressedOpacity : 1)
    }
}

extension EnvironmentValues {
    @Entry var bottomNavigationHeight: CGFloat = 0
}
