import Foundation
import Testing
@testable import ValanceCoeur

@Suite("Utilisation de Claude")
struct ClaudeTests {
    @Test func reponseDeClaudeCode() throws {
        let json = """
        {"type":"control_response","response":{"subtype":"success","request_id":"u1","response":{
          "subscription_type":"max","rate_limits_available":true,
          "rate_limits":{"five_hour":null,"seven_day":{"utilization":15,"resets_at":"2026-11-10T18:00:00.916316+00:00"}}}}}
        """
        let u = try #require(UtilisationClaude.lire(Data(json.utf8)))
        #expect(u.semaine == 15)
        #expect(u.restantSemaine == 85)
        #expect(u.cinqHeures == nil)
        #expect(abs((u.remiseSemaine?.timeIntervalSince1970 ?? 0) - 1794333600) < 1)   // 10/11/2026 18:00 UTC
        #expect(!u.bientotEpuise)
    }

    @Test func cinqHeuresEtSeuil() throws {
        let json = #"{"rate_limits":{"five_hour":{"utilization":40.5,"resets_at":"2026-11-05T12:00:00Z"},"seven_day":{"utilization":93}}}"#
        let u = try #require(UtilisationClaude.lire(Data(json.utf8)))
        #expect(u.cinqHeures == 40.5)
        #expect(u.restantSemaine == 7)
        #expect(u.bientotEpuise)
    }

    @Test func sansLimites() {
        #expect(UtilisationClaude.lire(Data(#"{"rate_limits_available":false,"rate_limits":null}"#.utf8)) == nil)
        #expect(UtilisationClaude.lire(Data("pas du json".utf8)) == nil)
    }
}
