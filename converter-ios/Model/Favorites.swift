import Foundation
import Observation

/// A conversion the user pinned to the home screen: one unit to another within a category.
struct UnitPair: Codable, Hashable, Identifiable {
    let categoryID: String
    let fromUnitID: String
    let toUnitID: String

    var id: String { "\(categoryID):\(fromUnitID)>\(toUnitID)" }
}

/// A pinned pair with its category and units looked up, ready to show.
struct ResolvedPair: Identifiable {
    let pair: UnitPair
    let category: Category
    let from: ConvUnit
    let to: ConvUnit

    var id: String { pair.id }
}

/// The categories and unit pairs the user pinned to the top of the home screen, saved across
/// launches. Pins keep the order they were made in.
@Observable
final class Favorites {

    private(set) var categoryIDs: [String]
    private(set) var pairs: [UnitPair]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        categoryIDs = defaults.stringArray(forKey: Keys.categories) ?? []
        pairs = defaults.data(forKey: Keys.pairs)
            .flatMap { try? JSONDecoder().decode([UnitPair].self, from: $0) } ?? []
    }

    // MARK: Categories

    func isPinned(_ categoryID: String) -> Bool {
        categoryIDs.contains(categoryID)
    }

    func togglePin(_ categoryID: String) {
        if let index = categoryIDs.firstIndex(of: categoryID) {
            categoryIDs.remove(at: index)
        } else {
            categoryIDs.append(categoryID)
        }
        defaults.set(categoryIDs, forKey: Keys.categories)
    }

    // MARK: Pairs

    func isPinned(_ pair: UnitPair) -> Bool {
        pairs.contains(pair)
    }

    /// Pin `pair`, unless it's already pinned or goes from a unit to itself.
    func pin(_ pair: UnitPair) {
        guard pair.fromUnitID != pair.toUnitID, !pairs.contains(pair) else { return }
        pairs.append(pair)
        savePairs()
    }

    func unpin(_ pair: UnitPair) {
        pairs.removeAll { $0 == pair }
        savePairs()
    }

    /// Pinned pairs whose category and units still exist, looked up and ready to show. A pair
    /// can go missing — a Clock city that now keeps the same time as the device's own zone is
    /// left out of the category — and comes back if the unit does.
    func resolvedPairs() -> [ResolvedPair] {
        pairs.compactMap { pair in
            guard let category = UnitsRepository.category(id: pair.categoryID),
                  let from = category.units.first(where: { $0.id == pair.fromUnitID }),
                  let to = category.units.first(where: { $0.id == pair.toUnitID }) else { return nil }
            return ResolvedPair(pair: pair, category: category, from: from, to: to)
        }
    }

    private func savePairs() {
        defaults.set(try? JSONEncoder().encode(pairs), forKey: Keys.pairs)
    }

    private enum Keys {
        static let categories = "favorites.categories"
        static let pairs = "favorites.pairs"
    }
}
