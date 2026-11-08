import SwiftUI

/// Home screen: a tiled grid of every conversion category, draggable to reorder and searchable.
struct ContentView: View {
    private static let orderKey = "category_order"

    /// Every category in the user's saved order — the grid shows a filtered view of this.
    @State private var categories = Self.orderedCategories()

    /// Current search text. Reordering is only meaningful, and only allowed, while it is blank.
    @State private var query = ""

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Two columns of tiles, or one at accessibility text sizes so names have room to grow.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    private var matches: [CategoryMatch] {
        UnitsRepository.search(query, in: categories)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let matches = matches
                if matches.isEmpty {
                    ContentUnavailableView.search(text: query.trimmingCharacters(in: .whitespaces))
                } else if #available(iOS 27.0, macOS 27.0, *) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(matches) { match in
                            tileLink(match)
                        }
                        .reorderable()
                    }
                    // A drag within search results would reorder a partial list, so only
                    // allow it while the full grid is on screen.
                    .reorderContainer(for: CategoryMatch.self, isEnabled: query.isEmpty) { difference in
                        move(difference)
                    }
                    .padding()
                } else {
                    // Before iOS 27 there is no reorder container, so tiles are plain drag
                    // sources and drop targets: drop a tile on another to take its place.
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(matches) { match in
                            tileLink(match)
                                .draggable(match.category.id) {
                                    CategoryTile(match: match)
                                        .frame(width: 160)
                                }
                                .dropDestination(for: String.self) { ids, _ in
                                    move(ids, onto: match.category.id)
                                }
                                // Dragging isn't available to VoiceOver, so offer the same
                                // reordering as actions.
                                .accessibilityActions {
                                    if query.isEmpty {
                                        Button("Move earlier") { move(match.category.id, by: -1) }
                                        Button("Move later") { move(match.category.id, by: 1) }
                                    }
                                }
                        }
                    }
                    .padding()
                }
            }
            .background(Color.groupedBackground)
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

    /// A tile that opens its category's converter.
    private func tileLink(_ match: CategoryMatch) -> some View {
        NavigationLink(value: match.category.id) {
            CategoryTile(match: match)
        }
        .buttonStyle(.plain)
    }

    /// Apply a drag-to-reorder from the iOS 27 reorder container.
    @available(iOS 27.0, macOS 27.0, *)
    private func move(_ difference: ReorderDifference<String, ReorderableSingleCollectionIdentifier>) {
        let before: String?
        switch difference.destination.position {
        case .before(let id):
            before = id
        case .end:
            before = nil
        @unknown default:
            before = nil
        }
        move(difference.sources, before: before)
    }

    /// Apply a tile dropped onto `targetID` (the pre-iOS 27 fallback). Returns whether the drop
    /// was accepted.
    private func move(_ ids: [String], onto targetID: String) -> Bool {
        // A drop within search results would reorder a partial list, so ignore it.
        guard query.isEmpty, let id = ids.first, id != targetID,
              let from = categories.firstIndex(where: { $0.id == id }),
              let to = categories.firstIndex(where: { $0.id == targetID }) else { return false }
        // The dropped tile takes the target's place: dragging forward lands after the target,
        // dragging backward lands before it.
        let before: String?
        if from > to {
            before = targetID
        } else {
            before = to + 1 < categories.count ? categories[to + 1].id : nil
        }
        withAnimation {
            move([id], before: before)
        }
        return true
    }

    /// Move one category a step earlier (`offset` -1) or later (+1), for VoiceOver's actions.
    private func move(_ id: String, by offset: Int) {
        guard let from = categories.firstIndex(where: { $0.id == id }),
              categories.indices.contains(from + offset) else { return }
        let target = categories[from + offset].id
        _ = move([id], onto: target)
    }

    /// Move the categories with `ids` to just before `beforeID` (or to the end when nil), then
    /// persist the new tile order.
    private func move(_ ids: [String], before beforeID: String?) {
        let moving = ids.compactMap { id in categories.first { $0.id == id } }
        categories.removeAll { ids.contains($0.id) }
        let insertAt = beforeID.flatMap { id in categories.firstIndex { $0.id == id } } ?? categories.endIndex
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

    /// The emoji circle grows with the emoji's text style so the emoji never spills out of it.
    @ScaledMetric(relativeTo: .title) private var circleSize: CGFloat = 52

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
                .frame(width: circleSize, height: circleSize)
                .background(Color(hex: match.category.colorHex).opacity(0.85), in: .circle)
                .padding(.bottom, 4)
                // Decorative: VoiceOver would read the emoji's name before the category's.
                .accessibilityHidden(true)
            // Names wrap rather than truncate at large text sizes.
            Text(match.category.name)
                .font(.subheadline.bold())
                .lineLimit(2)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 10)
        .background(Color.cardBackground, in: .rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
    }
}

#Preview {
    ContentView()
}
