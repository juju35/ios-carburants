import CarburantsKit
import SwiftUI

/// Settings: fuels taken by the car, and preferred navigation app for directions.
struct FuelPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<Fuel>
    @State private var navigationApp: NavigationApp
    private let onDone: ([Fuel], NavigationApp) -> Void

    init(
        selection: [Fuel],
        navigationApp: NavigationApp = Preferences.shared.navigationApp,
        onDone: @escaping ([Fuel], NavigationApp) -> Void
    ) {
        self.selection = Set(selection)
        self._navigationApp = State(initialValue: navigationApp)
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
                } header: {
                    Text("Carburants du véhicule")
                } footer: {
                    Text("Le tri par prix retient le moins cher de vos carburants dans chaque station. Gardez-en au moins un.")
                }

                Section {
                    Picker("Application d’itinéraire", selection: $navigationApp) {
                        ForEach(NavigationApp.allCases) { app in
                            Label(app.title, systemImage: app.symbol).tag(app)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Application d’itinéraire")
                } footer: {
                    Text("Application lancée en touchant le bouton Itinéraire.")
                }
            }
            .navigationTitle("Préférences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        onDone(Fuel.allCases.filter(selection.contains), navigationApp)
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
    FuelPickerView(selection: [.gazole], navigationApp: .appleMaps) { _, _ in }
}
