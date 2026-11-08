import Foundation

/// A single unit of measure. Conversions go through a per-category "base" unit:
/// any value is first mapped to the base via `toBase`, then to the target via `fromBase`.
/// Using closures (rather than a single multiplier) lets us support affine conversions
/// such as temperature, where Fahrenheit/Celsius/Kelvin differ by an offset, not just a factor.
struct ConvUnit {
    let name: String
    let symbol: String
    let toBase: (Double) -> Double
    let fromBase: (Double) -> Double
    /// When set, results displayed in this unit are rounded to the nearest multiple of this
    /// increment (e.g. 0.5 to snap shoe sizes to half sizes). Nil means show full precision.
    var snap: Double? = nil

    /// Convert `value`, expressed in this unit, into `target`, snapped to `target`'s increment if any.
    func convert(_ value: Double, to target: ConvUnit) -> Double {
        let result = target.fromBase(toBase(value))
        guard let snap = target.snap else { return result }
        // Half-up rounding, matching Java's Math.round.
        return (result / snap + 0.5).rounded(.down) * snap
    }
}

/// A group of related units shown as a tile on the home screen.
struct Category: Identifiable {
    let id: String
    let name: String
    let emoji: String
    let colorHex: String
    let units: [ConvUnit]
    /// Optional caveat shown at the top of the converter screen.
    var note: String? = nil
    /// Set when the category's conversions depend on a number the user can adjust.
    var param: CategoryParam? = nil
    /// Decimal places results are shown to, for categories where a fixed scale reads better
    /// than significant digits (money, for instance). Nil formats adaptively. The user can
    /// override this per category on the converter screen.
    var decimals: Int? = nil
    /// How this category's values are written into the fields and read back out. Nil formats
    /// them as plain numbers; Clock supplies one so its rows read "14:30" and not "14.5".
    var valueFormat: ValueFormat? = nil
    /// Value the first unit's field opens on, in that unit's own scale, in place of whatever the
    /// user last typed. Clock uses it to open on the current time.
    var openingValue: (() -> Double)? = nil
}

/// A number the user can change that the category's conversions depend on — currently only the
/// Pay category's hours worked per week. The converter screen shows it as an extra field above
/// the unit rows and swaps in `variantFor`'s category (new units, new note) as the value changes.
struct CategoryParam {
    /// Label for the input, e.g. "Hours worked per week".
    let label: String
    /// Smaller caption under the label, in the same spot as a unit's symbol.
    let caption: String
    let defaultValue: Double
    /// Values outside this range are ignored, so the last usable setting stays in effect.
    let range: ClosedRange<Double>
    /// Rebuilds the whole category for a new value of this parameter.
    let variantFor: (Double) -> Category
}

// MARK: - Shoe and shirt sizes

/// Shoe-size constants. Both shoe categories use foot length in millimeters as their base
/// (effectively the Mondopoint standard). A men's US 9 corresponds to roughly a 270 mm foot,
/// and each full size step is one barleycorn (1/3 inch). US/UK are affine in foot length;
/// EU (Paris point) uses EU ≈ 0.15·mm + 2. UK and EU are unisex by foot length.
private let shoeAnchorMM = 270.0
private let barleycornMM = 25.4 / 3.0

/// Build a shoe-size unit that is affine in foot length: `anchorSize` maps to the anchor foot.
private func shoeBarleycorn(_ name: String, _ symbol: String, anchorSize: Double) -> ConvUnit {
    ConvUnit(
        name: name,
        symbol: symbol,
        toBase: { shoeAnchorMM + ($0 - anchorSize) * barleycornMM },
        fromBase: { anchorSize + ($0 - shoeAnchorMM) / barleycornMM },
        snap: 0.5
    )
}

/// EU (Paris-point) shoe size, unisex: EU ≈ 0.15·(foot mm) + 2.
private func shoeEu() -> ConvUnit {
    ConvUnit(
        name: "EU", symbol: "EU",
        toBase: { ($0 - 2.0) / 0.15 },
        fromBase: { 0.15 * $0 + 2.0 },
        snap: 0.5
    )
}

