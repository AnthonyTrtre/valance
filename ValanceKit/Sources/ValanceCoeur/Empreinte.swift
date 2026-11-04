import Foundation

/// Image en niveaux de gris (un octet par pixel, lignes de haut en bas), fournie par la coque d'app.
public struct ImageGrise: Equatable, Sendable {
    public var largeur: Int
    public var hauteur: Int
    public var pixels: [UInt8]

    public init(largeur: Int, hauteur: Int, pixels: [UInt8]) {
        precondition(largeur >= 0 && hauteur >= 0 && pixels.count == largeur * hauteur, "taille incohérente")
        self.largeur = largeur
        self.hauteur = hauteur
        self.pixels = pixels
    }

    public func pixel(_ x: Int, _ y: Int) -> UInt8 { pixels[y * largeur + x] }
}

/// Empreinte perceptive par différences (« dHash », 64 bits) : l'image est réduite à 9 × 8 par moyenne de
/// zones, puis chaque bit dit si un pixel est plus clair que son voisin de droite. Deux images semblables
/// ont des empreintes proches (distance de Hamming faible), même après un léger changement d'échelle.
public struct Empreinte: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var bits: UInt64

    public init(bits: UInt64) { self.bits = bits }

    public init?(_ image: ImageGrise) {
        guard image.largeur > 0, image.hauteur > 0 else { return nil }
        let reduite = Self.reduire(image, largeur: 9, hauteur: 8)
        var b: UInt64 = 0
        var n = 0
        for y in 0..<8 {
            for x in 0..<8 {
                if reduite[y * 9 + x] > reduite[y * 9 + x + 1] { b |= (1 << UInt64(n)) }
                n += 1
            }
        }
        bits = b
    }

    public func distance(_ autre: Empreinte) -> Int { (bits ^ autre.bits).nonzeroBitCount }

    public var description: String {
        let h = String(bits, radix: 16)
        return String(repeating: "0", count: max(0, 16 - h.count)) + h
    }

    /// Réduction par moyenne de zones (chaque pixel de sortie couvre un rectangle de l'entrée).
    static func reduire(_ img: ImageGrise, largeur lw: Int, hauteur lh: Int) -> [Double] {
        var sortie = [Double](repeating: 0, count: lw * lh)
        for oy in 0..<lh {
            let y0 = oy * img.hauteur / lh
            let y1 = max(y0 + 1, (oy + 1) * img.hauteur / lh)
            for ox in 0..<lw {
                let x0 = ox * img.largeur / lw
                let x1 = max(x0 + 1, (ox + 1) * img.largeur / lw)
                var somme = 0.0
                var n = 0.0
                for y in y0..<min(y1, img.hauteur) {
                    for x in x0..<min(x1, img.largeur) {
                        somme += Double(img.pixel(x, y))
                        n += 1
                    }
                }
                sortie[oy * lw + ox] = n > 0 ? somme / n : 0
            }
        }
        return sortie
    }
}

/// Décide quand une icône surveillée a « changé » : distance d'empreinte au-dessus d'un seuil, avec un délai
/// de grâce par icône pour ne pas révéler la barre en boucle (icône animée).
public struct DetecteurChangements: Sendable {
    public var seuil: Int
    public var grace: TimeInterval
    private var dernieres: [String: Empreinte] = [:]
    private var derniersSignalements: [String: Date] = [:]

    public init(seuil: Int = 6, grace: TimeInterval = 60) {
        self.seuil = seuil
        self.grace = grace
    }

    /// Enregistre l'empreinte et dit s'il faut signaler un changement. La première observation ne signale rien.
    public mutating func observer(cle: String, empreinte: Empreinte, maintenant: Date) -> Bool {
        defer { dernieres[cle] = empreinte }
        guard let avant = dernieres[cle], avant.distance(empreinte) >= seuil else { return false }
        if let d = derniersSignalements[cle], maintenant.timeIntervalSince(d) < grace { return false }
        derniersSignalements[cle] = maintenant
        return true
    }

    /// Oublie les icônes disparues.
    public mutating func garder(seulement cles: Set<String>) {
        dernieres = dernieres.filter { cles.contains($0.key) }
        derniersSignalements = derniersSignalements.filter { cles.contains($0.key) }
    }
}
