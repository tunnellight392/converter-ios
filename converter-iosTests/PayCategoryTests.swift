import Testing
@testable import converter_ios

/// The Pay category converts against an adjustable work week, so check both ends of the rebuild.
@MainActor
struct PayCategoryTests {

    private let pay: converter_ios.Category
    private let hourly: ConvUnit
    private let yearly: ConvUnit

    init() throws {
        pay = try #require(UnitsRepository.category(id: "pay"))
        hourly = try #require(pay.units.first { $0.name == "Hourly" })
        yearly = try #require(pay.units.first { $0.name == "Yearly" })
    }

    @Test func defaultsToA40HourWeek() {
        #expect(abs(hourly.convert(1, to: yearly) - 2080) < 1e-9)
        #expect(pay.note == "Conversions assume a 40-hour work week (2080 hours per year).")
    }

    @Test func rebuildsForAShorterWeek() throws {
        let part = try #require(pay.param).variantFor(37.5)
        let partHourly = try #require(part.units.first { $0.name == "Hourly" })
        let partYearly = try #require(part.units.first { $0.name == "Yearly" })

        #expect(abs(partHourly.convert(1, to: partYearly) - 1950) < 1e-9)
        #expect(abs(partYearly.convert(39000, to: partHourly) - 20) < 1e-9)
        // The note writes the hours the way the device's locale does ("37,5" in Germany).
        let hours = UnitsRepository.format(37.5)
        #expect(part.note == "Conversions assume a \(hours)-hour work week (1950 hours per year).")
    }

    @Test func monthlyIsUnaffectedByTheWorkWeek() throws {
        let monthly = try #require(pay.units.first { $0.name == "Monthly" })
        #expect(abs(monthly.convert(1000, to: yearly) - 12000) < 1e-9)
    }
}