/// Women's tops are sized by bust circumference, but the ASOS chart is non-linear, so we
/// interpolate over the published table (keyed by UK size). US = UK − 4 and EU = UK + 28.
private let asosUKSizes: [Double] = [4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26]
private let asosBustCM: [Double] = [76, 80, 85, 89, 93, 97, 102, 108, 116, 123, 130, 137]

/// Piecewise-linear lookup of `x` against monotonically increasing `xs`, returning the matching
/// `ys` value. Inputs outside the table are linearly extrapolated using the end segments.
private func piecewise(_ x: Double, _ xs: [Double], _ ys: [Double]) -> Double {
    let last = xs.count - 1
    let i: Int
    if x <= xs[0] {
        i = 0
    } else if x >= xs[last] {
        i = last - 1
    } else {
        i = min(xs.lastIndex { $0 <= x } ?? 0, last - 1)
    }
    let t = (x - xs[i]) / (xs[i + 1] - xs[i])
    return ys[i] + t * (ys[i + 1] - ys[i])
}

/// Build a women's top size unit. `offsetFromUK` is how the system's number differs from the UK
/// size (US = −4, EU = +28); conversions go size → UK → bust (cm) and back via the ASOS table.
private func womensTop(_ name: String, _ symbol: String, offsetFromUK: Double) -> ConvUnit {
    ConvUnit(
        name: name,
        symbol: symbol,
        toBase: { piecewise($0 - offsetFromUK, asosUKSizes, asosBustCM) },
        fromBase: { piecewise($0, asosBustCM, asosUKSizes) + offsetFromUK },
        snap: 2.0
    )
}

/// Build a unit whose conversion to the base is a simple multiply by `factor`, optionally snapped.
private func linear(_ name: String, _ symbol: String, _ factor: Double, snap: Double? = nil) -> ConvUnit {
    ConvUnit(name: name, symbol: symbol, toBase: { $0 * factor }, fromBase: { $0 / factor }, snap: snap)
}

// MARK: - Number formatting

private let posixLocale = Locale(identifier: "en_US_POSIX")

/// Implementation of `UnitsRepository.format`. Mirrors the Android app: ~10 significant digits
/// with trailing zeros trimmed, or a fixed number of places, and scientific notation for very
/// large or small magnitudes. The decimal separator follows `locale` ("1,5" in Germany); there
/// is never any digit grouping, so results stay easy to copy and to type over.
private func formatNumber(_ value: Double, decimals: Int? = nil, locale: Locale = .autoupdatingCurrent) -> String {
    let plain = formatPOSIXNumber(value, decimals: decimals)
    let separator = locale.decimalSeparator ?? "."
    return separator == "." ? plain : plain.replacingOccurrences(of: ".", with: separator)
}

/// `formatNumber` with a "." decimal separator, whatever the locale.
private func formatPOSIXNumber(_ value: Double, decimals: Int?) -> String {
    guard value.isFinite else { return "" }
    let magnitude = abs(value)
    // Outside this window a plain decimal is unreadable however many places are asked for.
    if magnitude != 0, magnitude < 1e-4 || magnitude >= 1e12 {
        return String(format: "%.6E", locale: posixLocale, value)
    }
    // Start from the shortest decimal that round-trips (like Java's BigDecimal.valueOf), so
    // that e.g. 1.005 rounds up to 1.01 rather than suffering binary representation error.
    guard var exact = Decimal(string: "\(value)", locale: posixLocale) else { return "" }
    var rounded = Decimal()
    if let decimals {
        NSDecimalRound(&rounded, &exact, decimals, .plain)
        return rounded.formatted(
            .number.precision(.fractionLength(decimals)).grouping(.never).locale(posixLocale)
        )
    }
    if value == 0 { return "0" }
    // Round to 10 significant digits: the scale is relative to the leading digit's position.
    let scale = 9 - Int(log10(magnitude).rounded(.down))
    NSDecimalRound(&rounded, &exact, scale, .plain)
    // Decimal's description is plain notation with trailing zeros already trimmed.
    return rounded.description
}

