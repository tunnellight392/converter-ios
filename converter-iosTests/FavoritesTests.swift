import Foundation
import Testing
@testable import converter_ios

/// Pinned categories and conversions: toggling, ordering, persistence, and lookup.
@MainActor
struct FavoritesTests {

    private let suite = "FavoritesTests.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    private let mileToKm = UnitPair(categoryID: "length", fromUnitID: "Mile|mi", toUnitID: "Kilometer|km")

    @Test func pinsAndUnpinsCategoriesInPinOrder() {
        let favorites = Favorites(defaults: defaults)
        favorites.togglePin("mass")
        favorites.togglePin("length")
        #expect(favorites.categoryIDs == ["mass", "length"])
        #expect(favorites.isPinned("mass"))

        favorites.togglePin("mass")
        #expect(favorites.categoryIDs == ["length"])
        #expect(!favorites.isPinned("mass"))
    }

    @Test func pinsEachPairOnceAndNeverAUnitToItself() {
        let favorites = Favorites(defaults: defaults)
        favorites.pin(mileToKm)
        favorites.pin(mileToKm)
        favorites.pin(UnitPair(categoryID: "length", fromUnitID: "Mile|mi", toUnitID: "Mile|mi"))
        #expect(favorites.pairs == [mileToKm])

        favorites.unpin(mileToKm)
        #expect(favorites.pairs.isEmpty)
    }

    @Test func keepsPinsAcrossLaunches() {
        let first = Favorites(defaults: defaults)
        first.togglePin("temperature")
        first.pin(mileToKm)

        let relaunched = Favorites(defaults: defaults)
        #expect(relaunched.categoryIDs == ["temperature"])
        #expect(relaunched.pairs == [mileToKm])
    }

    @Test func resolvesPairsToTheirUnits() throws {
        let favorites = Favorites(defaults: defaults)
        favorites.pin(mileToKm)
        let resolved = try #require(favorites.resolvedPairs().first)
        #expect(resolved.category.id == "length")
        #expect(resolved.from.name == "Mile")
        #expect(resolved.to.name == "Kilometer")
    }

    @Test func skipsPairsWhoseUnitsNoLongerExist() {
        let favorites = Favorites(defaults: defaults)
        favorites.pin(UnitPair(categoryID: "length", fromUnitID: "Furlong|fur", toUnitID: "Mile|mi"))
        favorites.pin(UnitPair(categoryID: "gone", fromUnitID: "a", toUnitID: "b"))
        #expect(favorites.resolvedPairs().isEmpty)
        // Still remembered, in case the unit comes back (a Clock city, say).
        #expect(favorites.pairs.count == 2)
    }

    @Test func tellsApartUnitsThatShareAName() throws {
        let shirts = try #require(UnitsRepository.category(id: "shirt_women"))
        let busts = shirts.units.filter { $0.name == "Bust" }
        #expect(busts.count == 2)
        #expect(busts[0].id != busts[1].id)
        let ids = shirts.units.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func clockUnitIDsDontDependOnTheUTCOffset() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let winter = try #require(ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z"))
        let summer = try #require(ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z"))
        let winterIDs = clockCategory(at: winter, local: newYork).units.map(\.id)
        let summerIDs = clockCategory(at: summer, local: newYork).units.map(\.id)
        // The symbols carry the offset and change with daylight saving; the ids must not.
        #expect(Set(winterIDs) == Set(summerIDs))
        #expect(winterIDs.first == "local")
        #expect(winterIDs.contains("Asia/Tokyo"))
    }
}

/// Opening the converter from a pinned conversion.
@MainActor
struct PinnedPairConverterTests {

    private let defaults: UserDefaults

    init() throws {
        let suite = "PinnedPairConverterTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func putsThePairsUnitsFirst() throws {
        let pair = UnitPair(categoryID: "length", fromUnitID: "Mile|mi", toUnitID: "Kilometer|km")
        let model = try #require(ConverterModel(categoryID: "length", pair: pair, defaults: defaults, locale: .usEnglish))
        let units = model.category.units
        #expect(model.pair == pair)
        #expect(units[model.displayOrder[0]].name == "Mile")
        #expect(units[model.displayOrder[1]].name == "Kilometer")
        #expect(model.pairFromIndex == model.displayOrder[0])
        // Every unit is still shown, once.
        #expect(model.displayOrder.sorted() == Array(units.indices))
    }

    @Test func convertsAlongThePair() throws {
        let pair = UnitPair(categoryID: "length", fromUnitID: "Mile|mi", toUnitID: "Kilometer|km")
        let model = try #require(ConverterModel(categoryID: "length", pair: pair, defaults: defaults, locale: .usEnglish))
        model.userEdited(row: model.displayOrder[0], text: "1")
        #expect(model.texts[model.displayOrder[1]] == "1.609344")
    }

    @Test func opensInTheUsualOrderWhenThePairCantBeFound() throws {
        let pair = UnitPair(categoryID: "length", fromUnitID: "Furlong|fur", toUnitID: "Mile|mi")
        let model = try #require(ConverterModel(categoryID: "length", pair: pair, defaults: defaults, locale: .usEnglish))
        #expect(model.pair == nil)
        #expect(model.pairFromIndex == nil)
        #expect(model.displayOrder == Array(model.category.units.indices))
    }
}
