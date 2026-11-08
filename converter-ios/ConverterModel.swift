import Foundation
import Observation

/// State behind the converter screen. Every unit row has its own text; typing into any row
/// converts that value and rewrites every other row.
@Observable
final class ConverterModel {

    /// Decimal-place options offered in the menu; nil means format adaptively.
    static let decimalChoices: [Int?] = [nil, 0, 1, 2, 3, 4, 6]

    /// The category being shown. For a category with a `CategoryParam` this is swapped for a
    /// rebuilt variant whenever the user changes the parameter, so rows are looked up by index.
    private(set) var category: Category

    /// The text shown in each unit row, parallel to `category.units`.
    private(set) var texts: [String]

    /// Text of the parameter field (e.g. hours per week), when the category has one.
    private(set) var paramText = ""

    /// Shown under the parameter field when its text isn't a usable value.
    private(set) var paramError: String?

    /// Decimal places results are shown to; nil formats adaptively.
    private(set) var decimals: Int?

    /// Last row the user typed into, so conversions can be redriven when settings change.
    private var lastEdited: Int?

    private let defaults: UserDefaults

    /// Whose conventions numbers are read and shown in — "1,5" in Germany, "1.5" in the US.
    private let locale: Locale

    init?(categoryID: String, defaults: UserDefaults = .standard, locale: Locale = .autoupdatingCurrent) {
        guard let base = UnitsRepository.category(id: categoryID) else { return nil }
        self.defaults = defaults
        self.locale = locale
        var category = base
        // Reopen with whatever parameter value was last used, not the built-in default.
        if let param = base.param {
            let value = Self.savedParamValue(base.id, param, defaults)
            category = param.variantFor(value)
            paramText = UnitsRepository.format(value, locale: locale)
        }
        self.category = category
        texts = Array(repeating: "", count: category.units.count)
        decimals = Self.savedDecimals(category, defaults)
        fillInitialValue()
    }

    // MARK: Editing

    /// Store what the user typed into `row` and recompute every other row from it.
    func userEdited(row: Int, text: String) {
        texts[row] = text
        lastEdited = row
        recompute(from: row)
    }

    /// Rebuild the category around a new parameter value and refresh the note and conversions.
    func paramEdited(_ text: String) {
        paramText = text
        guard let param = category.param else { return }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = UnitsRepository.parse(trimmed, locale: locale), param.range.contains(value) else {
            // Keep the last usable setting, but say why a nonsense entry had no effect.
            let low = UnitsRepository.format(param.range.lowerBound, locale: locale)
            let high = UnitsRepository.format(param.range.upperBound, locale: locale)
            paramError = trimmed.isEmpty ? nil : "Enter \(low)–\(high)"
            return
        }
        paramError = nil
        category = param.variantFor(value)
        defaults.set(String(value), forKey: Keys.param + category.id)
        if let lastEdited { recompute(from: lastEdited) }
    }

    /// Let the user override how many decimal places this category's results are shown to.
    func setDecimals(_ value: Int?) {
        decimals = value
        // "auto" is stored as a non-numeric marker so it stays distinct from the
        // category's own default, which applies only while nothing has been chosen.
        defaults.set(value.map(String.init) ?? Keys.auto, forKey: Keys.decimals + category.id)
        if let lastEdited { recompute(from: lastEdited) }
    }

    /// Placeholder for an empty row — "00:00" for Clock, "0" otherwise.
    var placeholder: String {
        category.valueFormat?.format(0) ?? "0"
    }

    /// Fill in the value the screen opens on: the one the category names, where it has one (Clock
    /// opens on the current time), and otherwise the value last typed here, so that coming back
    /// resumes where the user left off.
    func fillInitialValue() {
        if let opening = category.openingValue, !texts.isEmpty {
            userEdited(row: 0, text: formatValue(opening()))
            return
        }
        guard let value = defaults.string(forKey: Keys.value + category.id), !value.isEmpty,
              defaults.object(forKey: Keys.unit + category.id) != nil else { return }
        let row = defaults.integer(forKey: Keys.unit + category.id)
        guard texts.indices.contains(row) else { return }
        userEdited(row: row, text: value)
    }

    /// Remember the last typed value so the screen resumes there next time.
    func save() {
        // A category that opens on a value of its own (Clock, on the current time) would only
        // ever restore a stale one, so there is nothing here worth saving.
        guard category.openingValue == nil, let lastEdited else { return }
        defaults.set(lastEdited, forKey: Keys.unit + category.id)
        defaults.set(texts[lastEdited], forKey: Keys.value + category.id)
    }

    // MARK: Conversion

    private func recompute(from source: Int) {
        let value = parseValue(texts[source].trimmingCharacters(in: .whitespaces))
        let sourceUnit = category.units[source]
        for row in texts.indices where row != source {
            texts[row] = value.map { formatValue(sourceUnit.convert($0, to: category.units[row])) } ?? ""
        }
    }

    /// Read a field the way this category writes values — Clock's "14:30", say, rather than 14.5.
    private func parseValue(_ text: String) -> Double? {
        if let format = category.valueFormat { return format.parse(text) }
        return UnitsRepository.parse(text, locale: locale)
    }

    /// Render a converted value the way this category writes values.
    private func formatValue(_ value: Double) -> String {
        category.valueFormat?.format(value) ?? UnitsRepository.format(value, decimals: decimals, locale: locale)
    }

    // MARK: Persistence

    private enum Keys {
        static let param = "param:"
        static let value = "value:"
        static let unit = "unit:"
        static let decimals = "decimals:"
        static let auto = "auto"
    }

    /// The chosen decimal places for this category, falling back to the category's own default.
    private static func savedDecimals(_ category: Category, _ defaults: UserDefaults) -> Int? {
        guard let saved = defaults.string(forKey: Keys.decimals + category.id) else { return category.decimals }
        return Int(saved)
    }

    /// The parameter value last entered for `categoryID`, or the parameter's default.
    private static func savedParamValue(_ categoryID: String, _ param: CategoryParam, _ defaults: UserDefaults) -> Double {
        if let saved = defaults.string(forKey: Keys.param + categoryID).flatMap(Double.init),
           param.range.contains(saved) {
            return saved
        }
        return param.defaultValue
    }
}
