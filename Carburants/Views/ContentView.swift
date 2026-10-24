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
            StationBrowser(model: model, showsFuelButton: false)
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
            // The map fills the whole screen, under the status bar wherever it is (on the side on iPhone Duo), and
            // keeps its controls and framing inside the safe area, to which the list's room is added so stations
            // are not framed under it.
            if isRegular {
                StationMap(model: model, camera: $camera)
                    .safeAreaPadding(.leading, Self.panelWidth + 24)
                    .ignoresSafeArea()
            } else {
                // Compact: the fuel button goes in the bar over the map, under the status bar (on the side of the
                // iPhone Duo's cover screen, with the other bar buttons; top right elsewhere).
                NavigationStack {
                    StationMap(model: model, camera: $camera)
                        .safeAreaPadding(.bottom, height * 0.42)
                        .ignoresSafeArea()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) { FuelButton(model: model) }
                        }
                        .toolbarBackground(.hidden, for: .navigationBar)
                }
            }

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

/// iPhone Duo partly folded, around 90°: the map fills the screen and the list sits in a glass panel on one side
/// of the fold, as the side panel does, so nothing straddles the fold:
/// - book pose (fold down the screen): the list takes the leading half, the map shows in the trailing one;
/// - laptop pose (fold across the screen): the map stands up above the fold, the list lies below it, within reach.
private struct FoldedLayout: View {
    @Bindable var model: StationsModel
    @Binding var camera: MapCameraPosition
    let fold: CGRect
    let size: CGSize

    /// Clear space kept on each side of the hinge band, and around the panel.
    private static let gap: CGFloat = 12

    var body: some View {
        let stacked = fold.width >= fold.height
        ZStack(alignment: stacked ? .bottom : .leading) {
            // Stations framed in the half the list leaves free.
            StationMap(model: model, camera: $camera)
                .safeAreaPadding(stacked ? .bottom : .leading, stacked ? size.height - fold.minY + Self.gap : fold.maxX + Self.gap)
                .ignoresSafeArea()

            StationBrowser(model: model)
                .frame(
                    width: stacked ? nil : max(0, fold.minX - Self.gap * 2),
                    height: stacked ? max(0, size.height - fold.maxY - Self.gap * 2) : nil
                )
                .frame(maxWidth: stacked ? .infinity : nil, maxHeight: stacked ? nil : .infinity)
                .modifier(PanelBackground())
                .padding(Self.gap)
        }
        .animation(.smooth, value: fold)
    }
}

/// Opens the fuel picker, from the bar over the map.
private struct FuelButton: View {
    @Bindable var model: StationsModel

    var body: some View {
        Button {
            model.showsFuelPicker = true
        } label: {
            Label(Format.fuels(model.fuels), systemImage: "fuelpump")
        }
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
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        if #available(iOS 26, *) {
            // Clipped too: the list's rows and bars stay inside the glass's rounded corners.
            content
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
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
