import SwiftUI
import UIKit

/// Shows every unit in a category, each with its own input field. Typing a value into any
/// field instantly converts and fills in all the others.
struct ConverterView: View {
    @State private var model: ConverterModel
    @Environment(\.scenePhase) private var scenePhase

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
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(model.category.name)
        .navigationBarTitleDisplayMode(.inline)
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
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(unit.name)
                    .font(.headline)
                Text(unit.symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ValueField(
                placeholder: model.placeholder,
                accessibilityName: unit.name,
                text: Binding(
                    get: { model.texts[index] },
                    set: { model.userEdited(row: index, text: $0) }
                )
            )
        }
        .cardStyle()
        .contextMenu {
            let value = model.texts[index].trimmingCharacters(in: .whitespaces)
            if !value.isEmpty {
                Button("Copy \(value)", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = value
                }
            }
        }
    }

    /// The input for a category's adjustable parameter, e.g. hours worked per week.
    private func paramRow(_ param: CategoryParam) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(param.label)
                    .font(.headline)
                Text(model.paramError ?? param.caption)
                    .font(.subheadline)
                    .foregroundStyle(model.paramError == nil ? Color.secondary : Color.red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ValueField(
                placeholder: UnitsRepository.format(param.defaultValue),
                accessibilityName: param.label,
                text: Binding(
                    get: { model.paramText },
                    set: { model.paramEdited($0) }
                )
            )
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
        // A keyboard with digits, "-", "." and ":" covers both numbers and Clock's times.
        TextField(placeholder, text: $text)
            .keyboardType(.numbersAndPunctuation)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .multilineTextAlignment(.trailing)
            .font(.body.monospacedDigit())
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
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
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
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
