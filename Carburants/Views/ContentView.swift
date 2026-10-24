import CarburantsKit
import MapKit
import SwiftUI

/// Map with the stations, and their list over it, as in Plans: a sheet on a compact width (iPhone, iPhone Duo
/// closed or in Split View), the list over the map on a regular one (iPhone Duo open, iPad). From iOS 27.1 the
/// regular layout is an overlay arrangement, as Apple's iPhone Duo guidelines ask for a foreground over a
/// background: the system places the panel, and puts it beside the map, clear of the fold, when the iPhone Duo is
/// partly folded.
struct ContentView: View {
    @Bindable var model: StationsModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var detent: PresentationDetent = Self.middle
    @State private var framed = false

    private static let middle = PresentationDetent.fraction(0.42)
    private static let panelWidth: CGFloat = 420

    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        GeometryReader { proxy in
            if isRegular, #available(iOS 27.1, *) {
                ArrangedLayout(model: model, camera: $camera)
            } else {
                unfolded(height: proxy.size.height)
            }
        }
        .sheet(isPresented: .constant(!isRegular)) {
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

    /// Compact: the map full screen and the list in the sheet. Regular before iOS 27.1: the list in a side panel.
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

/// Regular width from iOS 27.1: the list over the map in an overlay arrangement. The system sizes and places the
/// panel, and lays the two side by side, away from the hinge, when an iPhone Duo is partly folded (book or tent).
@available(iOS 27.1, *)
private struct ArrangedLayout: View {
    @Bindable var model: StationsModel
    @Binding var camera: MapCameraPosition

    var body: some View {
        ArrangementView {
            StationBrowser(model: model)
                .overlayArrangementEdge(.leading)
        } secondary: {
            StationMap(model: model, camera: $camera)
                .ignoresSafeArea()
        }
        .arrangementViewStyle(.overlay)
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
