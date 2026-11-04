import Testing
@testable import ValanceCoeur

@Suite("Espace disque")
struct DisqueTests {
    @Test func formatCourt() {
        #expect(FormatDisque.court(142_400_000_000) == "142 Go")
        #expect(FormatDisque.court(1_230_000_000_000) == "1,2 To")
        #expect(FormatDisque.court(2_000_000_000_000) == "2 To")
        #expect(FormatDisque.court(8_460_000_000) == "8,5 Go")
        #expect(FormatDisque.court(850_000_000) == "850 Mo")
        #expect(FormatDisque.court(-5) == "0 Mo")
    }

    @Test func detail() {
        let v = VolumeDecrit(nom: "Macintosh HD", libre: 142_000_000_000, total: 994_000_000_000)
        #expect(FormatDisque.detail(v) == "Macintosh HD : 142 Go libres sur 994 Go (14 %)")
    }

    @Test func presquePlein() {
        #expect(!VolumeDecrit(nom: "a", libre: 142_000_000_000, total: 994_000_000_000).estPresquePlein)
        #expect(VolumeDecrit(nom: "a", libre: 90_000_000_000, total: 1_000_000_000_000).estPresquePlein)   // 9 %
        #expect(VolumeDecrit(nom: "a", libre: 15_000_000_000, total: 100_000_000_000).estPresquePlein)     // 15 Go
        #expect(!VolumeDecrit(nom: "a", libre: 0, total: 0).estPresquePlein)
    }
}