/// Implementation of `UnitsRepository.parse`: reads a number the way people in `locale` write
/// one, while still accepting the forms people use everywhere.
///
/// - A comma or a period can be the decimal separator, so "1,5" and "1.5" both read as 1.5.
/// - When both appear, whichever comes last is the decimal separator and the other is grouping:
///   "1.234,5" and "1,234.5" both read as 1234.5.
/// - A lone separator is grouping only when it is the locale's grouping separator and exactly
///   three digits follow it, so "1.500" is 1500 in Germany but "1.5" is 1.5 everywhere.
/// - Spaces and apostrophes (French and Swiss grouping) are ignored, as is a typographic minus.
private func parseNumber(_ text: String, locale: Locale = .autoupdatingCurrent) -> Double? {
    var s = text.trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "\u{2212}", with: "-")
    s.removeAll { " \u{00A0}\u{202F}'’".contains($0) }
    guard !s.isEmpty else { return nil }

    let separators = s.filter { $0 == "." || $0 == "," }
    if let last = s.lastIndex(where: { $0 == "." || $0 == "," }) {
        let decimal = s[last]
        let other: Character = decimal == "." ? "," : "."
        let digitsAfter = s[s.index(after: last)...].prefix { $0.isNumber }.count
        let isGrouping = separators.count > 1 && !separators.contains(other)
            // Several of one kind ("1.234.567") can only be grouping.
            || (separators.count == 1
                && locale.groupingSeparator == String(decimal)
                && locale.decimalSeparator != String(decimal)
                && digitsAfter == 3)
        if isGrouping {
            s.removeAll { $0 == decimal }
        } else {
            // Everything before the last separator of the other kind is grouping.
            s.removeAll { $0 == other }
            s = s.replacingOccurrences(of: String(decimal), with: ".")
            // The decimal separator can't also appear earlier as grouping ("1.2,3.4").
            if s.filter({ $0 == "." }).count > 1 { return nil }
        }
    }
    // Only plain decimal numbers (optionally with an exponent) — Double(_:) would otherwise
    // also accept "inf", "nan" and hexadecimal.
    guard s.allSatisfy({ $0.isASCII && ($0.isNumber || "+-.eE".contains($0)) }),
          let value = Double(s), value.isFinite else { return nil }
    return value
}

// MARK: - Pay

/// Work week the Pay category assumes until the user enters their own hours.
let defaultHoursPerWeek = 40.0
private let weeksPerYear = 52.0

/// Build the Pay category for a given work week. Base unit is yearly pay: hourly ×
/// (hours per week × 52) = yearly, monthly × 12 = yearly.
private func payCategory(hoursPerWeek: Double) -> Category {
    let hoursPerYear = hoursPerWeek * weeksPerYear
    return Category(
        id: "pay", name: "Pay", emoji: "💵", colorHex: "#16A34A",
        units: [
            linear("Hourly", "/hr", hoursPerYear),
            linear("Monthly", "/mo", 12.0),
            linear("Yearly", "/yr", 1.0)
        ],
        note: "Conversions assume a \(formatNumber(hoursPerWeek))-hour work week "
            + "(\(formatNumber(hoursPerYear)) hours per year).",
        param: CategoryParam(
            label: "Hours worked per week",
            caption: "h/week",
            defaultValue: defaultHoursPerWeek,
            range: 1.0...168.0,
            variantFor: { payCategory(hoursPerWeek: $0) }
        ),
        // Pay is money, so two places reads better than ten significant digits.
        decimals: 2
    )
}

// MARK: - Clock

/// Reads and writes a category's field text as something other than a plain number. Only Clock
/// needs one, so that its values read as times of day rather than as decimal hours.
protocol ValueFormat {
    /// Turn field text into a value in the unit's own scale, or nil when it isn't usable.
    func parse(_ text: String) -> Double?
    /// Render a converted value for display.
    func format(_ value: Double) -> String
}

private let minutesPerDay = 1440

/// Clock times. Values are hours, shown as "HH:mm". A conversion that crosses midnight is left to
/// run past the ends of the day — 23:30 in London reaches Tokyo as 32.5 — and the marker "+1d" or
/// "-1d" says which day it landed on. Parsing is lenient: "9", "9:", "9:05", "09:05:30" and
/// "9:05 pm" all read, so a half-typed time doesn't blank out every other row.
struct ClockFormat: ValueFormat {

