import Foundation
import Testing
@testable import converter_ios

/// Arithmetic typed into a value field.
@MainActor
struct CalculatorTests {

    /// Typed text and what it should work out to, in a US locale.
    private static let expressions: [(String, Double)] = [
        ("12*3", 36),
        ("2+3*4", 14),
        ("(2+3)/4", 1.25),
        ("-(2+3)", -5),
        ("10÷4", 2.5),
        ("3×4", 12),
        ("2−1", 1),
        ("1.5e3/2", 750),
        ("1,000*2", 2000),
        // Recipe fractions.
        ("1/2", 0.5),
        ("1 1/2", 1.5),
        ("1½", 1.5),
        ("2 ¾", 2.75),
        ("½*3", 1.5),
        // Half-typed: a trailing operator or open parenthesis is ignored.
        ("12*", 12),
        ("3+(", 3),
        ("(2+3", 5)
    ]

    @Test(arguments: expressions)
    func evaluates(text: String, expected: Double) throws {
        let value = try #require(Calculator.evaluate(text, locale: .usEnglish))
        #expect(abs(value - expected) < 1e-9)
    }

    @Test func readsDecimalCommasInsideExpressions() {
        #expect(Calculator.evaluate("1,5*2", locale: .german) == 3)
        #expect(Calculator.evaluate("2,5+2,5", locale: .german) == 5)
    }

    @Test(arguments: ["", "abc", "1/0", "2**3", "()", ")", "12*3x", "-"])
    func refusesWhatIsntArithmetic(text: String) {
        #expect(Calculator.evaluate(text, locale: .usEnglish) == nil)
    }
}

/// Feet-and-inches notation.
@MainActor
struct FeetAndInchesTests {

    private static let heights: [(String, Double, Double)] = [
        ("5'11\"", 5, 11),
        ("5' 11\"", 5, 11),
        ("5 ft 11 in", 5, 11),
        ("5ft11in", 5, 11),
        ("6'", 6, 0),
        ("11\"", 0, 11),
        ("5''", 0, 5), // two apostrophes for inches
        ("5’11”", 5, 11), // iOS smart quotes
        ("5′11″", 5, 11), // prime marks
        ("5'11.5\"", 5, 11.5)
    ]

    @Test(arguments: heights)
    func reads(text: String, feet: Double, inches: Double) throws {
        let parsed = try #require(FeetAndInches.parse(text, locale: .usEnglish))
        #expect(parsed.feet == feet)
        #expect(parsed.inches == inches)
    }

    @Test func readsADecimalCommaInches() throws {
        let parsed = try #require(FeetAndInches.parse("5'11,5\"", locale: .german))
        #expect(parsed.inches == 11.5)
    }

    @Test(arguments: ["5", "abc", "5'11'", "\"", "'"])
    func refusesWhatIsntFeetAndInches(text: String) {
        #expect(FeetAndInches.parse(text, locale: .usEnglish) == nil)
    }
}

/// Math and feet-and-inches in the converter itself.
@MainActor
struct ConverterMathTests {

    private let defaults: UserDefaults

    init() throws {
        let suite = "ConverterMathTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    private func model(_ id: String, locale: Locale = .usEnglish) throws -> ConverterModel {
        try #require(ConverterModel(categoryID: id, defaults: defaults, locale: locale))
    }

    private func row(_ model: ConverterModel, _ name: String) throws -> Int {
        try #require(model.category.units.firstIndex { $0.name == name })
    }

    @Test func convertsAnExpressionAndShowsWhatItCameTo() throws {
        let model = try model("volume")
        let cup = try row(model, "US cup")
        model.userEdited(row: cup, text: "12*3")
        #expect(model.texts[try row(model, "Liter")] == "8.517176514")
        #expect(model.calculation?.row == cup)
        #expect(model.calculation?.result == "= 36")
    }

    @Test func plainNumbersShowNoCalculation() throws {
        let model = try model("volume")
        model.userEdited(row: 0, text: "2")
        #expect(model.calculation == nil)
    }

    @Test func readsAHeightInAnyLengthRow() throws {
        let model = try model("length")
        let centimeter = try row(model, "Centimeter")
        model.userEdited(row: centimeter, text: "5'11\"")
        // 5'11" is 71 inches, 180.34 cm — typed into the centimeter row it means 180.34 cm.
        #expect(model.texts[try row(model, "Inch")] == "71")
        #expect(model.texts[try row(model, "Meter")] == "1.8034")
        #expect(model.calculation?.result == "= 180.34")
    }

    @Test func readsAHeightInTheFootRow() throws {
        let model = try model("length")
        model.userEdited(row: try row(model, "Foot"), text: "5'6\"")
        #expect(model.calculation?.result == "= 5.5")
        #expect(model.texts[try row(model, "Inch")] == "66")
    }

    @Test func readsInchesInACollarSize() throws {
        let model = try model("shirt_men")
        model.userEdited(row: 1, text: "15.5\"") // Collar EU, in cm
        #expect(model.texts[0] == "15.5") // Collar US/UK, in inches
    }

    @Test func ignoresFeetWhereTheCategoryHasNoFootUnit() throws {
        let model = try model("mass")
        model.userEdited(row: 0, text: "5'")
        #expect(model.texts.dropFirst().allSatisfy(\.isEmpty))
        #expect(model.calculation == nil)
    }

    @Test func acceptsMathInTheWorkWeek() throws {
        let model = try model("pay")
        model.userEdited(row: 0, text: "20")
        model.paramEdited("35+2.5")
        #expect(model.paramError == nil)
        #expect(model.texts[2] == "39000.00")
    }

    @Test func leavesClockTimesAlone() throws {
        let model = try model("clock")
        model.userEdited(row: 0, text: "9:30")
        #expect(model.calculation == nil)
        #expect(model.texts.dropFirst().allSatisfy { !$0.isEmpty })
    }
}
