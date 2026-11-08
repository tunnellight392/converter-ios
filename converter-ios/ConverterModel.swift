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
    private(set) var lastEdited: Int?

    /// When the row being typed in holds math rather than a plain number, what it worked out
    /// to — shown under that row as "= 36".
    private(set) var calculation: (row: Int, result: String)?

    /// The pinned conversion the screen was opened from, if any. Its two units lead the list.
    let pair: UnitPair?

    /// Unit indices in the order the rows are shown: a pinned pair's units first, then the rest.
    let displayOrder: [Int]

    /// Index of the pinned pair's "from" unit — the row to start typing in.
    var pairFromIndex: Int? { pair == nil ? nil : displayOrder.first }

    private let defaults: UserDefaults

    /// Whose conventions numbers are read and shown in — "1,5" in Germany, "1.5" in the US.
    private let locale: Locale

    init?(
        categoryID: String,
        pair: UnitPair? = nil,
        defaults: UserDefaults = .standard,
        locale: Locale = .autoupdatingCurrent
    ) {
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
        // A pair whose units can't be found (say, a Clock city no longer listed) opens the
        // category in its usual order.
        let all = Array(category.units.indices)
        if let pair,
           let from = category.units.firstIndex(where: { $0.id == pair.fromUnitID }),
           let to = category.units.firstIndex(where: { $0.id == pair.toUnitID }), from != to {
            self.pair = pair
            displayOrder = [from, to] + all.filter { $0 != from && $0 != to }
        } else {
            self.pair = nil
            displayOrder = all
        }
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
        let parsed = UnitsRepository.parse(trimmed, locale: locale) ?? Calculator.evaluate(trimmed, locale: locale)
        guard let value = parsed, param.range.contains(value) else {
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

    /// The whole conversion as plain text, for Copy All and Share: the category, any setting it
    /// depends on, then every unit with a value — the one typed in first, the rest in screen
    /// order. Nil while there's nothing to share.
    var shareText: String? {
        guard let source = lastEdited, texts.indices.contains(source) else { return nil }
        let typed = texts[source].trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty, !texts.enumerated().allSatisfy({ $0.offset == source || $0.element.isEmpty }) else {
            return nil
        }
        var lines = [category.name]
        if let param = category.param, !paramText.isEmpty, paramError == nil {
            lines.append("\(param.label): \(paramText)")
        }
        // Math is shared as what it worked out to, not as "12*3".
        let sourceValue = calculation.flatMap { $0.row == source ? String($0.result.dropFirst(2)) : nil } ?? typed
        let order = [source] + displayOrder.filter { $0 != source }
        for row in order {
            let value = row == source ? sourceValue : texts[row]
            guard !value.isEmpty else { continue }
            lines.append(Self.line(for: category.units[row], value: value, plain: category.valueFormat == nil))
        }
        return lines.joined(separator: "\n")
    }

    /// "Kilometer: 1.5 km", "US 9" (where the name is the symbol), or "Tokyo: 14:30" for Clock.
    private static func line(for unit: ConvUnit, value: String, plain: Bool) -> String {
        if unit.name == unit.symbol { return "\(unit.name) \(value)" }
        return plain ? "\(unit.name): \(value) \(unit.symbol)" : "\(unit.name): \(value)"
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
        let text = texts[source].trimmingCharacters(in: .whitespaces)
        let value = parseValue(text, row: source)
        let sourceUnit = category.units[source]
        for row in texts.indices where row != source {
            texts[row] = value.map { formatValue(sourceUnit.convert($0, to: category.units[row])) } ?? ""
        }
        // Show what typed math worked out to ("12*3" → "= 36"); a plain number needs no echo.
        if let value, category.valueFormat == nil, UnitsRepository.parse(text, locale: locale) == nil {
            calculation = (source, "= " + formatValue(value))
        } else {
            calculation = nil
        }
    }

    /// Read a field the way this category writes values — Clock's "14:30", say, rather than 14.5
    /// — falling back to feet and inches ("5'11\"") and arithmetic ("12*3", "1 1/2").
    private func parseValue(_ text: String, row: Int) -> Double? {
        if let format = category.valueFormat { return format.parse(text) }
        if let value = UnitsRepository.parse(text, locale: locale) { return value }
        if let value = feetAndInches(text, in: row) { return value }
        return Calculator.evaluate(text, locale: locale)
    }

    /// `text` read as feet and inches, in the unit of `row` — for categories that have foot and
    /// inch units (Length, collar sizes).
    private func feetAndInches(_ text: String, in row: Int) -> Double? {
        guard let parsed = FeetAndInches.parse(text, locale: locale) else { return nil }
        let foot = category.units.first { $0.symbol == "ft" }
        let inch = category.units.first { $0.symbol == "in" }
        // Every part that was typed needs its unit in this category.
        if parsed.feet != 0 && foot == nil || parsed.inches != 0 && inch == nil { return nil }
        let base = (foot?.toBase(parsed.feet) ?? 0) + (inch?.toBase(parsed.inches) ?? 0)
        return category.units[row].fromBase(base)
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