    func format(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        let minutes = Int((value * 60.0 + 0.5).rounded(.down))
        // Floor division/modulo so negative values land on the previous day.
        let days = Int((Double(minutes) / Double(minutesPerDay)).rounded(.down))
        let inDay = minutes - days * minutesPerDay
        let time = String(format: "%02d:%02d", inDay / 60, inDay % 60)
        if days > 0 { return "\(time) +\(days)d" }
        if days < 0 { return "\(time) \(days)d" }
        return time
    }

    func parse(_ text: String) -> Double? {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces).lowercased())
        var days = 0
        if let match = rest.firstMatch(of: /([+-])\s*(\d+)\s*d$/) {
            days = (Int(match.output.2) ?? 0) * (match.output.1 == "-" ? -1 : 1)
            rest = rest[..<match.range.lowerBound]
            rest = Substring(rest.trimmingCharacters(in: .whitespaces))
        }
        var meridiem: Substring?
        if let match = rest.firstMatch(of: /\s*([ap])\.?m?\.?$/) {
            meridiem = match.output.1
            rest = rest[..<match.range.lowerBound]
            rest = Substring(rest.trimmingCharacters(in: .whitespaces))
        }
        // Hours, then optional minutes and seconds; the empty groups let a trailing ":" through.
        guard let fields = rest.wholeMatch(of: /(\d{1,2})(?::(\d{0,2}))?(?::(\d{0,2}))?/),
              var hours = Int(fields.output.1) else { return nil }
        let minutes = fields.output.2.flatMap { Int($0) } ?? 0
        let seconds = fields.output.3.flatMap { Int($0) } ?? 0
        if minutes > 59 || seconds > 59 { return nil }
        if let meridiem {
            guard (1...12).contains(hours) else { return nil }
            hours = hours % 12 + (meridiem == "p" ? 12 : 0)
        } else if hours > 23 {
            return nil
        }
        return Double(days * 24 + hours) + Double(minutes) / 60.0 + Double(seconds) / 3600.0
    }
}

let clockID = "clock"

/// Cities the Clock category offers beside the device's own zone, as time-zone id to display name.
private let clockZones: [(id: String, name: String)] = [
    ("America/Los_Angeles", "Los Angeles"),
    ("America/Chicago", "Chicago"),
    ("America/New_York", "New York"),
    ("America/Sao_Paulo", "São Paulo"),
    ("UTC", "UTC"),
    ("Europe/London", "London"),
    ("Europe/Paris", "Paris"),
    ("Africa/Johannesburg", "Johannesburg"),
    ("Europe/Moscow", "Moscow"),
    ("Asia/Dubai", "Dubai"),
    ("Asia/Kolkata", "Kolkata"),
    ("Asia/Singapore", "Singapore"),
    ("Asia/Shanghai", "Shanghai"),
    ("Asia/Tokyo", "Tokyo"),
    ("Australia/Sydney", "Sydney"),
    ("Pacific/Auckland", "Auckland")
]

/// A time zone as a Clock unit. The base is hours since midnight UTC, so a zone is only an offset —
/// the one it is on at `date`, which is what puts daylight saving in the right place for today.
private func zoneUnit(_ name: String, zone: TimeZone, at date: Date, city: String? = nil) -> ConvUnit {
    let offsetHours = Double(zone.secondsFromGMT(for: date)) / 3600.0
    let offsetLabel = utcOffsetLabel(offsetHours)
    return ConvUnit(
        name: name,
        symbol: (city == nil || city == offsetLabel) ? offsetLabel : "\(city!) · \(offsetLabel)",
        toBase: { $0 - offsetHours },
        fromBase: { $0 + offsetHours }
    )
}

/// "UTC+05:30", "UTC-08:00", or plain "UTC" on a zero offset.
private func utcOffsetLabel(_ offsetHours: Double) -> String {
    if offsetHours == 0 { return "UTC" }
    let minutes = Int((abs(offsetHours) * 60.0).rounded())
    let sign = offsetHours < 0 ? "-" : "+"
    return String(format: "UTC%@%02d:%02d", sign, minutes / 60, minutes % 60)
}

/// "Asia/Kolkata" → "Kolkata". An id with no region (such as "UTC") is its own name.
private func zoneCity(_ zone: TimeZone) -> String {
    (zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier)
        .replacingOccurrences(of: "_", with: " ")
}

