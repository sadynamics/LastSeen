//
//  LastSeenTests.swift
//

import Testing
@testable import LastSeen

struct LastSeenTests {

    @Test func durationFormatting_underMinute() {
        #expect(45.asDuration == "45s")
    }

    @Test func durationFormatting_minutes() {
        #expect((90).asDuration == "2m") // rounds
    }

    @Test func durationFormatting_hours() {
        #expect(3_600.asDuration == "1h")
        #expect(3_900.asDuration == "1h 5m")
    }

    @Test func country_lookup_currentRegion_returnsValid() {
        let c = Country.current
        #expect(!c.iso.isEmpty)
        #expect(!c.dialCode.isEmpty)
    }

    @Test func country_flag_isTwoEmoji() {
        let c = Country.all.first(where: { $0.iso == "TR" })!
        #expect(c.flag == "🇹🇷")
    }
}
