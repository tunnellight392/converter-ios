import Foundation
import Testing
@testable import converter_ios

/// The converter screen's state: typing in one row fills the others, and settings persist.
/// Each test gets its own throwaway defaults suite so nothing leaks between tests or into the app.
@MainActor
struct ConverterModelTests {

    private let defaults: UserDefaults

    init() throws {
        let suite = "ConverterModelTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    private func model(_ id: String, locale: Locale = .usEnglish) throws -> ConverterModel {
        try #require(ConverterModel(categoryID: id, defaults: defaults, locale: locale))
    }

    @Test func unknownCategoryHasNoModel() {
        #expect(ConverterModel(categoryID: "nope", defaults: defaults) == nil)
    }

    @Test func typingInOneRowFillsTheOthers() throws {
        let model = try model("length")
        model.userEdited(row: 1, text: "1") // Kilometer
        #expect(model.texts[0] == "1000") // Meter
        #expect(model.texts[2] == "100000") // Centimeter
        #expect(model.texts[1] == "1", "the row being typed in is left alone")
    }

    @Test func unreadableTextClearsTheOtherRows() throws {
        let model = try model("length")
        model.userEdited(row: 0, text: "5")
        model.userEdited(row: 0, text: "abc")
        let othersEmpty = model.texts.dropFirst().allSatisfy(\.isEmpty)
        #expect(othersEmpty)
    }

    @Test func decimalPlacesApplyAndPersist() throws {
        let model = try model("length")
        model.userEdited(row: 0, text: "1") // Meter
        model.setDecimals(2)
        #expect(model.texts[5] == "0.00") // Mile
        // Reopening the category keeps the choice.
        let reopened = try self.model("length")
        #expect(reopened.decimals == 2)
    }

    @Test func payDefaultsToTwoDecimalPlaces() throws {
        let model = try model("pay")
        model.userEdited(row: 0, text: "20") // Hourly
        #expect(model.texts[2] == "41600.00") // Yearly
    }

    @Test func changingTheWorkWeekRedrivesTheLastEdit() throws {
        let model = try model("pay")
        model.userEdited(row: 0, text: "20")
        model.paramEdited("37.5")
        #expect(model.texts[2] == "39000.00")
        #expect(model.category.note?.contains("37.5-hour") == true)
        let reopened = try self.model("pay")
        #expect(reopened.paramText == "37.5", "the work week is remembered")
    }

    @Test func outOfRangeWorkWeekIsRejected() throws {
        let model = try model("pay")
        model.userEdited(row: 0, text: "20")
        model.paramEdited("500")
        #expect(model.paramError != nil)
        #expect(model.texts[2] == "41600.00", "the last usable setting stays in effect")
    }

    @Test func resumesTheLastTypedValue() throws {
        let first = try model("mass")
        first.userEdited(row: 4, text: "10") // Pound
        first.save()

        let reopened = try model("mass")
        #expect(reopened.texts[4] == "10")
        #expect(reopened.texts[0] == "4.5359237") // Kilogram
    }

    @Test func clockOpensOnTheCurrentTime() throws {
        let model = try model("clock")
        #expect(ClockFormat().parse(model.texts[0]) != nil)
        let allFilled = model.texts.allSatisfy { !$0.isEmpty }
        #expect(allFilled)
    }
}
