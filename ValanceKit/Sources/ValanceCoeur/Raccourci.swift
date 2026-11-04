import Foundation

/// Modificateurs d'un raccourci, indépendants d'AppKit et de Carbon.
public struct Modificateurs: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let controle = Modificateurs(rawValue: 1 << 0)
    public static let option = Modificateurs(rawValue: 1 << 1)
    public static let majuscule = Modificateurs(rawValue: 1 << 2)
    public static let commande = Modificateurs(rawValue: 1 << 3)

    /// Masques Carbon (`Events.h`) : cmdKey, shiftKey, optionKey, controlKey.
    public static let carbonCommande: UInt32 = 0x0100
    public static let carbonMajuscule: UInt32 = 0x0200
    public static let carbonOption: UInt32 = 0x0800
    public static let carbonControle: UInt32 = 0x1000

    /// Masques `NSEvent.ModifierFlags` (valeurs publiques et stables d'AppKit).
    public static let cocoaMajuscule: UInt = 1 << 17
    public static let cocoaControle: UInt = 1 << 18
    public static let cocoaOption: UInt = 1 << 19
    public static let cocoaCommande: UInt = 1 << 20

    public var carbon: UInt32 {
        var m: UInt32 = 0
        if contains(.commande) { m |= Self.carbonCommande }
        if contains(.majuscule) { m |= Self.carbonMajuscule }
        if contains(.option) { m |= Self.carbonOption }
        if contains(.controle) { m |= Self.carbonControle }
        return m
    }

    public init(drapeauxCocoa d: UInt) {
        var m: Modificateurs = []
        if d & Self.cocoaControle != 0 { m.insert(.controle) }
        if d & Self.cocoaOption != 0 { m.insert(.option) }
        if d & Self.cocoaMajuscule != 0 { m.insert(.majuscule) }
        if d & Self.cocoaCommande != 0 { m.insert(.commande) }
        self = m
    }

    /// Symboles dans l'ordre d'Apple : ⌃ ⌥ ⇧ ⌘.
    public var symboles: String {
        var s = ""
        if contains(.controle) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.majuscule) { s += "⇧" }
        if contains(.commande) { s += "⌘" }
        return s
    }
}

/// Raccourci clavier global : un code de touche physique (kVK_…) et des modificateurs.
public struct Raccourci: Codable, Hashable, Sendable, CustomStringConvertible {
    public var codeTouche: UInt16
    public var modificateurs: Modificateurs
    /// Caractère réellement imprimé sur la touche dans la disposition de l'utilisateur (AZERTY…), saisi à
    /// l'enregistrement ; sert seulement à l'affichage.
    public var libelle: String?

    public init(codeTouche: UInt16, modificateurs: Modificateurs, libelle: String? = nil) {
        self.codeTouche = codeTouche
        self.modificateurs = modificateurs
        self.libelle = libelle
    }

    /// ⌃⌥⌘V (« V » comme Valance), peu utilisé par les apps.
    public static let parDefaut = Raccourci(codeTouche: 0x09, modificateurs: [.controle, .option, .commande])

    /// Accepté si au moins un modificateur autre que ⇧, ou s'il s'agit d'une touche de fonction seule.
    /// Une lettre seule ou ⇧+lettre volerait la frappe normale.
    public var estValide: Bool {
        if NomsTouches.estToucheDeFonction(codeTouche) { return true }
        if NomsTouches.estModificateur(codeTouche) { return false }
        return !modificateurs.subtracting(.majuscule).isEmpty
    }

    public var nomTouche: String {
        if let l = libelle?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty,
           NomsTouches.nomSpecial(codeTouche) == nil {
            return l.uppercased()
        }
        return NomsTouches.nom(codeTouche)
    }

    public var description: String { modificateurs.symboles + nomTouche }

    public static func == (a: Raccourci, b: Raccourci) -> Bool {
        a.codeTouche == b.codeTouche && a.modificateurs == b.modificateurs
    }

    public func hash(into h: inout Hasher) {
        h.combine(codeTouche)
        h.combine(modificateurs)
    }
}

/// Noms des touches par code physique (positions ANSI ; la disposition réelle est donnée par `libelle`).
public enum NomsTouches {
    private static let lettres: [UInt16: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
        0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
        0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
        0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P", 0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x32: "`", 0x0A: "§",
    ]

    private static let speciales: [UInt16: String] = [
        0x24: "↩", 0x30: "⇥", 0x31: "Espace", 0x33: "⌫", 0x35: "⎋", 0x75: "⌦",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑", 0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",
    ]

    private static let fonctions: [UInt16: Int] = [
        0x7A: 1, 0x78: 2, 0x63: 3, 0x76: 4, 0x60: 5, 0x61: 6, 0x62: 7, 0x64: 8, 0x65: 9, 0x6D: 10,
        0x67: 11, 0x6F: 12, 0x69: 13, 0x6B: 14, 0x71: 15, 0x6A: 16, 0x40: 17, 0x4F: 18, 0x50: 19, 0x5A: 20,
    ]

    /// Codes des touches de modification elles-mêmes (⌘, ⇧, ⌥, ⌃, verrouillage, fn).
    private static let modificateurs: Set<UInt16> = [0x37, 0x36, 0x38, 0x3C, 0x3A, 0x3D, 0x3B, 0x3E, 0x39, 0x3F]

    public static func estToucheDeFonction(_ code: UInt16) -> Bool { fonctions[code] != nil }
    public static func estModificateur(_ code: UInt16) -> Bool { modificateurs.contains(code) }
    public static func nomSpecial(_ code: UInt16) -> String? {
        if let f = fonctions[code] { return "F\(f)" }
        return speciales[code]
    }

    public static func nom(_ code: UInt16) -> String {
        nomSpecial(code) ?? lettres[code] ?? "touche \(code)"
    }
}
