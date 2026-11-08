import Foundation
import Testing
@testable import converter_ios

/// The Clock category is built around the device's own time zone, so the tests pass a known zone
/// in. Conversions are checked between Dubai and Kolkata, which keep a fixed 1.5 hours between
/// them all year and so are not at the mercy of whenever the suite happens to run.
@MainActor
struct ClockCategoryTests {

    private let format = ClockFormat()

    private func clock() throws -> converter_ios.Category {
        clockCategory(local: try #require(TimeZone(identifier: "America/New_York")))
    }

    private func dubaiAndKolkata() throws -> (ConvUnit, ConvUnit) {
        let units = try clock().units
        return (
            try #require(units.first { $0.name == "Dubai" }),
            try #require(units.first { $0.name == "Kolkata" })
        )
    }

    /// Parse text that is expected to read as a time, so the assertions stay on Doubles.
    private func parsed(_ text: String) throws -> Double {
        try #require(format.parse(text))
    }

    @Test func leadsWithTheDeviceZoneAndDoesNotRepeatIt() throws {
        let clock = try clock()
        #expect(clock.units.first?.name == "Local time")
        #expect(clock.units.first?.symbol.hasPrefix("New York · UTC-0") == true)
        // The device is already showing New York time, so the city itself is left out.
        #expect(!clock.units.dropFirst().contains { $0.name == "New York" })
        #expect(clock.units.contains { $0.name == "Tokyo" })
    }

    @Test func ordersTheOtherZonesWestToEast() throws {
        let names = try clock().units.dropFirst().map(\.name)
        let london = try #require(names.firstIndex(of: "London"))
        let kolkata = try #require(names.firstIndex(of: "Kolkata"))
        let tokyo = try #require(names.firstIndex(of: "Tokyo"))
        #expect(london < kolkata)
        #expect(kolkata < tokyo)
    }

    @Test func convertsBetweenZones() throws {
        let (dubai, kolkata) = try dubaiAndKolkata()
        #expect(abs(dubai.convert(12, to: kolkata) - 13.5) < 1e-9)
        #expect(abs(kolkata.convert(13.5, to: dubai) - 12) < 1e-9)
    }

    @Test func carriesTimesPastMidnightIntoTheNextOrPreviousDay() throws {
        let (dubai, kolkata) = try dubaiAndKolkata()
        #expect(format.format(dubai.convert(23.5, to: kolkata)) == "01:00 +1d")
        #expect(format.format(kolkata.convert(0.5, to: dubai)) == "23:00 -1d")
    }

    @Test func opensOnATimeOfDay() throws {
        let openingValue = try #require(try clock().openingValue)
        let opening = openingValue()
        #expect(opening >= 0 && opening < 24)
    }

    @Test(arguments: [
        (0.0, "00:00"),
        (14.5, "14:30"),
        (32.5, "08:30 +1d"),
        (-1.0, "23:00 -1d")
    ])
    func formatsHoursAsTimesOfDay(hours: Double, expected: String) {
        #expect(format.format(hours) == expected)
    }

    /// Text typed into a Clock field, and the hours it should read as.
    private static let typedTimes: [(String, Double)] = [
        ("9", 9.0),
        ("9:", 9.0),
        ("09:05", 9.0 + 5.0 / 60),
        ("9:05:30", 9.0 + 5.5 / 60),
        ("9:00 pm", 21.0),
        ("12:30 AM", 0.5),
        ("12:30 pm", 12.5),
        // The day marker the fields display has to read back as the value it was printed from.
        ("08:30 +1d", 32.5),
        ("23:00 -1d", -1.0)
    ]

    @Test(arguments: typedTimes)
    func readsTimesTypedAnyOfTheUsualWays(text: String, expected: Double) throws {
        #expect(abs(try parsed(text) - expected) < 1e-9)
    }

    @Test(arguments: ["", "noon", "24:00", "9:75", "13:00 pm"])
    func refusesTextThatIsNotATime(text: String) {
        #expect(format.parse(text) == nil)
    }

    @Test func acceptsTheLastMinuteOfTheDay() {
        #expect(format.parse("23:59") != nil)
    }
}
