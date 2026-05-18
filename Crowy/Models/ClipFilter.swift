import Foundation

/// Filter criterion. Filters AND together at the repository level. `.text` uses FTS5; others are plain WHERE.
enum ClipFilter: Equatable, Hashable {
    case text(String)
    case time(TimeRange)
    case kind(Clip.Kind)
    case app(bundleID: String, displayName: String?)
}

// MARK: - Codable

// Manual Codable: Swift doesn't synthesize for enums with labeled/optional associated values.
// Used for the custom pasteboard type in the search bar (in-app JSON round-trip).
extension ClipFilter: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, value, bundleID, displayName
    }
    private enum FilterType: String, Codable {
        case text, time, kind, app
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let s):
            try c.encode(FilterType.text, forKey: .type)
            try c.encode(s, forKey: .value)
        case .time(let r):
            try c.encode(FilterType.time, forKey: .type)
            try c.encode(r, forKey: .value)
        case .kind(let k):
            try c.encode(FilterType.kind, forKey: .type)
            try c.encode(k, forKey: .value)
        case .app(let bundleID, let displayName):
            try c.encode(FilterType.app, forKey: .type)
            try c.encode(bundleID, forKey: .bundleID)
            try c.encodeIfPresent(displayName, forKey: .displayName)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(FilterType.self, forKey: .type) {
        case .text: self = .text(try c.decode(String.self, forKey: .value))
        case .time: self = .time(try c.decode(TimeRange.self, forKey: .value))
        case .kind: self = .kind(try c.decode(Clip.Kind.self, forKey: .value))
        case .app:
            self = .app(
                bundleID: try c.decode(String.self, forKey: .bundleID),
                displayName: try c.decodeIfPresent(String.self, forKey: .displayName)
            )
        }
    }
}

/// Relative time ranges. Computed via `Calendar.current` at query time — no cache, so "today" rolls over at midnight.
enum TimeRange: String, Equatable, Hashable, Codable, CaseIterable {
    case lastHour
    case today
    case yesterday
    case thisWeek
    case thisMonth

    nonisolated var label: String {
        switch self {
        case .lastHour:  return "Last hour"
        case .today:     return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek:  return "This week"
        case .thisMonth: return "This month"
        }
    }

    var startDate: Date {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .lastHour:
            return now.addingTimeInterval(-3600)
        case .today:
            return cal.startOfDay(for: now)
        case .yesterday:
            return cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))
                ?? cal.startOfDay(for: now)
        case .thisWeek:
            return cal.dateInterval(of: .weekOfYear, for: now)?.start
                ?? cal.startOfDay(for: now)
        case .thisMonth:
            return cal.dateInterval(of: .month, for: now)?.start
                ?? cal.startOfDay(for: now)
        }
    }

    /// Exclusive upper bound. `nil` means open-ended (today/this week/this month include incoming clips).
    var endDate: Date? {
        let cal = Calendar.current
        switch self {
        case .yesterday: return cal.startOfDay(for: Date())
        default:         return nil
        }
    }
}

// MARK: - Display helpers

extension ClipFilter {
    nonisolated var pillLabel: String {
        switch self {
        case .text(let q):          return q
        case .time(let range):      return range.label
        case .kind(let kind):       return kind.label
        case .app(_, let name):     return name ?? "App"
        }
    }
}

extension Clip.Kind {
    nonisolated var label: String {
        switch self {
        case .text:    return "Text"
        case .link:    return "Link"
        case .unknown: return "Other"
        case .color:   return "Color"
        case .image:   return "Image"
        case .file:    return "File"
        }
    }

    nonisolated var sfSymbol: String {
        switch self {
        case .text:    return "text.alignleft"
        case .link:    return "link"
        case .unknown: return "questionmark.square.dashed"
        case .color:   return "eyedropper.halffull"
        case .image:   return "photo"
        case .file:    return "doc"
        }
    }
}

extension TimeRange {
    nonisolated var sfSymbol: String { "calendar" }
}

