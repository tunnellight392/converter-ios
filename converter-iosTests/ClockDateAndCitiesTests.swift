import Foundation
import Testing
@testable import converter_ios

/// Clock conversions on a chosen date, with daylight saving applied for that date, and cities
/// the user adds.
@MainActor
struct ClockDateTests {

    private let format = ClockFormat()

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    private func zone(_ id: String) throws -> TimeZone {
        try #require(TimeZone(identifier: id))
    }

    private func unit(_ name: String, in category: converter_ios.Category) throws -> ConvUnit {
        try #require(category.units.first { $0.name == name })
    }

    @Test func usesTheOffsetsInForceOnTheChosenDate() throws {
        // New York moves its clocks forward on 8 March 2026, London not until 29 March, so in
        // between they are four hours apart instead of five.
        let newYork = try zone("America/New_York")
        let before = clockCategory(at: try date("2026-03-01T17:00:00Z"), local: newYork, extraZoneIDs: [])
        let between = clockCategory(at: try date("2026-03-15T17:00:00Z"), local: newYork, extraZoneIDs: [])

        let nine = 9.0
        #expect(try unit("Local time", in: before).convert(nine, to: unit("London", in: before)) == 14)
        #expect(try unit("Local time", in: between).convert(nine, to: unit("London", in: between)) == 13)
    }

    @Test func getsTheHourOfTheSwitchItselfRight() throws {
        // London springs forward at 01:00 UTC on 29 March 2026: 00:30 is still GMT, 03:00 is BST.
        let london = try zone("Europe/London")
        let clock = clockCategory(at: try date("2026-03-29T12:00:00Z"), local: london, extraZoneIDs: [])
        let local = try unit("Local time", in: clock)
        let utc = try unit("UTC", in: clock)
        #expect(format.format(local.convert(0.5, to: utc)) == "00:30")
        #expect(format.format(local.convert(3, to: utc)) == "02:00")
        #expect(format.format(utc.convert(2, to: local)) == "03:00")
    }

    @Test func showsTheOffsetForTheChosenDate() throws {
        let newYork = try zone("America/New_York")
        let winter = clockCategory(at: try date("2026-01-15T17:00:00Z"), local: newYork, extraZoneIDs: [])
        let summer = clockCategory(at: try date("2026-07-15T17:00:00Z"), local: newYork, extraZoneIDs: [])
        #expect(try unit("London", in: winter).symbol == "UTC")
        #expect(try unit("London", in: summer).symbol == "UTC+01:00")
    }

    @Test func carriesTimesPastMidnightAcrossTheDateLine() throws {
        let newYork = try zone("America/New_York")
        let clock = clockCategory(at: try date("2026-01-15T17:00:00Z"), local: newYork, extraZoneIDs: [])
        // 20:00 in New York (UTC-5) is 10:00 the next morning in Tokyo (UTC+9).
        let tokyo = try unit("Local time", in: clock).convert(20, to: unit("Tokyo", in: clock))
        #expect(format.format(tokyo) == "10:00 +1d")
        // And back again.
        #expect(try unit("Tokyo", in: clock).convert(tokyo, to: unit("Local time", in: clock)) == 20)
    }
}

@MainActor
struct ClockCitiesTests {

    private let defaults: UserDefaults

    init() throws {
        let suite = "ClockCitiesTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func savesAddedCitiesOnceAndRemovesThem() {
        ClockCities.add("America/Denver", in: defaults)
        ClockCities.add("America/Denver", in: defaults)
        ClockCities.add("Not/A_Zone", in: defaults)
        #expect(ClockCities.saved(in: defaults) == ["America/Denver"])
        ClockCities.remove("America/Denver", in: defaults)
        #expect(ClockCities.saved(in: defaults).isEmpty)
    }

