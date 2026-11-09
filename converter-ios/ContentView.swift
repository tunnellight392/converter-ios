import SwiftUI

/// Home screen: a tiled grid of every conversion category, draggable to reorder and searchable.
struct ContentView: View {
    private static let orderKey = "category_order"

    /// Every category in the user's saved order — the grid shows a filtered view of this.
    @State private var categories = Self.orderedCategories()

    /// Current search text. Reordering is only meaningful, and only allowed, while it is blank.
    @State private var query = ""

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// As many tile columns as fit at 160 pt or wider — two on iPhone, five or so on a large iPad —
    /// or a single column at accessibility text sizes so names have room to grow.
    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 16)]
            : [GridItem(.adaptive(minimum: 160), spacing: 16)]
    }

    /// Pinned conversion cards: one per row on iPhone, side by side where there's room (iPad).
    private var pairColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 16)]
            : [GridItem(.adaptive(minimum: 300), spacing: 16)]
    }

    @Environment(Favorites.self) private var favorites

    /// What a home-screen link opens: a category, or a pinned conversion within one.
    enum Route: Hashable {
        case category(String)
        case pair(UnitPair)
    }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The main grid: while searching, every category that matches; otherwise every category
    /// not already pinned above it.
    private var matches: [CategoryMatch] {
        if isSearching { return UnitsRepository.search(query, in: categories) }
        return UnitsRepository.search("", in: categories.filter { !favorites.isPinned($0.id) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let matches = matches
                let pairs = isSearching ? [] : favorites.resolvedPairs()
                let pinned = isSearching ? [] : favorites.categoryIDs.compactMap { id in
                    categories.first { $0.id == id }
                }
                VStack(alignment: .leading, spacing: 16) {
                    if !pairs.isEmpty || !pinned.isEmpty {
                        pinnedSection(pairs: pairs, categories: pinned)
                        if !matches.isEmpty {
                            sectionHeader("All Categories")
                        }
                    }
                    if matches.isEmpty {
                        if isSearching {
                            ContentUnavailableView.search(text: query.trimmingCharacters(in: .whitespaces))
                        }
                    } else {
                        grid(matches)
                    }
                }
                .padding()
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
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .category(let id):
                    if let model = ConverterModel(categoryID: id) {
                        ConverterView(model: model)
                    }
                case .pair(let pair):
                    if let model = ConverterModel(categoryID: pair.categoryID, pair: pair) {
                        ConverterView(model: model)
                    }
                }
            }
        }
    }

    /// Pinned conversions as cards, then pinned categories as tiles.
    private func pinnedSection(pairs: [ResolvedPair], categories pinned: [Category]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Pinned")
            if !pairs.isEmpty {
                LazyVGrid(columns: pairColumns, spacing: 16) {
                    ForEach(pairs) { resolved in
                        NavigationLink(value: Route.pair(resolved.pair)) {
                            PairCard(resolved: resolved)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Unpin", systemImage: "pin.slash") {
                                favorites.unpin(resolved.pair)
                            }
                        }
                        .accessibilityAction(named: "Unpin") { favorites.unpin(resolved.pair) }
                    }
                }
            }
            if !pinned.isEmpty {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(pinned) { category in
                        tileLink(CategoryMatch(category: category))
                    }
                }
            }
        }
    }

    /// Every category not pinned (or every search match), draggable to reorder.
    @ViewBuilder
    private func grid(_ matches: [CategoryMatch]) -> some View {
        if #available(iOS 27.0, *) {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(matches) { match in
                    tileLink(match)
                }
                .reorderable()
            }
            // A drag within search results would reorder a partial list, so only
            // allow it while the full grid is on screen.
            .reorderContainer(for: CategoryMatch.self, isEnabled: !isSearching) { difference in
                move(difference)
            }
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
                            if !isSearching {
                                Button("Move earlier") { move(match.category.id, by: -1) }
                                Button("Move later") { move(match.category.id, by: 1) }
                            }
                        }
                }
            }
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.title3.bold())
            .accessibilityAddTraits(.isHeader)
    }

    /// A tile that opens its category's converter. Long-press to pin or unpin it.
    private func tileLink(_ match: CategoryMatch) -> some View {
        let id = match.category.id
        let isPinned = favorites.isPinned(id)
        return NavigationLink(value: Route.category(id)) {
            CategoryTile(match: match)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(isPinned ? "Unpin" : "Pin to Top", systemImage: isPinned ? "pin.slash" : "pin") {
                withAnimation { favorites.togglePin(id) }
            }
        }
        .accessibilityAction(named: isPinned ? "Unpin" : "Pin to Top") {
            favorites.togglePin(id)
        }
    }

    /// Apply a drag-to-reorder from the iOS 27 reorder container.
    @available(iOS 27.0, *)
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
        // Step between the tiles in the grid, skipping pinned categories shown above it.
        let visible = categories.filter { !favorites.isPinned($0.id) }
        guard let from = visible.firstIndex(where: { $0.id == id }),
              visible.indices.contains(from + offset) else { return }
        _ = move([id], onto: visible[from + offset].id)
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

/// A pinned conversion: "Mile → Kilometer" with a sample result, opening that converter.
private struct PairCard: View {
    let resolved: ResolvedPair

    @ScaledMetric(relativeTo: .title3) private var circleSize: CGFloat = 40
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// "1 mi = 1.609344 km", for categories whose values are plain numbers.
    private var sample: String? {
        let category = resolved.category
        guard category.valueFormat == nil else { return nil }
        let result = UnitsRepository.format(resolved.from.convert(1, to: resolved.to), decimals: category.decimals)
        return "1 \(resolved.from.symbol) = \(result) \(resolved.to.symbol)"
    }

    /// "Length · 1 ft = 30.48 cm"
    private var subtitle: some View {
        Text(sample.map { "\(resolved.category.name) · \($0)" } ?? resolved.category.name)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(resolved.category.emoji)
                .font(.title3)
                .frame(width: circleSize, height: circleSize)
                .background(Color(hex: resolved.category.colorHex).opacity(0.85), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(resolved.from.name) → \(resolved.to.name)")
                    .font(.headline)
                    .accessibilityLabel("\(resolved.from.name) to \(resolved.to.name)")
                // Side by side (iPad), cards are narrow enough for this line to wrap; reserving
                // two lines in every card keeps a row of cards the same height.
                if horizontalSizeClass == .regular {
                    subtitle.lineLimit(2, reservesSpace: true)
                } else {
                    subtitle
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(Color.cardBackground, in: .rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
    }
}

#Preview {
    ContentView()
        .environment(Favorites())
}

#Preview("With pins") {
    // A throwaway store so the preview's pins don't leak into the app's own.
    let defaults = UserDefaults(suiteName: "ContentView.preview") ?? .standard
    defaults.removePersistentDomain(forName: "ContentView.preview")
    let favorites = Favorites(defaults: defaults)
    favorites.pin(UnitPair(categoryID: "length", fromUnitID: "Mile|mi", toUnitID: "Kilometer|km"))
    favorites.pin(UnitPair(categoryID: "temperature", fromUnitID: "Fahrenheit|°F", toUnitID: "Celsius|°C"))
    favorites.togglePin("mass")
    favorites.togglePin("pay")
    return ContentView()
        .environment(favorites)
}