/// Whether two zones keep the same time all year: the same offset now and the same next
/// daylight-saving transition (the closest Foundation gets to comparing zone rules).
private func keepSameTime(_ a: TimeZone, _ b: TimeZone, at date: Date) -> Bool {
    a.identifier == b.identifier
        || (a.secondsFromGMT(for: date) == b.secondsFromGMT(for: date)
            && a.nextDaylightSavingTimeTransition(after: date) == b.nextDaylightSavingTimeTransition(after: date))
}

/// Build the Clock category as of `date`. The device's own zone leads the list — it comes from the
/// system time-zone setting, so nothing here needs location access — followed by `clockZones`,
/// minus any entry that keeps the same time as the device's zone anyway.
func clockCategory(at date: Date = .now, local: TimeZone = .current) -> Category {
    let elsewhere = clockZones
        .compactMap { entry in TimeZone(identifier: entry.id).map { (zone: $0, name: entry.name) } }
        .filter { !keepSameTime($0.zone, local, at: date) }
        .sorted { $0.zone.secondsFromGMT(for: date) < $1.zone.secondsFromGMT(for: date) }
        .map { zoneUnit($0.name, zone: $0.zone, at: date) }
    return Category(
        id: clockID, name: "Clock", emoji: "🕒", colorHex: "#4338CA",
        units: [zoneUnit("Local time", zone: local, at: date, city: zoneCity(local))] + elsewhere,
        note: "Your own zone is the one the device is set to — no location access involved. "
            + "Every zone is shown at the UTC offset it is on right now, so a time typed for a "
            + "date the other side of a daylight-saving change can be an hour out.",
        valueFormat: ClockFormat(),
        openingValue: {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = local
            let parts = calendar.dateComponents([.hour, .minute], from: .now)
            return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60.0
        }
    )
}

// MARK: - Repository

/// A category a search turned up, plus the unit that matched when the category name did not.
struct CategoryMatch: Identifiable {
    let category: Category
    var matchedUnit: ConvUnit? = nil

    var id: String { category.id }
}

enum UnitsRepository {

