import SwiftUI

/// Shows every unit in a category, each with its own input field. Typing a value into any
/// field instantly converts and fills in all the others.
struct ConverterView: View {
    @State private var model: ConverterModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(Favorites.self) private var favorites

    /// The row being typed in. A pinned conversion opens with its "from" row focused.
    @FocusState private var focusedRow: Int?
    @State private var isPinningPair = false

    /// Bumped on every copy, to play a success haptic.
    @State private var copyCount = 0

    /// Focus value for the parameter field (hours per week), alongside unit-row indices.
    private static let paramFocus = -1

    init(model: ConverterModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let note = model.category.note {
                    NoteBanner(text: note)
                }
                if let param = model.category.param {
                    paramRow(param)
                }
                if model.pair != nil {
                    // Opened from a pinned conversion: its two units first, then the rest.
                    sectionHeader("Pinned conversion")
                    ForEach(model.displayOrder.prefix(2), id: \.self) { index in
                        unitRow(index)
                    }
                    if model.displayOrder.count > 2 {
                        sectionHeader("Other units")
                        ForEach(model.displayOrder.dropFirst(2), id: \.self) { index in
                            unitRow(index)
                        }
                    }
                } else {
                    ForEach(model.displayOrder, id: \.self) { index in
                        unitRow(index)
                    }
                }
            }
            .padding()
        }
        .background(Color.groupedBackground)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(model.category.name)
        .inlineNavigationTitle()
        .toolbar {
            if model.category.openingValue != nil {
                // Clock offers a way back to the current moment.
                Button("Now", systemImage: "clock.arrow.circlepath") {
                    model.fillInitialValue()
                }
            }
            if model.category.valueFormat == nil {
                // Decimal places say nothing about a category that formats its own values.
                decimalsMenu
            }
            shareMenu
            pinMenu
        }
        .sensoryFeedback(.success, trigger: copyCount)
        .sheet(isPresented: $isPinningPair) {
            PinPairSheet(
                category: model.category,
                initialFrom: model.lastEdited ?? model.displayOrder[0]
            ) { pair in
                favorites.pin(pair)
            }
        }
        .task {
            focusedRow = model.pairFromIndex
        }
        .onDisappear { model.save() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.save() }
        }
    }

    /// Copy or share every value at once, as text.
    private var shareMenu: some View {
        let text = model.shareText
        return Menu("Share", systemImage: "square.and.arrow.up") {
            Button("Copy All", systemImage: "doc.on.doc") {
                guard let text else { return }
                copyToPasteboard(text)
                copyCount += 1
            }
            if let text {
                ShareLink("Share…", item: text)
            }
        }
        .disabled(text == nil)
    }

    /// Pin this category, or a conversion between two of its units, to the home screen.
    private var pinMenu: some View {
        let categoryID = model.category.id
        let isPinned = favorites.isPinned(categoryID)
        return Menu("Pin", systemImage: isPinned ? "pin.fill" : "pin") {
            Button(isPinned ? "Unpin Category" : "Pin Category", systemImage: isPinned ? "pin.slash" : "pin") {
                favorites.togglePin(categoryID)
            }
            if model.category.units.count > 1 {
                Button("Pin a Conversion…", systemImage: "arrow.left.arrow.right") {
                    isPinningPair = true
                }
            }
            if let pair = model.pair, favorites.isPinned(pair) {
                Button("Unpin This Conversion", systemImage: "pin.slash", role: .destructive) {
                    favorites.unpin(pair)
                }
            }
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private var decimalsMenu: some View {
        Menu("Decimal places", systemImage: "textformat.123") {
            Picker("Decimal places", selection: Binding(
                get: { model.decimals },
                set: { model.setDecimals($0) }
            )) {
                ForEach(ConverterModel.decimalChoices, id: \.self) { choice in
                    Text(choice.map { "\($0)" } ?? "Automatic").tag(choice)
                }
            }
        }
    }

    private func unitRow(_ index: Int) -> some View {
        let unit = model.category.units[index]
        let isActive = focusedRow == index
        return rowLayout {
            VStack(alignment: .leading, spacing: 2) {
                Text(unit.name)
                    .font(.headline)
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                Text(unit.symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The field carries the name and symbol, so VoiceOver reads each row once.
            .accessibilityHidden(true)

            VStack(alignment: .trailing, spacing: 4) {
                ValueField(
                    placeholder: model.placeholder,
                    // The symbol tells apart units that share a name ("Bust" in inches and in cm).
                    accessibilityName: unit.name == unit.symbol ? unit.name : "\(unit.name), \(unit.symbol)",
                    text: Binding(
                        get: { model.texts[index] },
                        set: { model.userEdited(row: index, text: $0) }
                    )
                )
                .focused($focusedRow, equals: index)
                .accessibilityAction(named: "Copy value") { copy(row: index) }

                // What typed math ("12*3", "5'11\"") worked out to.
                if let calculation = model.calculation, calculation.row == index {
                    Text(calculation.result)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 12)
                        .accessibilityLabel("Equals \(calculation.result.dropFirst(2))")
                }
            }
        }
        .cardStyle(isActive: isActive)
        .contextMenu {
            let value = model.texts[index].trimmingCharacters(in: .whitespaces)
            if !value.isEmpty {
                Button("Copy \(value)", systemImage: "doc.on.doc") {
                    copy(row: index)
                }
            }
        }
    }

    /// Put a row's value on the clipboard, if it has one.
    private func copy(row: Int) {
        let value = model.texts[row].trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        copyToPasteboard(value)
        copyCount += 1
    }

    /// Label beside field normally; at accessibility text sizes the label sits above a
    /// full-width field, so neither gets squeezed.
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    /// The input for a category's adjustable parameter, e.g. hours worked per week.
    private func paramRow(_ param: CategoryParam) -> some View {
        let isActive = focusedRow == Self.paramFocus
        return rowLayout {
            VStack(alignment: .leading, spacing: 2) {
                Text(param.label)
                    .font(.headline)
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                Text(model.paramError ?? param.caption)
                    .font(.subheadline)
                    .foregroundStyle(model.paramError == nil ? Color.secondary : Color.red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)

            ValueField(
                placeholder: UnitsRepository.format(param.defaultValue),
                accessibilityName: param.label,
                text: Binding(
                    get: { model.paramText },
                    set: { model.paramEdited($0) }
                )
            )
            // Say why an entry was ignored; the label already covers the "h/week" caption.
            .accessibilityHint(model.paramError ?? "")
            .focused($focusedRow, equals: Self.paramFocus)
        }
        .cardStyle(isActive: isActive)
    }
}

/// The right-aligned text field each row types into.
private struct ValueField: View {
    let placeholder: String
    let accessibilityName: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .valueKeyboard()
            .autocorrectionDisabled()
            .multilineTextAlignment(.trailing)
            .font(.body.monospacedDigit())
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.fieldBackground, in: .rect(cornerRadius: 10))
            .frame(maxWidth: .infinity)
            .accessibilityLabel(accessibilityName)
    }
}

/// A highlighted caveat banner shown above the unit rows.
private struct NoteBanner: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(Color(hex: "#92400E"))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "#FEF3C7"), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#FCD34D")))
    }
}

