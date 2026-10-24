import CarburantsKit
import MapKit
import SwiftUI

/// Map with the stations, and their list over it, as in Plans: a sheet on a compact width (iPhone, iPhone Duo
/// closed or in Split View), a floating side panel on a regular one (iPhone Duo open flat, iPad). iPhone Duo partly
/// folded (around 90°): the map and the list each take one side of the fold, see `FoldedLayout`.
struct ContentView: View {
    @Bindable var model: StationsModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var detent: PresentationDetent = Self.middle
    @State private var framed = false
    /// The hinge band while an iPhone Duo is partly folded, nil otherwise.
    @State private var fold: CGRect?

    private static let middle = PresentationDetent.fraction(0.42)
    private static let panelWidth: CGFloat = 420

    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        GeometryReader { proxy in
            let hinge = Fold.band(in: proxy)
            Group {
                if let hinge {
                    FoldedLayout(model: model, camera: $camera, fold: hinge, size: proxy.size)
                } else {
                    unfolded(height: proxy.size.height)
                }
            }
            .onChange(of: hinge, initial: true) { _, band in fold = band }
        }
        // Partly folded, the list has its own half of the screen: no sheet.
        .sheet(isPresented: .constant(!isRegular && fold == nil)) {
            StationBrowser(model: model)
                .presentationDetents([.height(110), Self.middle, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: Self.middle))
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
        }
        .onAppear {
            if Demo.isOn, Demo.screen == .detail { detent = .large }
        }
        .onChange(of: model.stations == nil) { _, cleared in
            if cleared { framed = false }
        }
        .onChange(of: model.updatedAt) {
            // Frame the stations once per list (first search, other fuels), not on every refresh.
            guard !framed, model.stations?.isEmpty == false else { return }
            framed = true
            withAnimation { camera = .automatic }
        }
        .onChange(of: model.selectedID) { _, id in
            guard let station = model.station(id) else { return }
            if !isRegular, detent == .large, !Demo.isOn { detent = Self.middle }
            withAnimation(.smooth) {
                camera = .region(MKCoordinateRegion(center: station.coordinate, latitudinalMeters: 1_500, longitudinalMeters: 1_500))
            }
        }
    }

    /// Flat or closed: the map full screen, the list in the sheet or the side panel.
    private func unfolded(height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // The map draws under the bars by itself and keeps its controls and framing inside the safe area,
            // to which the list's room is added so stations are not framed under it.
            StationMap(model: model, camera: $camera)
                .safeAreaPadding(isRegular ? .leading : .bottom, isRegular ? Self.panelWidth + 24 : height * 0.42)

            if isRegular {
                StationBrowser(model: model)
                    .frame(width: Self.panelWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .modifier(PanelBackground())
                    .padding(12)
            }
        }
    }
}

/// iPhone Duo partly folded, around 90°. Nothing straddles the fold:
/// - laptop / tabletop pose (fold across the screen): the map stands up above the fold, the list lies below it,
///   within reach, as Apple's apps put the picture up and the controls down;
/// - book pose (fold down the screen): the list on the leading side, the map on the trailing one.
private struct FoldedLayout: View {
    @Bindable var model: StationsModel
    @Binding var camera: MapCameraPosition
    let fold: CGRect
    let size: CGSize

    /// Clear space kept on each side of the hinge band.
    private static let gap: CGFloat = 12

    var body: some View {
        let stacked = fold.width >= fold.height
        let first = stacked
            ? CGRect(x: 0, y: 0, width: size.width, height: max(0, fold.minY - Self.gap))
            : CGRect(x: 0, y: 0, width: max(0, fold.minX - Self.gap), height: size.height)
        let second = stacked
            ? CGRect(x: 0, y: fold.maxY + Self.gap, width: size.width, height: max(0, size.height - fold.maxY - Self.gap))
            : CGRect(x: fold.maxX + Self.gap, y: 0, width: max(0, size.width - fold.maxX - Self.gap), height: size.height)

        ZStack(alignment: .topLeading) {
            Color(.systemBackground)
            if stacked {
                place(StationMap(model: model, camera: $camera), in: first)
                place(StationBrowser(model: model), in: second)
            } else {
                place(StationBrowser(model: model), in: first)
                place(StationMap(model: model, camera: $camera), in: second)
            }
        }
        .animation(.smooth, value: fold)
    }

    private func place(_ view: some View, in rect: CGRect) -> some View {
        view
            .frame(width: rect.width, height: rect.height)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .offset(x: rect.minX, y: rect.minY)
    }
}

/// The fold of an iPhone Duo (iOS 27.1 reserved regions), only while it is partly folded: the division region is
/// inactive, and not returned, when the device is closed or open flat.
private enum Fold {
    static func band(in proxy: GeometryProxy) -> CGRect? {
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 27.1, *) {
            return proxy.reservedRegions(kind: .division).first?.frame
        }
        #endif
        return nil
    }
}

/// Liquid Glass from iOS 26, a material before.
private struct PanelBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .clipShape(shape)
                .shadow(color: .black.opacity(0.15), radius: 16, y: 4)
        }
    }
}

#Preview {
    ContentView(model: .shared)
}
