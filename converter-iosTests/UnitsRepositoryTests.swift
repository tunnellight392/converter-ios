import Testing
@testable import converter_ios

/// Formatting and search are pure functions the two screens lean on, so pin their behaviour.
@MainActor
struct UnitsRepositoryTests {

    @Test(arguments: [
        (8666.666666, 2, "8666.67"),
        (104000.0, 2, "104000.00"),
        (0.0, 2, "0.00"),
        (12.5, 0, "13"),
        (1.005, 2, "1.01")
    ])
    func formatsToAFixedNumberOfDecimals(value: Double, decimals: Int, expected: String) {
        #expect(UnitsRepository.format(value, decimals: decimals) == expected)
    }

    @Test(arguments: [
        (0.0, "0"),
        (2080.0, "2080"),
        (1.5, "1.5"),
        (-40.0, "-40"),
        (1.0 / 3.0, "0.3333333333")
    ])
    func formatsAdaptivelyWithoutDecimals(value: Double, expected: String) {
        #expect(UnitsRepository.format(value) == expected)
    }

    @Test func keepsScientificNotationForExtremeMagnitudes() {
        // A fixed scale would print a misleading "0.00" here, so the fallback wins either way.
        #expect(UnitsRepository.format(1e-9, decimals: 2).contains("E-"))
        #expect(UnitsRepository.format(1e15, decimals: 2).contains("E+"))
    }

    @Test func formatsNonFiniteValuesAsEmpty() {
        #expect(UnitsRepository.format(.infinity).isEmpty)
        #expect(UnitsRepository.format(.nan).isEmpty)
    }

    @Test func searchMatchesCategoryNames() throws {
        let matches = UnitsRepository.search("temp")
        try #require(matches.count == 1)
        #expect(matches[0].category.id == "temperature")
        #expect(matches[0].matchedUnit == nil, "a category-name hit needs no unit caption")
    }

    @Test func searchFallsBackToUnitNamesAndSymbols() throws {
        let bySymbol = try #require(UnitsRepository.search("psi").only)
        #expect(bySymbol.category.id == "pressure")
        #expect(bySymbol.matchedUnit?.name == "PSI")

        let byName = try #require(UnitsRepository.search("knot").only)
        #expect(byName.category.id == "speed")
        #expect(byName.matchedUnit?.name == "Knot")
    }

    @Test func blankSearchReturnsEverythingAndNonsenseReturnsNothing() {
        #expect(UnitsRepository.search("   ").count == UnitsRepository.categories.count)
        #expect(UnitsRepository.search("zzzz").isEmpty)
    }

    @Test func categoryIDsAreUnique() {
        let ids = UnitsRepository.categories.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}

@MainActor
struct ConversionTests {

    private func units(_ categoryID: String) throws -> [ConvUnit] {
        try #require(UnitsRepository.category(id: categoryID)).units
    }

    private func unit(_ name: String, in categoryID: String) throws -> ConvUnit {
        try #require(try units(categoryID).first { $0.name == name })
    }

    @Test func convertsTemperatureWithOffsets() throws {
        let celsius = try unit("Celsius", in: "temperature")
        let fahrenheit = try unit("Fahrenheit", in: "temperature")
        let kelvin = try unit("Kelvin", in: "temperature")
        #expect(abs(celsius.convert(100, to: fahrenheit) - 212) < 1e-9)
        #expect(abs(fahrenheit.convert(-40, to: celsius) - -40) < 1e-9)
        #expect(abs(kelvin.convert(0, to: celsius) - -273.15) < 1e-9)
    }

    @Test func convertsInverseFuelEconomy() throws {
        let kmPerLiter = try unit("Kilometer/liter", in: "fuel")
        let litersPer100 = try unit("Liter/100 km", in: "fuel")
        #expect(abs(kmPerLiter.convert(20, to: litersPer100) - 5) < 1e-9)
    }

    @Test func snapsShoeSizesToHalfSizes() throws {
        let shoes = try units("shoe_men")
        let us = shoes[0], uk = shoes[1], eu = shoes[2]
        #expect(us.convert(9, to: uk) == 8.5)
        #expect(us.convert(9, to: eu) == 42.5)
    }

    @Test func roundTripsEveryLinearUnit() throws {
        // Converting out and back should land where it started for every unit pair whose
        // target isn't snapped (snapping deliberately loses precision).
        for category in UnitsRepository.categories {
            for from in category.units where from.snap == nil {
                for to in category.units where to.snap == nil {
                    let back = to.convert(from.convert(7.25, to: to), to: from)
                    #expect(abs(back - 7.25) < 1e-6, "\(category.name): \(from.name) ↔ \(to.name)")
                }
            }
        }
    }
}

private extension Array {
    /// The sole element, or nil when there isn't exactly one — like Kotlin's `single()`.
    var only: Element? { count == 1 ? first : nil }
}
