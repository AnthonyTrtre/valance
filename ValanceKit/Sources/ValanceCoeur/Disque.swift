import Foundation

/// Un volume local et sa place, en octets. « Libre » compte l'espace que macOS peut récupérer (caches, copies
/// iCloud), comme le Finder : c'est `volumeAvailableCapacityForImportantUsage`.
public struct VolumeDecrit: Equatable, Sendable {
    public var nom: String
    public var libre: Int64
    public var total: Int64

    public init(nom: String, libre: Int64, total: Int64) {
        self.nom = nom
        self.libre = libre
        self.total = total
    }

    /// Part libre, entre 0 et 1.
    public var partLibre: Double { total > 0 ? min(1, max(0, Double(libre) / Double(total))) : 0 }

    /// Moins de 10 % ou de 20 Go libres : la barre l'affiche en orange.
    public var estPresquePlein: Bool { total > 0 && (partLibre < 0.10 || libre < 20_000_000_000) }
}

public enum FormatDisque {
    /// Unités décimales, comme le Finder : « 142 Go », « 1,2 To », « 850 Mo ».
    public static func court(_ octets: Int64) -> String {
        let o = Double(max(0, octets))
        func f(_ v: Double, _ u: String) -> String {
            let texte = v < 10 ? String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") : String(Int(v.rounded()))
            return "\(texte.hasSuffix(",0") ? String(texte.dropLast(2)) : texte) \(u)"
        }
        if o >= 1e12 { return f(o / 1e12, "To") }
        if o >= 1e9 { return f(o / 1e9, "Go") }
        return f(o / 1e6, "Mo")
    }

    /// « Macintosh HD : 142 Go libres sur 994 Go (14 %) ».
    public static func detail(_ v: VolumeDecrit) -> String {
        "\(v.nom) : \(court(v.libre)) libres sur \(court(v.total)) (\(Int((v.partLibre * 100).rounded())) %)"
    }
}
