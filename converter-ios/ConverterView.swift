import SwiftUI

/// Shows every unit in a category, each with its own input field. Typing a value into any
/// field instantly converts and fills in all the others.
struct ConverterView: View {
    @State private var model: ConverterModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                ForEach(model.category.units.indices, id: \.self) { index in
                    unitRow(index)
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
        }
        .onDisappear { model.save() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.save() }
        }
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
        return rowLayout {
            VStack(alignment: .leading, spacing: 2) {
                Text(unit.name)
                    .font(.headline)
                Text(unit.symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The field carries the name and symbol, so VoiceOver reads each row once.
            .accessibilityHidden(true)

            ValueField(
                placeholder: model.placeholder,
                // The symbol tells apart units that share a name ("Bust" in inches and in cm).
                accessibilityName: unit.name == unit.symbol ? unit.name : "\(unit.name), \(unit.symbol)",
                text: Binding(
                    get: { model.texts[index] },
                    set: { model.userEdited(row: index, text: $0) }
                )
            )
            .accessibilityAction(named: "Copy value") { copy(row: index) }
        }
        .cardStyle()
        .contextMenu {
            let value = model.texts[index].trimmingCharacters(in: .whitespaces)
            if !value.isEmpty {
                Button("Copy \(value)", systemImage: "doc.on.doc") {
                    copyToPasteboard(value)
                }
            }
        }
    }

    /// Put a row's value on the clipboard, if it has one.
    private func copy(row: Int) {
        let value = model.texts[row].trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        copyToPasteboard(value)
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
        rowLayout {
            VStack(alignment: .leading, spacing: 2) {
                Text(param.label)
                    .font(.headline)
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
        }
        .cardStyle()
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
    /// The rounded white card used for rows and tiles.
    func cardStyle() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.cardBackground, in: .rect(cornerRadius: 14))
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

#Preview {
    NavigationStack {
        if let model = ConverterModel(categoryID: "pay") {
            ConverterView(model: model)
        }
    }
}
