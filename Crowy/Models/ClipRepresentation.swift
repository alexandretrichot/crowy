import Foundation

/// One UTI-tagged representation of a clip. A single copy (e.g. from Figma) may produce
/// several reps (`public.png`, `com.adobe.pdf`, `public.utf8-plain-text`, …); all are kept
/// to preserve paste fidelity. Storage location (inline DB vs blob on disk) lives elsewhere.
struct ClipRepresentation: Codable, Equatable {
    var clipID: UUID
    var uti: String
    var data: Data

    var byteSize: Int { data.count }
}