    static let categories: [Category] = [
        Category(
            id: "length", name: "Length", emoji: "📏", colorHex: "#3B82F6",
            units: [
                linear("Meter", "m", 1.0),
                linear("Kilometer", "km", 1000.0),
                linear("Centimeter", "cm", 0.01),
                linear("Millimeter", "mm", 0.001),
                linear("Micrometer", "µm", 1e-6),
                linear("Mile", "mi", 1609.344),
                linear("Yard", "yd", 0.9144),
                linear("Foot", "ft", 0.3048),
                linear("Inch", "in", 0.0254),
                linear("Thou", "thou", 2.54e-5),
                linear("Nautical mile", "nmi", 1852.0)
            ]
        ),
        Category(
            id: "mass", name: "Mass", emoji: "⚖️", colorHex: "#10B981",
            units: [
                linear("Kilogram", "kg", 1.0),
                linear("Gram", "g", 0.001),
                linear("Milligram", "mg", 1e-6),
                linear("Metric ton", "t", 1000.0),
                linear("Pound", "lb", 0.45359237),
                linear("Ounce", "oz", 0.028349523125),
                linear("Stone", "st", 6.35029318)
            ]
        ),
        Category(
            id: "temperature", name: "Temperature", emoji: "🌡️", colorHex: "#EF4444",
            units: [
                ConvUnit(name: "Celsius", symbol: "°C", toBase: { $0 }, fromBase: { $0 }),
                ConvUnit(name: "Fahrenheit", symbol: "°F",
                         toBase: { ($0 - 32.0) * 5.0 / 9.0 },
                         fromBase: { $0 * 9.0 / 5.0 + 32.0 }),
                ConvUnit(name: "Kelvin", symbol: "K",
                         toBase: { $0 - 273.15 },
                         fromBase: { $0 + 273.15 })
            ]
        ),
        Category(
            id: "area", name: "Area", emoji: "📐", colorHex: "#8B5CF6",
            units: [
                linear("Square meter", "m²", 1.0),
                linear("Square kilometer", "km²", 1e6),
                linear("Square centimeter", "cm²", 1e-4),
                linear("Square mile", "mi²", 2589988.110336),
                linear("Square yard", "yd²", 0.83612736),
                linear("Square foot", "ft²", 0.09290304),
                linear("Square inch", "in²", 0.00064516),
                linear("Acre", "ac", 4046.8564224),
                linear("Hectare", "ha", 10000.0)
            ]
        ),
        Category(
            id: "volume", name: "Volume", emoji: "🧪", colorHex: "#06B6D4",
            units: [
                linear("Liter", "L", 1.0),
                linear("Milliliter", "mL", 0.001),
                linear("Cubic meter", "m³", 1000.0),
                linear("Cubic centimeter", "cm³", 0.001),
                linear("US gallon", "gal", 3.785411784),
                linear("US quart", "qt", 0.946352946),
                linear("US pint", "pt", 0.473176473),
                linear("US cup", "cup", 0.2365882365),
                linear("US fluid ounce", "fl oz", 0.0295735295625),
                linear("Imperial gallon", "imp gal", 4.54609)
            ]
        ),
        Category(
            id: "speed", name: "Speed", emoji: "🏎️", colorHex: "#F59E0B",
            units: [
                linear("Meter/second", "m/s", 1.0),
                linear("Kilometer/hour", "km/h", 1.0 / 3.6),
                linear("Mile/hour", "mph", 0.44704),
                linear("Foot/second", "ft/s", 0.3048),
                linear("Knot", "kn", 0.514444444444)
            ]
        ),
        Category(
            id: "fuel", name: "Fuel Economy", emoji: "⛽", colorHex: "#84CC16",
            // Base unit is kilometers per liter (km/L). MPG (more is better) maps with a
            // simple factor, but L/100 km is inversely related, so it uses km/L = 100 / value.
            units: [
                ConvUnit(name: "Mile/gallon (US)", symbol: "mpg",
                         toBase: { $0 * (1.609344 / 3.785411784) },
                         fromBase: { $0 / (1.609344 / 3.785411784) }),
                ConvUnit(name: "Mile/gallon (UK)", symbol: "mpg",
                         toBase: { $0 * (1.609344 / 4.54609) },
                         fromBase: { $0 / (1.609344 / 4.54609) }),
                ConvUnit(name: "Kilometer/liter", symbol: "km/L",
                         toBase: { $0 }, fromBase: { $0 }),
                ConvUnit(name: "Liter/100 km", symbol: "L/100km",
                         toBase: { 100.0 / $0 }, fromBase: { 100.0 / $0 })
            ],
            note: "Liters/100 km is an inverse measure: a lower number means a more efficient vehicle."
        ),
        Category(
            id: "ev", name: "EV Efficiency", emoji: "🔌", colorHex: "#7C3AED",
            units: [
                ConvUnit(name: "Watt-hour/kilometer", symbol: "Wh/km",
                         toBase: { $0 }, fromBase: { $0 }),
                ConvUnit(name: "Watt-hour/mile", symbol: "Wh/mi",
                         toBase: { $0 / 1.609344 }, fromBase: { $0 * 1.609344 }),
                ConvUnit(name: "kWh/100 km", symbol: "kWh/100km",
                         toBase: { $0 * 10.0 }, fromBase: { $0 / 10.0 }),
                ConvUnit(name: "kWh/100 mi", symbol: "kWh/100mi",
                         toBase: { $0 * (10.0 / 1.609344) }, fromBase: { $0 / (10.0 / 1.609344) }),
                ConvUnit(name: "Kilometer/kWh", symbol: "km/kWh",
                         toBase: { 1000.0 / $0 }, fromBase: { 1000.0 / $0 }),
                ConvUnit(name: "Mile/kWh", symbol: "mi/kWh",
                         toBase: { 1000.0 / ($0 * 1.609344) }, fromBase: { 1000.0 / ($0 * 1.609344) }),
                ConvUnit(name: "MPGe", symbol: "MPGe",
                         toBase: { 33700.0 / ($0 * 1.609344) }, fromBase: { 33700.0 / ($0 * 1.609344) })
            ],
            note: "Base is energy used per distance (Wh/km). Consumption units (Wh/km, "
                + "kWh/100 km) rise as efficiency drops; range units (mi/kWh, km/kWh, MPGe) "
                + "are inverse, so a higher number means a more efficient vehicle. MPGe uses "
                + "the EPA equivalence of 33.7 kWh per US gallon of gasoline."
        ),
        Category(
            id: "time", name: "Time", emoji: "⏱️", colorHex: "#6366F1",
            units: [
                linear("Second", "s", 1.0),
                linear("Millisecond", "ms", 0.001),
                linear("Minute", "min", 60.0),
                linear("Hour", "h", 3600.0),
                linear("Day", "d", 86400.0),
                linear("Week", "wk", 604800.0),
                linear("Month (30 d)", "mo", 2592000.0),
                linear("Year (365 d)", "yr", 31536000.0)
            ]
        ),
        clockCategory(),
        Category(
            id: "storage", name: "Digital Storage", emoji: "💾", colorHex: "#64748B",
            units: [
                linear("Bit", "b", 0.125),
                linear("Byte", "B", 1.0),
                linear("Kilobyte", "KB", 1024.0),
                linear("Megabyte", "MB", 1048576.0),
                linear("Gigabyte", "GB", 1073741824.0),
                linear("Terabyte", "TB", 1099511627776.0),
                linear("Petabyte", "PB", 1125899906842624.0)
            ]
        ),
        Category(
            id: "energy", name: "Energy", emoji: "⚡", colorHex: "#EAB308",
            units: [
                linear("Joule", "J", 1.0),
                linear("Kilojoule", "kJ", 1000.0),
                linear("Calorie", "cal", 4.184),
                linear("Kilocalorie", "kcal", 4184.0),
                linear("Watt-hour", "Wh", 3600.0),
                linear("Kilowatt-hour", "kWh", 3600000.0),
                linear("Foot-pound", "ft·lb", 1.3558179483314004)
            ]
        ),
        Category(
            id: "pressure", name: "Pressure", emoji: "🌬️", colorHex: "#0EA5E9",
            units: [
                linear("Pascal", "Pa", 1.0),
                linear("Kilopascal", "kPa", 1000.0),
                linear("Bar", "bar", 100000.0),
                linear("Millibar", "mbar", 100.0),
                linear("PSI", "psi", 6894.757293168),
                linear("Atmosphere", "atm", 101325.0),
                linear("Torr (mmHg)", "Torr", 133.32236842105263),
                linear("Kilogram-force per sq. cm", "kg/cm²", 98066.5)
            ]
        ),
        Category(
            id: "power", name: "Power", emoji: "🔋", colorHex: "#F97316",
            units: [
                linear("Watt", "W", 1.0),
                linear("Milliwatt", "mW", 0.001),
                linear("Kilowatt", "kW", 1000.0),
                linear("Megawatt", "MW", 1e6),
                linear("Horsepower", "hp", 745.6998715822702)
            ]
        ),
        Category(
            id: "angle", name: "Angle", emoji: "📐", colorHex: "#D946EF",
            units: [
                linear("Degree", "°", 1.0),
                linear("Radian", "rad", 57.29577951308232),
                linear("Gradian", "grad", 0.9),
                linear("Arcminute", "′", 1.0 / 60.0),
                linear("Arcsecond", "″", 1.0 / 3600.0),
                linear("Turn", "turn", 360.0)
            ]
        ),
        Category(
            id: "frequency", name: "Frequency", emoji: "📡", colorHex: "#14B8A6",
            units: [
                linear("Hertz", "Hz", 1.0),
                linear("Kilohertz", "kHz", 1000.0),
                linear("Megahertz", "MHz", 1e6),
                linear("Gigahertz", "GHz", 1e9)
            ]
        ),
        payCategory(hoursPerWeek: defaultHoursPerWeek),
        Category(
            id: "shoe_men", name: "Men's Shoe Size", emoji: "👞", colorHex: "#92400E",
            // Base unit is foot length in mm. Men's UK runs 0.5 below US; EU is unisex.
            units: [
                shoeBarleycorn("US", "US", anchorSize: 9.0),
                shoeBarleycorn("UK", "UK", anchorSize: 8.5),
                shoeEu(),
                linear("Foot length (cm)", "cm", 10.0),
                linear("Foot length (mm)", "mm", 1.0)
            ],
            note: "Approximate adult men's sizes anchored to common charts (US 9 ≈ 270 mm "
                + "foot). Round to the nearest half size; fit varies by brand."
        ),
        Category(
            id: "shoe_women", name: "Women's Shoe Size", emoji: "👠", colorHex: "#BE185D",
            // Base unit is foot length in mm. Women's US runs 1.5 above men's; UK and EU are unisex.
            units: [
                shoeBarleycorn("US", "US", anchorSize: 10.5),
                shoeBarleycorn("UK", "UK", anchorSize: 8.5),
                shoeEu(),
                linear("Foot length (cm)", "cm", 10.0),
                linear("Foot length (mm)", "mm", 1.0)
            ],
            note: "Approximate adult women's sizes anchored to common charts (US 10.5 ≈ "
                + "270 mm foot; US women run ~1.5 above US men). Round to the nearest half "
                + "size; fit varies by brand."
        ),
        Category(
            id: "shirt_men", name: "Men's Shirt Size", emoji: "👔", colorHex: "#1E3A8A",
            // Base unit is neck circumference in cm. EU shirt size = neck cm.
            units: [
                linear("Collar US/UK", "in", 2.54, snap: 0.5),
                linear("Collar EU", "cm", 1.0, snap: 0.5)
            ],
            note: "Dress-shirt sizes by collar (neck) circumference. EU size equals the "
                + "neck in cm. Rough letter sizes: S ≈ 14–14½ in, M ≈ 15–15½ in, L ≈ 16–16½ in, "
                + "XL ≈ 17–17½ in. Fit varies by brand."
        ),
        Category(
            id: "shirt_women", name: "Women's Shirt Size", emoji: "👚", colorHex: "#DB2777",
            // Base unit is bust circumference in cm; US/UK/EU come from the ASOS table.
            units: [
                womensTop("US", "US", offsetFromUK: -4.0),
                womensTop("UK", "UK", offsetFromUK: 0.0),
                womensTop("EU", "EU", offsetFromUK: 28.0),
                linear("Bust", "in", 2.54),
                linear("Bust", "cm", 1.0)
            ],
            note: "Tops/blouse sizes by bust circumference, interpolated from the ASOS chart "
                + "(UK = US + 4, EU = US + 32). E.g. UK 12 / US 8 ≈ 93 cm, UK 20 ≈ 116 cm bust. "
                + "Fit varies by brand."
        )
    ]

