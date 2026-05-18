import Foundation

/// Atomic unit in the search bar. Ordered tokens (text + pills) are the SwiftUI source of truth; NSTextView mirrors them as an NSAttributedString.
enum SearchBarToken: Equatable, Hashable, Codable {
    case text(String)
    case filter(ClipFilter)
}

extension Array where Element == SearchBarToken {
    var freeText: String {
        compactMap { if case .text(let s) = $0 { return s }; return nil }.joined()
    }

    var filters: [ClipFilter] {
        compactMap { if case .filter(let f) = $0 { return f }; return nil }
    }
}