extension View {
    /// The rounded white card used for rows and tiles. An active card — the row being typed
    /// in — is outlined in the accent color.
    func cardStyle(isActive: Bool = false) -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.cardBackground, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(isActive ? 1 : 0)
            }
            .animation(.easeOut(duration: 0.15), value: isActive)
    }
}

extension Color {
    /// A color from a "#RRGGBB" string; the model stores category colors this way.
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// Choose two of a category's units to pin as a conversion on the home screen.
private struct PinPairSheet: View {
    let category: Category
    let onPin: (UnitPair) -> Void

    @State private var fromID: String
    @State private var toID: String
    @Environment(\.dismiss) private var dismiss

    init(category: Category, initialFrom: Int, onPin: @escaping (UnitPair) -> Void) {
        self.category = category
        self.onPin = onPin
        let units = category.units
        let from = units.indices.contains(initialFrom) ? initialFrom : 0
        // Default "to" is the next unit along, wrapping round to the first.
        let to = (from + 1) % units.count
        _fromID = State(initialValue: units[from].id)
        _toID = State(initialValue: units[to].id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    unitPicker("From", selection: $fromID)
                    unitPicker("To", selection: $toID)
                } footer: {
                    Text("Pinned conversions appear at the top of the home screen.")
                }
            }
            .navigationTitle("Pin a Conversion")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pin") {
                        onPin(UnitPair(categoryID: category.id, fromUnitID: fromID, toUnitID: toID))
                        dismiss()
                    }
                    .disabled(fromID == toID)
                }
            }
        }
    }

    private func unitPicker(_ title: LocalizedStringKey, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(category.units, id: \.id) { unit in
                Text(unit.name == unit.symbol ? unit.name : "\(unit.name) (\(unit.symbol))")
                    .tag(unit.id)
            }
        }
    }
}

#Preview {
    NavigationStack {
        if let model = ConverterModel(categoryID: "pay") {
            ConverterView(model: model)
        }
    }
    .environment(Favorites())
}
