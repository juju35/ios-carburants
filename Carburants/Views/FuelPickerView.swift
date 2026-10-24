import CarburantsKit
import SwiftUI

/// The fuels your car takes (at least one); the price sort uses the cheapest of them at each station.
struct FuelPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<Fuel>
    private let onDone: ([Fuel]) -> Void

    init(selection: [Fuel], onDone: @escaping ([Fuel]) -> Void) {
        _selection = State(initialValue: Set(selection))
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Fuel.allCases) { fuel in
                        Toggle(isOn: binding(fuel)) {
                            HStack(spacing: 12) {
                                FuelBadge(fuel, large: true)
                                    .frame(minWidth: 44)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(fuel.label)
                                    Text(fuel.euCode.isEmpty ? fuel.summary : "\(fuel.summary) · \(fuel.euCode)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(selection == [fuel])
                    }
                } footer: {
                    Text("Le tri par prix retient le moins cher de vos carburants dans chaque station. Gardez-en au moins un.")
                }
            }
            .navigationTitle("Carburants du véhicule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        onDone(Fuel.allCases.filter(selection.contains))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func binding(_ fuel: Fuel) -> Binding<Bool> {
        Binding {
            selection.contains(fuel)
        } set: { isOn in
            if isOn { selection.insert(fuel) } else if selection.count > 1 { selection.remove(fuel) }
        }
    }
}

#Preview {
    FuelPickerView(selection: [.gazole]) { _ in }
}