    @Test func listsAddedCitiesInOffsetOrder() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let clock = clockCategory(local: newYork, extraZoneIDs: ["America/Denver", "Asia/Kathmandu"])
        let names = clock.units.dropFirst().map(\.name)
        let denver = try #require(names.firstIndex(of: "Denver"))
        let chicago = try #require(names.firstIndex(of: "Chicago"))
        let kathmandu = try #require(names.firstIndex(of: "Kathmandu"))
        let kolkata = try #require(names.firstIndex(of: "Kolkata"))
        #expect(denver < chicago)
        #expect(kolkata < kathmandu)
    }

    @Test func showsAnAddedCityEvenIfItKeepsTheDevicesTime() throws {
        // Toronto keeps New York's time, so it would never be listed by default.
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let clock = clockCategory(local: newYork, extraZoneIDs: ["America/Toronto"])
        #expect(clock.units.contains { $0.name == "Toronto" })
    }

    @Test func doesntRepeatABuiltInCity() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let clock = clockCategory(local: newYork, extraZoneIDs: ["Asia/Tokyo"])
        #expect(clock.units.filter { $0.name == "Tokyo" }.count == 1)
    }
}

/// The Clock converter screen's date and city controls.
@MainActor
struct ClockConverterTests {

    private let defaults: UserDefaults

    init() throws {
        let suite = "ClockConverterTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    private func model() throws -> ConverterModel {
        try #require(ConverterModel(categoryID: clockID, defaults: defaults, locale: .usEnglish))
    }

    private func row(_ model: ConverterModel, _ name: String) throws -> Int {
        try #require(model.category.units.firstIndex { $0.name == name })
    }

    /// Hours from Tokyo to Sydney for 12:00 typed in Tokyo — 2 in January (Sydney on summer
    /// time), 1 in July. Neither city is likely to be the test machine's own zone.
    private func sydneyMinusTokyo(_ model: ConverterModel) throws -> Double {
        model.userEdited(row: try row(model, "Tokyo"), text: "12:00")
        let sydney = try #require(ClockFormat().parse(model.texts[try row(model, "Sydney")]))
        return sydney - 12
    }

    @Test func picksUpDaylightSavingForTheChosenDate() throws {
        let model = try model()
        #expect(model.hasDate)
        model.setDate(try #require(ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")))
        #expect(try sydneyMinusTokyo(model) == 2)
        model.setDate(try #require(ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")))
        #expect(try sydneyMinusTokyo(model) == 1)
    }

    @Test func addsAndRemovesACityKeepingWhatWasTyped() throws {
        let model = try model()
        let tokyo = try row(model, "Tokyo")
        model.userEdited(row: tokyo, text: "12:00")

        model.addCity("Asia/Kathmandu")
        let kathmandu = try row(model, "Kathmandu")
        #expect(model.isAddedCity(kathmandu))
        #expect(model.texts[try row(model, "Tokyo")] == "12:00")
        #expect(model.texts[kathmandu] == "08:45") // UTC+05:45, all year
        #expect(!model.shownZoneIDs.isDisjoint(with: ["Asia/Kathmandu"]))

        model.removeCity(inRow: kathmandu)
        #expect(!model.category.units.contains { $0.name == "Kathmandu" })
        #expect(model.texts[try row(model, "Tokyo")] == "12:00")
    }

    @Test func onlyAddedCitiesCanBeRemoved() throws {
        let model = try model()
        let tokyo = try row(model, "Tokyo")
        #expect(!model.isAddedCity(tokyo))
        model.removeCity(inRow: tokyo)
        #expect(model.category.units.contains { $0.name == "Tokyo" })
    }

    @Test func sharesTheDate() throws {
        let model = try model()
        model.setDate(try #require(ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")))
        model.userEdited(row: try row(model, "Tokyo"), text: "12:00")
        let lines = try #require(model.shareText).split(separator: "\n")
        #expect(lines[1] == "Date: Jul 15, 2026")
    }

    @Test func otherCategoriesHaveNoDate() throws {
        let model = try #require(ConverterModel(categoryID: "length", defaults: defaults))
        #expect(!model.hasDate)
    }
}
