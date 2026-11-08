import SwiftUI

/// Home screen: a tiled grid of every conversion category, draggable to reorder and searchable.
struct ContentView: View {
    private static let orderKey = "category_order"

    /// Every category in the user's saved order — the grid shows a filtered view of this.
    @State private var categories = Self.orderedCategories()

    /// Current search text. Reordering is only meaningful, and only allowed, while it is blank.
    @State private var query = ""

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    private var matches: [CategoryMatch] {
        UnitsRepository.search(query, in: categories)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let matches = matches
                if matches.isEmpty {
                    ContentUnavailableView.search(text: query.trimmingCharacters(in: .whitespaces))
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(matches) { match in
                            NavigationLink(value: match.category.id) {
                                CategoryTile(match: match)
                            }
                            .buttonStyle(.plain)
                        }
                        .reorderable()
                    }
                    // A drag within search results would reorder a partial list, so only
                    // allow it while the full grid is on screen.
                    .reorderContainer(for: CategoryMatch.self, isEnabled: query.isEmpty) { difference in
                        move(difference)
                    }
                    .padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Unit Converter")
            .searchable(text: $query, prompt: "Search categories or units")
            .toolbar {
                NavigationLink {
                    FeedbackView()
                } label: {
                    Label("Feedback", systemImage: "bubble.left")
                }
            }
            .navigationDestination(for: String.self) { id in
                if let model = ConverterModel(categoryID: id) {
                    ConverterView(model: model)
                }
            }
        }
    }

    /// Apply a drag-to-reorder and persist the new tile order.
    private func move(_ difference: ReorderDifference<String, ReorderableSingleCollectionIdentifier>) {
        let moving = difference.sources.compactMap { id in categories.first { $0.id == id } }
        categories.removeAll { difference.sources.contains($0.id) }
        let insertAt: Int
        switch difference.destination.position {
        case .before(let id):
            insertAt = categories.firstIndex { $0.id == id } ?? categories.endIndex
        case .end:
            insertAt = categories.endIndex
        @unknown default:
            insertAt = categories.endIndex
        }
        categories.insert(contentsOf: moving, at: insertAt)
        UserDefaults.standard.set(categories.map(\.id), forKey: Self.orderKey)
    }

    /// Apply any saved reordering, appending categories the saved order doesn't mention.
    private static func orderedCategories() -> [Category] {
        let all = UnitsRepository.categories
        guard let saved = UserDefaults.standard.stringArray(forKey: orderKey) else { return all }
        let ordered = saved.compactMap { id in all.first { $0.id == id } }
        // Fall back gracefully if the category set changed since the order was saved.
        return ordered + all.filter { category in !ordered.contains { $0.id == category.id } }
    }
}

/// A category rendered as a tile in the home grid.
private struct CategoryTile: View {
    let match: CategoryMatch

    /// When a search found this tile through one of its units, name that unit instead of the
    /// unit count — it is why the tile is on screen.
    private var subtitle: String {
        guard let unit = match.matchedUnit else { return "\(match.category.units.count) units" }
        return unit.name == unit.symbol ? unit.name : "\(unit.name) · \(unit.symbol)"
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(match.category.emoji)
                .font(.title)
                .frame(width: 52, height: 52)
                .background(Color(hex: match.category.colorHex).opacity(0.85), in: .circle)
                .padding(.bottom, 4)
            Text(match.category.name)
                .font(.subheadline.bold())
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 10)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
    }
}

#Preview {
    ContentView()
}
