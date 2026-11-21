import CarburantsKit
import SwiftUI

/// The row of capsules under the search field, as Plans' suggestions under its own: the sort order, then the
/// fuels of the car, each turned on or off with a touch.
struct QuickFilters: View {
    @Bindable var model: StationsModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("Moins cher", symbol: "eurosign", on: model.sort == .price) {
                    model.setSort(.price)
                }
                chip("Plus proche", symbol: "location.fill", on: model.sort == .distance) {
                    model.setSort(.distance)
                }

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 2)

                ForEach(Fuel.allCases) { fuel in
                    fuelChip(fuel)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: model.sort)
        .sensoryFeedback(.selection, trigger: model.fuels)
    }

    private func chip(_ title: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .labelStyle(ChipLabelStyle())
                .foregroundStyle(on ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(on ? Color.blue : Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func fuelChip(_ fuel: Fuel) -> some View {
        let on = model.fuels.contains(fuel)
        return Button {
            withAnimation(.snappy) { model.toggleFuel(fuel) }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(on ? fuel.textColor.opacity(0.85) : fuel.color)
                    .frame(width: 8, height: 8)
                Text(fuel.short)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(on ? fuel.textColor : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(on ? fuel.color : Color(.tertiarySystemFill), in: Capsule())
            .overlay {
                if on { Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1) }
            }
        }
        .buttonStyle(.plain)
        // The last fuel stays on (setFuels ignores an empty list): the list needs at least one.
        .accessibilityLabel(fuel.summary)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Symbol and title closer together than the default label, as in Plans' capsules.
private struct ChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}
