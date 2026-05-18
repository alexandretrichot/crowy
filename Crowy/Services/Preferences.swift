import Foundation
import Observation

/// Age-based retention policy. `.unlimited` disables age purge; size quota still applies.
enum RetentionPolicy: String, CaseIterable, Codable {
    case day
    case week
    case month
    case unlimited

    /// Max age of an unpinned clip. `nil` means no age limit.
    var maxAge: TimeInterval? {
        switch self {
        case .day:       return 24 * 3600
        case .week:      return 7 * 24 * 3600
        case .month:     return 30 * 24 * 3600
        case .unlimited: return nil
        }
    }

    var label: String {
        switch self {
        case .day:       return "24 hours"
        case .week:      return "1 week"
        case .month:     return "1 month"
        case .unlimited: return "Unlimited"
        }
    }
}

/// User preferences persisted via UserDefaults. `@Observable` so SwiftUI views
/// rebind automatically when the user edits a setting.
@MainActor
@Observable
final class Preferences {

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - App blacklist

    var blacklistedBundleIDs: Set<String> {
        get {
            access(keyPath: \.blacklistedBundleIDs)
            return Set(defaults.stringArray(forKey: Keys.blacklistedBundleIDs) ?? [])
        }
        set {
            withMutation(keyPath: \.blacklistedBundleIDs) {
                defaults.set(Array(newValue), forKey: Keys.blacklistedBundleIDs)
            }
        }
    }

    func addToBlacklist(bundleID: String) {
        var set = blacklistedBundleIDs
        set.insert(bundleID)
        blacklistedBundleIDs = set
    }

    func removeFromBlacklist(bundleID: String) {
        var set = blacklistedBundleIDs
        set.remove(bundleID)
        blacklistedBundleIDs = set
    }

    // MARK: - Retention

    /// Default: 1 month — balances user comfort with DB size.
    var retentionPolicy: RetentionPolicy {
        get {
            access(keyPath: \.retentionPolicy)
            guard let raw = defaults.string(forKey: Keys.retentionPolicy),
                  let policy = RetentionPolicy(rawValue: raw)
            else { return .month }
            return policy
        }
        set {
            withMutation(keyPath: \.retentionPolicy) {
                defaults.set(newValue.rawValue, forKey: Keys.retentionPolicy)
            }
        }
    }

    /// Total on-disk quota (sum of `totalBytes` across clips). Default 5 GB;
    /// GC drops the oldest unpinned clips above this.
    var maxCacheSizeBytes: Int64 {
        get {
            access(keyPath: \.maxCacheSizeBytes)
            let v = defaults.object(forKey: Keys.maxCacheSizeBytes) as? Int64
            return v ?? 5 * 1024 * 1024 * 1024  // 5 GB
        }
        set {
            withMutation(keyPath: \.maxCacheSizeBytes) {
                defaults.set(newValue, forKey: Keys.maxCacheSizeBytes)
            }
        }
    }

    // MARK: - Global hotkey

    var hotkey: HotkeyBinding {
        get {
            access(keyPath: \.hotkey)
            guard let data = defaults.data(forKey: Keys.hotkey),
                  let decoded = try? JSONDecoder().decode(HotkeyBinding.self, from: data)
            else { return .default }
            return decoded
        }
        set {
            withMutation(keyPath: \.hotkey) {
                if let data = try? JSONEncoder().encode(newValue) {
                    defaults.set(data, forKey: Keys.hotkey)
                }
            }
        }
    }

    // MARK: - Launch at login

    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return defaults.bool(forKey: Keys.launchAtLogin)
        }
        set {
            withMutation(keyPath: \.launchAtLogin) {
                defaults.set(newValue, forKey: Keys.launchAtLogin)
            }
        }
    }

    // MARK: - Keys

    private enum Keys {
        static let blacklistedBundleIDs = "blacklistedBundleIDs"
        static let retentionPolicy = "retentionPolicy"
        static let maxCacheSizeBytes = "maxCacheSizeBytes"
        static let hotkey = "globalHotkey"
        static let launchAtLogin = "launchAtLogin"
    }
}
