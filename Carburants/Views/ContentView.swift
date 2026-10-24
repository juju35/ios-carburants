import CarburantsKit
import MapKit
import SwiftUI

/// Map with the stations, and their list over it, as in Plans: a sheet on a compact width (iPhone, iPhone Duo
/// folded or in Split View), a floating side panel on a regular one (iPhone Duo unfolded, iPad).
struct ContentView: View {
    @Bindable var model: StationsModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var detent: PresentationDetent = Self.middle
    @State private var framed = false

    private static let middle = PresentationDetent.fraction(0.42)
    private static let panelWidth: CGFloat = 380

    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                // The map draws under the bars by itself and keeps its controls and framing inside the safe area,
                // to which the list's room is added so stations are not framed under it.
                StationMap(model: model, camera: $camera)
                    .safeAreaPadding(isRegular ? .leading : .bottom, isRegular ? Self.panelWidth + 24 : proxy.size.height * 0.42)

                if isRegular {
                    StationBrowser(model: model)
                        .frame(width: Self.panelWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 16, y: 4)
                        .padding(12)
                }
            }
        }
        .sheet(isPresented: .constant(!isRegular)) {
            StationBrowser(model: model)
                .presentationDetents([.height(110), Self.middle, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: Self.middle))
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
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
            if !isRegular, detent == .large { detent = Self.middle }
            withAnimation(.smooth) {
                camera = .region(MKCoordinateRegion(center: station.coordinate, latitudinalMeters: 1_500, longitudinalMeters: 1_500))
            }
        }
    }
}

#Preview {
    ContentView(model: .shared)
}
