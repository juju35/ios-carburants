import SwiftUI
import WidgetKit

public extension Color {
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

public extension Fuel {
    var color: Color { Color(rgb: rgb) }
    var textColor: Color { darkText ? Color(rgb: 0x1A1A1A) : .white }
}

public extension Opening.State {
    var color: Color {
        switch self {
        case .open, .always: .green
        case .automate: .orange
        case .closed: .red
        }
    }
}

/// The fuel's pump colour with its short name, as on the pump.
public struct FuelBadge: View {
    private let fuel: Fuel
    private let large: Bool

    public init(_ fuel: Fuel, large: Bool = false) {
        self.fuel = fuel
        self.large = large
    }

    public var body: some View {
        Text(fuel.short)
            .font(large ? .footnote.weight(.bold) : .caption2.weight(.bold))
            .foregroundStyle(fuel.textColor)
            .padding(.horizontal, large ? 7 : 5)
            .padding(.vertical, large ? 3 : 1.5)
            .background(fuel.color, in: RoundedRectangle(cornerRadius: large ? 6 : 4, style: .continuous))
            .accessibilityLabel(fuel.summary)
    }
}

/// The station's logo on a rounded tile, like an app icon; the brand's initials when there is none.
public struct StationLogo: View {
    private let station: Station
    private let size: CGFloat

    public init(_ station: Station, size: CGFloat = 44) {
        self.station = station
        self.size = size
    }

    public var body: some View {
        let store = LogoStore.shared
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        ZStack {
            switch store.artwork(for: station) {
            case let .logo(image, dark):
                (dark ? Color(rgb: 0x202124) : Color.white)
                logo(image)
                    .scaledToFit()
                    .padding(size * 0.12)
            case let .initials(text):
                placeholder
                Text(text)
                    .font(.system(size: size * (text.count > 1 ? 0.36 : 0.44), weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            case .generic:
                placeholder
                Image(systemName: "fuelpump.fill")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        // Redraw when downloaded logos arrive.
        .id(store.revision)
        .accessibilityHidden(true)
    }

    /// In a widget shown tinted or clear (Home Screen, CarPlay), the logo follows the tint instead of
    /// staying in colour.
    @ViewBuilder
    private func logo(_ uiImage: UIImage) -> some View {
        let image = Image(uiImage: uiImage).resizable().interpolation(.high)
        if #available(iOS 18, *) {
            image.widgetAccentedRenderingMode(.accentedDesaturated)
        } else {
            image
        }
    }

    // Grey gradient, as Contacts draws a contact without a photo.
    private var placeholder: some View {
        LinearGradient(colors: [Color(white: 0.64), Color(white: 0.5)], startPoint: .top, endPoint: .bottom)
    }
}

/// "1,749 €" with the euro sign a little smaller, in tabular figures.
public struct PriceText: View {
    private let price: Double
    private let font: Font

    public init(_ price: Double, font: Font = .title3) {
        self.price = price
        self.font = font
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(Format.priceNumber(price)).font(font.weight(.semibold))
            Text("€").font(.caption.weight(.semibold))
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Format.price(price))
    }
}

public extension Station {
    /// Made-up stations for previews, widget placeholders and screenshots.
    static let samples: [Station] = {
        let updated = Date().addingTimeInterval(-1800)
        func fuels(_ prices: [Fuel: Double]) -> [Fuel: FuelPrice] {
            prices.mapValues { FuelPrice(price: $0, updated: updated, available: true, rupture: nil, ruptureSince: nil) }
        }
        func days(_ open: String, _ close: String) -> [DayHours] {
            (1...7).map { DayHours(day: $0, closed: false, ranges: [TimeRange(open: open, close: close)]) }
        }
        let week = days("07:00", "21:00")
        return [
            Station(
                id: 35000001, address: "Route de Lorient", postcode: "35000", city: "Rennes",
                latitude: 48.1046, longitude: -1.7240, automate24: true, hours: week,
                services: ["Boutique alimentaire", "Lavage automatique", "Gonflage"],
                fuels: fuels([.gazole: 1.689, .e10: 1.729, .sp98: 1.819]), distanceKm: 1.2,
                name: "E.Leclerc Rennes", brand: "E.Leclerc"
            ),
            Station(
                id: 35000002, address: "Avenue Gros Malhon", postcode: "35000", city: "Rennes",
                latitude: 48.1270, longitude: -1.6930, hours: week,
                services: ["Boutique alimentaire", "Toilettes publiques"],
                fuels: fuels([.gazole: 1.709, .e10: 1.749, .e85: 0.829]), distanceKm: 2.4,
                name: "Super U Rennes", brand: "Super U"
            ),
            Station(
                id: 35510001, address: "Rue de Paris", postcode: "35510", city: "Cesson-Sévigné",
                latitude: 48.1180, longitude: -1.6050, automate24: true, hours: week,
                services: ["Lavage manuel"],
                fuels: fuels([.gazole: 1.725, .e10: 1.759, .sp98: 1.839]), distanceKm: 3.8,
                name: "Intermarché Cesson", brand: "Intermarché"
            ),
            Station(
                id: 35000003, address: "Rocade Nord", postcode: "35000", city: "Rennes",
                latitude: 48.1350, longitude: -1.6700, highway: true, hours: days("00:00", "23:59"),
                services: ["Boutique alimentaire", "Restauration à emporter", "Wifi"],
                fuels: fuels([.gazole: 1.849, .e10: 1.879, .sp98: 1.959]), distanceKm: 4.6,
                name: "TotalEnergies Rennes Nord", brand: "TotalEnergies"
            ),
            Station(
                id: 35760001, address: "Rue de Rennes", postcode: "35760", city: "Saint-Grégoire",
                latitude: 48.1510, longitude: -1.6850, hours: week,
                fuels: fuels([.gazole: 1.739, .e10: 1.769]), distanceKm: 5.3,
                name: "Carrefour Market Saint-Grégoire", brand: "Carrefour Market"
            ),
            Station(
                id: 35200001, address: "Boulevard Oscar Leroux", postcode: "35200", city: "Rennes",
                latitude: 48.0950, longitude: -1.6620, hours: week,
                fuels: fuels([.gazole: 1.759, .sp98: 1.869]), distanceKm: 5.9,
                name: "Esso Rennes Sud", brand: "Esso"
            ),
        ]
    }()
}
