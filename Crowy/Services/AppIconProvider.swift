import AppKit
import Observation
import SwiftUI

/// Caches app icons by bundle ID and derives a dominant color for card headers.
@MainActor
@Observable
final class AppIconProvider {

    @ObservationIgnored
    private var iconCache: [String: NSImage] = [:]
    @ObservationIgnored
    private var colorCache: [String: Color] = [:]

    static let fallbackHeaderColor: Color = Color(white: 0.18)

    func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let cached = iconCache[bundleID] { return cached }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[bundleID] = icon
        return icon
    }

    func headerColor(forBundleID bundleID: String?) -> Color {
        guard let bundleID, !bundleID.isEmpty else { return Self.fallbackHeaderColor }
        if let cached = colorCache[bundleID] { return cached }
        guard let nsImage = icon(forBundleID: bundleID) else {
            return Self.fallbackHeaderColor
        }
        let color = Self.extractDominantColor(from: nsImage)
        colorCache[bundleID] = color
        return color
    }

    /// Quantized histogram of opaque, sufficiently saturated pixels.
    /// Brightness clamped to 0.7 max so white text stays readable on top.
    private static func extractDominantColor(from image: NSImage) -> Color {
        let dim = 24
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: dim,
            pixelsHigh: dim,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return fallbackHeaderColor }

        bitmap.size = NSSize(width: dim, height: dim)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(
            in: NSRect(x: 0, y: 0, width: dim, height: dim),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        // 3 bits/channel = 512 buckets. Also tracks the most saturated pixel
        // so we can fall back to it when the dominant bucket is gray/white.
        var buckets: [Int: (count: Int, r: Double, g: Double, b: Double)] = [:]
        var bestSaturated: (saturation: Double, r: Double, g: Double, b: Double) = (0, 0.5, 0.5, 0.5)

        for y in 0..<dim {
            for x in 0..<dim {
                guard let c = bitmap.colorAt(x: x, y: y),
                      c.alphaComponent > 0.5 else { continue }
                let r = Double(c.redComponent)
                let g = Double(c.greenComponent)
                let b = Double(c.blueComponent)

                let maxC = max(r, g, b)
                let minC = min(r, g, b)
                let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC

                if saturation > bestSaturated.saturation {
                    bestSaturated = (saturation, r, g, b)
                }

                let qr = Int(r * 7), qg = Int(g * 7), qb = Int(b * 7)
                let key = qr * 64 + qg * 8 + qb
                let cur = buckets[key] ?? (0, 0, 0, 0)
                buckets[key] = (cur.count + 1, cur.r + r, cur.g + g, cur.b + b)
            }
        }

        guard let best = buckets.max(by: { $0.value.count < $1.value.count }) else {
            return fallbackHeaderColor
        }

        let (count, sumR, sumG, sumB) = best.value
        var r = sumR / Double(count)
        var g = sumG / Double(count)
        var b = sumB / Double(count)

        // If the dominant bucket is desaturated, prefer a vibrant pixel found elsewhere.
        let dominantSat: Double = {
            let mx = max(r, g, b), mn = min(r, g, b)
            return mx == 0 ? 0 : (mx - mn) / mx
        }()
        if dominantSat < 0.2 && bestSaturated.saturation > 0.4 {
            r = bestSaturated.r
            g = bestSaturated.g
            b = bestSaturated.b
        }

        // Clamp brightness so white text stays readable.
        let brightness = max(r, g, b)
        if brightness > 0.7 {
            let scale = 0.7 / brightness
            r *= scale; g *= scale; b *= scale
        }

        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