    /// Look up a category by id. Clock is rebuilt on every lookup so that it opens on the device's
    /// current zone and today's offsets, not on whatever they were when the app started.
    static func category(id: String) -> Category? {
        id == clockID ? clockCategory() : categories.first { $0.id == id }
    }

    /// Format a converted value for display. With `decimals` the value is rounded to that many
    /// places; without it precision is limited to ~10 significant digits and trailing zeros are
    /// trimmed. Either way very large/small magnitudes fall back to scientific notation.
    static func format(_ value: Double, decimals: Int? = nil, locale: Locale = .autoupdatingCurrent) -> String {
        formatNumber(value, decimals: decimals, locale: locale)
    }

    /// Read a number typed in a field, in `locale`'s conventions or the "." ones. Returns nil for
    /// text that isn't a usable number.
    static func parse(_ text: String, locale: Locale = .autoupdatingCurrent) -> Double? {
        parseNumber(text, locale: locale)
    }

    /// Find the categories matching a search `query`. A category whose own name matches wins;
    /// otherwise the first unit whose name or symbol matches brings its category along, so
    /// searching "psi" or "knot" finds where those units live. Blank queries match everything.
    static func search(_ query: String, in from: [Category] = categories) -> [CategoryMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return from.map { CategoryMatch(category: $0) } }
        return from.compactMap { category in
            if category.name.localizedCaseInsensitiveContains(trimmed) {
                return CategoryMatch(category: category)
            }
            return category.units
                .first {
                    $0.name.localizedCaseInsensitiveContains(trimmed)
                        || $0.symbol.localizedCaseInsensitiveContains(trimmed)
                }
                .map { CategoryMatch(category: category, matchedUnit: $0) }
        }
    }
}
