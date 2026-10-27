import CarburantsKit
import MapKit
import SwiftUI

/// Main screen of the application:
/// - on portrait and compact screens (iPhone): the map full screen, the stations in an interactive drawer sheet;
/// - on landscape screens (iPad, Mac): the map full screen, the stations in a collapsible floating side panel;
/// - on iPhone Duo folded: the map and the stations each occupy one side of the fold.
struct ContentView: View {
    @Bindable var model: StationsModel

    private static let middle: PresentationDetent = .fraction(0.42)
    private static let panelWidth: CGFloat = 380

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var detent: PresentationDetent = Self.middle
    @State private var framed = false
    @State private var isPanelVisible = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        GeometryReader { proxy in
            let hinge = Fold.band(in: proxy)
            let isRegular = horizontalSizeClass == .regular
            let portrait = proxy.size.height > proxy.size.width

            Group {
                if let hinge {
                    FoldedLayout(
                        model: model,
                        camera: $camera,
                        fold: hinge,
                        size: proxy.size,
                        insets: proxy.safeAreaInsets
                    )
                } else if isRegular && !portrait {
                    landscapeUnfolded
                } else {
                    portraitUnfolded(height: proxy.size.height)
                }
            }
        }
        .ignoresSafeArea()
        .task {
            // First fix if already authorized, or shows the explanation screen.
            model.location.start()
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
            if detent == .large, !Demo.isOn { detent = Self.middle }
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            withAnimation(.smooth) {
                camera = .region(MKCoordinateRegion(center: station.coordinate, latitudinalMeters: 1_500, longitudinalMeters: 1_500))
            }
        }
        .onChange(of: model.customLocation) { _, location in
            if let location {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    detent = Self.middle
                    camera = .region(MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 12_000, longitudinalMeters: 12_000))
                }
            } else {
                withAnimation {
                    camera = .userLocation(fallback: .automatic)
                }
            }
        }
        .onChange(of: camera) { _, newCamera in
            if newCamera.followsUserLocation {
                if model.customTownName != nil || model.customLocation != nil {
                    model.resetToCurrentLocation()
                } else {
                    model.refresh()
                }
            }
        }
        .onChange(of: model.isSearching) { _, searching in
            withAnimation(.smooth) {
                if searching {
                    detent = .large
                } else if detent == .large {
                    detent = Self.middle
                }
            }
        }
        .onChange(of: detent) { _, newDetent in
            if newDetent != .large, model.isSearching {
                model.isSearching = false
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }

    /// Regular width in landscape: the map with a collapsible floating side panel on the left.
    private var landscapeUnfolded: some View {
        ZStack(alignment: .topLeading) {
            StationMap(model: model, camera: $camera)
                .safeAreaPadding(.leading, isPanelVisible ? Self.panelWidth + 24 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPanelVisible)
                .ignoresSafeArea()

            if !isPanelVisible {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isPanelVisible = true
                    }
                } label: {
                    Label("Stations", systemImage: "sidebar.leading")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .modifier(PanelBackground())
                .padding(12)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            StationBrowser(model: model, inlineSearch: false) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isPanelVisible = false
                }
            }
            .frame(width: Self.panelWidth)
            .modifier(PanelBackground())
            .padding(12)
            .offset(x: isPanelVisible ? 0 : -Self.panelWidth - 24)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPanelVisible)
        }
    }

    /// Portrait or compact width: the map full screen, the list in a sheet with detents over it.
    private func portraitUnfolded(height: CGFloat) -> some View {
        StationMap(model: model, camera: $camera)
            .safeAreaPadding(.bottom, height * 0.42)
            .ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                StationBrowser(model: model, inlineSearch: true)
                    .presentationDetents([.height(110), Self.middle, .large], selection: $detent)
                    .presentationBackgroundInteraction(.enabled(upThrough: Self.middle))
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
                    .modifier(DisableVerticalToolbarModifier())
            }
    }
}

/// iPhone Duo partly folded, around 90°: the map and the list each take one side of the fold without borders:
/// - book pose (fold down the screen): the list takes the full left screen edge-to-edge, the map shows in the trailing one;
/// - laptop pose (fold across the screen): the map stands up above the fold, the list lies below it. When searching,
///   the list moves to the top screen so the keyboard on the bottom screen does not hide what the user is typing.
private struct FoldedLayout: View {
    @Bindable var model: StationsModel
    @Binding var camera: MapCameraPosition
    let fold: CGRect
    let size: CGSize
    let insets: EdgeInsets

    var body: some View {
        let stacked = fold.width >= fold.height
        let searchInLaptop = stacked && model.isSearching

        let topPadding: CGFloat = stacked ? (searchInLaptop ? insets.top : 0) : insets.top
        let bottomPadding: CGFloat = stacked ? (searchInLaptop ? 0 : insets.bottom) : insets.bottom

        ZStack(alignment: .topLeading) {
            // Stations framed in the half the list leaves free.
            StationMap(model: model, camera: $camera)
                .safeAreaPadding(
                    stacked ? (searchInLaptop ? .top : .bottom) : .leading,
                    stacked ? (searchInLaptop ? fold.maxY : size.height - fold.minY) : fold.maxX
                )
                .ignoresSafeArea()

            StationBrowser(model: model, inlineSearch: true)
                .ignoresSafeArea(edges: .top)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
                .background(Color(.systemBackground))
                .frame(
                    width: stacked ? size.width : fold.minX,
                    height: stacked ? (searchInLaptop ? fold.minY : max(0, size.height - fold.maxY)) : size.height
                )
                .offset(
                    x: 0,
                    y: stacked ? (searchInLaptop ? 0 : fold.maxY) : 0
                )
                .ignoresSafeArea(.keyboard)
        }
        .animation(.smooth, value: fold)
        .animation(.smooth, value: searchInLaptop)
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
            content
                .glassEffect(.regular, in: shape)
                .clipShape(shape)
                .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .clipShape(shape)
                .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        }
    }
}
