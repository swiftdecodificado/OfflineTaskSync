import SwiftUI

enum TaskSearchPreview {
    static func snippet(_ text: String, query: String) -> String {
        let text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let match = text.localizedStandardRange(of: query) else {
            return String(text.prefix(160)) + (text.count > 160 ? "…" : "")
        }
        let start = text.index(match.lowerBound, offsetBy: -24, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(match.upperBound, offsetBy: 96, limitedBy: text.endIndex) ?? text.endIndex
        return (start > text.startIndex ? "…" : "")
            + text[start..<end].trimmingCharacters(in: .whitespaces)
            + (end < text.endIndex ? "…" : "")
    }

    static func highlighted(_ text: String, query: String) -> AttributedString {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return AttributedString(text) }
        var remaining = text
        var result = AttributedString()
        while let match = remaining.localizedStandardRange(of: query), !match.isEmpty {
            result.append(AttributedString(remaining[..<match.lowerBound]))
            var highlighted = AttributedString(remaining[match])
            highlighted.inlinePresentationIntent = .stronglyEmphasized
            highlighted.backgroundColor = Theme.TaskPalette.searchHighlight
            highlighted.foregroundColor = Theme.TaskPalette.content
            result.append(highlighted)
            remaining = String(remaining[match.upperBound...])
        }
        result.append(AttributedString(remaining))
        return result
    }
}
