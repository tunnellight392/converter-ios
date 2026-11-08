import Foundation
import Testing
@testable import converter_ios

extension Locale {
    static let usEnglish = Locale(identifier: "en_US")
    static let german = Locale(identifier: "de_DE")
    static let french = Locale(identifier: "fr_FR")
}

/// Numbers are typed and shown in the user's own conventions: "1,5" in Germany and France,
/// "1.5" in the US — while the forms everyone uses keep working everywhere.
@MainActor
struct LocaleNumberTests {

    @Test(arguments: [
        ("1.5", 1.5),
        ("-40", -40.0),
        (".5", 0.5),
        ("1,500", 1500.0), // US grouping
        ("1,234.5", 1234.5),
        ("1,5", 1.5), // a comma with one digit after can only be a decimal
        ("1.", 1.0), // half-typed
        ("1e3", 1000.0)
    ])
    func readsUSNumbers(text: String, expected: Double) {
        #expect(UnitsRepository.parse(text, locale: .usEnglish) == expected)
    }

    @Test(arguments: [
        ("1,5", 1.5),
        ("-1,5", -1.5),
        ("1.500", 1500.0), // German grouping
        ("1.234,5", 1234.5),
        ("1.234.567", 1234567.0),
        ("1.5", 1.5), // a period still works as a decimal
        ("1,", 1.0), // half-typed
        ("1,5e3", 1500.0)
    ])
    func readsGermanNumbers(text: String, expected: Double) {
        #expect(UnitsRepository.parse(text, locale: .german) == expected)
    }

    @Test(arguments: [
        ("1 234,5", 1234.5), // regular space
        ("1\u{202F}234,5", 1234.5), // narrow no-break space, as iOS writes French grouping
        ("\u{2212}3,25", -3.25) // typographic minus
    ])
    func readsFrenchNumbers(text: String, expected: Double) {
        #expect(UnitsRepository.parse(text, locale: .french) == expected)
    }

    @Test(arguments: ["", " ", "-", "abc", "1.2,3.4", "inf", "nan", "0x10", "1,2a"])
    func refusesTextThatIsNotANumber(text: String) {
        #expect(UnitsRepository.parse(text, locale: .german) == nil)
        #expect(UnitsRepository.parse(text, locale: .usEnglish) == nil)
    }

    @Test func showsResultsWithTheLocaleDecimalSeparator() {
        #expect(UnitsRepository.format(1.5, locale: .german) == "1,5")
        #expect(UnitsRepository.format(1.5, locale: .usEnglish) == "1.5")
        #expect(UnitsRepository.format(8666.666666, decimals: 2, locale: .french) == "8666,67")
        #expect(UnitsRepository.format(1e15, locale: .german) == "1,000000E+15")
    }

    @Test func neverGroupsDigitsInResults() {
        #expect(UnitsRepository.format(1234567.5, locale: .german) == "1234567,5")
        #expect(UnitsRepository.format(1234567.5, locale: .usEnglish) == "1234567.5")
    }

    @Test(arguments: [Locale.usEnglish, .german, .french])
    func readsBackWhatItShows(locale: Locale) throws {
        for value in [0.0, 1.5, -40, 1234.5678, 0.000123, 2.5e13] {
            let shown = UnitsRepository.format(value, locale: locale)
            let read = try #require(UnitsRepository.parse(shown, locale: locale))
            #expect(abs(read - value) <= abs(value) * 1e-9, "\(shown) in \(locale.identifier)")
        }
    }
}

/// The converter screen in a comma-decimal locale.
@MainActor
struct GermanConverterTests {

    private let defaults: UserDefaults

    init() throws {
        let suite = "GermanConverterTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    private func model(_ id: String) throws -> ConverterModel {
        try #require(ConverterModel(categoryID: id, defaults: defaults, locale: .german))
    }

    @Test func convertsACommaDecimal() throws {
        let model = try model("length")
        model.userEdited(row: 1, text: "1,5") // Kilometer
        #expect(model.texts[0] == "1500") // Meter
        #expect(model.texts[2] == "150000") // Centimeter
        #expect(model.texts[3] == "1500000") // Millimeter
    }

    @Test func showsResultsWithACommaDecimal() throws {
        let model = try model("temperature")
        model.userEdited(row: 1, text: "100") // Fahrenheit
        #expect(model.texts[0] == "37,77777778") // Celsius
    }

    @Test func readsTheWorkWeekWithACommaDecimal() throws {
        let model = try model("pay")
        #expect(model.paramText == "40")
        model.userEdited(row: 0, text: "20") // Hourly
        model.paramEdited("37,5")
        #expect(model.paramError == nil)
        #expect(model.texts[2] == "39000,00") // Yearly
    }

    @Test func rangeErrorUsesTheLocale() throws {
        let model = try model("pay")
        model.paramEdited("0,5")
        #expect(model.paramError == "Enter 1–168")
    }
}
