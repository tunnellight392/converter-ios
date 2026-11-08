import Foundation
import Testing
@testable import converter_ios

/// The text behind Copy All and Share.
@MainActor
struct ShareTextTests {

    private let defaults: UserDefaults

    init() throws {
        let suite = "ShareTextTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    private func model(_ id: String, pair: UnitPair? = nil) throws -> ConverterModel {
        try #require(ConverterModel(categoryID: id, pair: pair, defaults: defaults, locale: .usEnglish))
    }

    @Test func isNilUntilSomethingIsTyped() throws {
        let model = try model("temperature")
        #expect(model.shareText == nil)
        model.userEdited(row: 0, text: "")
        #expect(model.shareText == nil)
        model.userEdited(row: 0, text: "abc") // unreadable: nothing converted
        #expect(model.shareText == nil)
    }

    @Test func listsTheTypedValueFirstThenTheRest() throws {
        let model = try model("temperature")
        model.userEdited(row: 1, text: "212") // Fahrenheit
        #expect(model.shareText == """
            Temperature
            Fahrenheit: 212 °F
            Celsius: 100 °C
            Kelvin: 373.15 K
            """)
    }

    @Test func sharesWhatMathWorkedOutTo() throws {
        let model = try model("temperature")
        model.userEdited(row: 0, text: "50*2") // Celsius
        let lines = try #require(model.shareText).split(separator: "\n")
        #expect(lines[1] == "Celsius: 100 °C")
    }

    @Test func includesTheWorkWeekForPay() throws {
        let model = try model("pay")
        model.userEdited(row: 0, text: "20") // Hourly
        #expect(model.shareText == """
            Pay
            Hours worked per week: 40
            Hourly: 20 /hr
            Monthly: 3466.67 /mo
            Yearly: 41600.00 /yr
            """)
    }

    @Test func writesUnitsNamedByTheirSymbolOnce() throws {
        let model = try model("shoe_men")
        model.userEdited(row: 0, text: "9") // US
        let lines = try #require(model.shareText).split(separator: "\n")
        #expect(lines[1] == "US 9")
        #expect(lines[2] == "UK 8.5")
    }

    @Test func followsAPinnedPairsOrder() throws {
        let pair = UnitPair(categoryID: "length", fromUnitID: "Mile|mi", toUnitID: "Kilometer|km")
        let model = try model("length", pair: pair)
        model.userEdited(row: model.displayOrder[0], text: "1")
        let lines = try #require(model.shareText).split(separator: "\n")
        #expect(lines[1] == "Mile: 1 mi")
        #expect(lines[2] == "Kilometer: 1.609344 km")
    }
}
