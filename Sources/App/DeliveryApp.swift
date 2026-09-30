import MapKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class DeliveryStore: NSObject, ObservableObject, CLLocationManagerDelegate {
  @Published var stops = Stop.sample
  @Published var location: CLLocationCoordinate2D?
  @Published var locationStatus = "Location off"
  @Published var error: String?
  @Published var simulation = false
  private let manager = CLLocationManager()
  private let file = FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(
      (ProcessInfo.processInfo.environment["PORTFOLIO_UI_TEST"].map { "UITests/" + $0 + "/" } ?? "")
        + "DeliveryCompanion/stops.json")
  private var canSave = true
  override init() {
    super.init()
    manager.delegate = self
    do { stops = try JSONDecoder().decode([Stop].self, from: Data(contentsOf: file)) } catch let e
      as CocoaError where e.code == .fileReadNoSuchFile
    {} catch {
      canSave = false
      self.error = "Saved deliveries could not be opened. The original file is preserved."
    }
  }
  func mutate(_ id: String, change: (inout Stop) throws -> Void) {
    guard canSave, let index = stops.firstIndex(where: { $0.id == id }) else { return }
    do {
      var next = stops
      try change(&next[index])
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(next).write(to: file, options: [.atomic, .completeFileProtection])
      stops = next
    } catch { self.error = error.localizedDescription }
  }
  func enableLocation() {
    simulation = false
    manager.requestWhenInUseAuthorization()
    manager.startUpdatingLocation()
  }
  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let authorization = manager.authorizationStatus
    Task { @MainActor in
      switch authorization {
      case .authorizedWhenInUse, .authorizedAlways: locationStatus = "Device location"
      case .denied, .restricted: locationStatus = "Location unavailable · use Maps or sample route"
      default: break
      }
    }
  }
  nonisolated func locationManager(
    _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
  ) {
    let coordinate = locations.last?.coordinate
    Task { @MainActor in if !self.simulation { self.location = coordinate } }
  }
  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    let message = error.localizedDescription
    Task { @MainActor in self.locationStatus = message }
  }
  func simulate(_ stop: Stop) {
    manager.stopUpdatingLocation()
    simulation = true
    locationStatus = "Simulated position"
    location = CLLocationCoordinate2D(
      latitude: stop.latitude - 0.002, longitude: stop.longitude + 0.002)
  }
}
@main struct DeliveryApp: App {
  @StateObject var store = DeliveryStore()
  var body: some Scene { WindowGroup { RouteList().environmentObject(store).tint(.indigo) } }
}
struct RouteList: View {
  @EnvironmentObject var store: DeliveryStore
  var body: some View {
    NavigationView {
      List {
        Section {
          VStack(alignment: .leading, spacing: 10) {
            Text("Today’s route").font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text("Three sample stops in San Francisco").foregroundColor(.secondary)
            ProgressView(
              value: Double(store.stops.filter { $0.status == "Delivered" }.count), total: 3)
            Text("\(store.stops.filter { $0.status == "Delivered" }.count) of 3 delivered").font(
              .caption)
          }.padding(.vertical, 8)
        }
        Section("Assigned stops") {
          ForEach(Array(store.stops.enumerated()), id: \.element.id) { index, stop in
            NavigationLink {
              StopDetail(id: stop.id)
            } label: {
              HStack(spacing: 14) {
                Text(String(index + 1)).font(.headline).frame(width: 34, height: 34).background(
                  Color.indigo.opacity(0.12)
                ).clipShape(Circle())
                VStack(alignment: .leading, spacing: 6) {
                  Text(stop.business).font(.headline)
                  Text(stop.address).font(.subheadline).foregroundColor(.secondary)
                  Text(stop.status).font(.caption.weight(.medium)).foregroundColor(
                    stop.status == "Delivered" ? .green : .indigo)
                }
              }.padding(.vertical, 6)
            }
          }
        }
        Section {
          Label(store.locationStatus, systemImage: "location")
          Button("Enable device location") { store.enableLocation() }
          Text(
            "Sample assignments. Location stays on this device; nothing is sent to a dispatcher."
          ).font(.footnote).foregroundColor(.secondary)
        }
      }.listStyle(.insetGrouped).navigationTitle("Delivery Companion")
        .navigationBarTitleDisplayMode(.inline)
    }.navigationViewStyle(.stack).alert(
      "Delivery could not be saved",
      isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
    ) {
      Button("OK") { store.error = nil }
    } message: {
      Text(store.error ?? "")
    }
  }
}
struct StopDetail: View {
  @EnvironmentObject var store: DeliveryStore
  let id: String
  @State var recipient = ""
  @State var note = ""
  @State var photo: Data?
  @State var importing = false
  @State var route: MKRoute?
  @State var routeError: String?
  @State var calculating = false
  var body: some View {
    if let stop = store.stops.first(where: { $0.id == id }) {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          RouteMap(stop: stop, location: store.location, route: route).frame(height: 270)
            .cornerRadius(16)
          Text(stop.business).font(.title.weight(.semibold))
          Text(stop.address).foregroundColor(.secondary)
          Label(
            stop.status,
            systemImage: stop.status == "Delivered" ? "checkmark.circle" : "shippingbox"
          ).font(.headline)
          HStack {
            Button("Directions") {
              let item = MKMapItem(
                placemark: MKPlacemark(
                  coordinate: CLLocationCoordinate2D(
                    latitude: stop.latitude, longitude: stop.longitude)))
              item.name = stop.business
              item.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
              ])
            }
            Spacer()
            Button("Sample position") { store.simulate(stop) }
          }.buttonStyle(.bordered)
          if let location = store.location {
            Button(calculating ? "Calculating…" : "Preview route") {
              calculating = true
              Task {
                do {
                  let request = MKDirections.Request()
                  request.source = MKMapItem(placemark: MKPlacemark(coordinate: location))
                  request.destination = MKMapItem(
                    placemark: MKPlacemark(
                      coordinate: CLLocationCoordinate2D(
                        latitude: stop.latitude, longitude: stop.longitude)))
                  request.transportType = .automobile
                  route = try await MKDirections(request: request).calculate().routes.first
                  routeError = nil
                } catch { routeError = error.localizedDescription }
                calculating = false
              }
            }.disabled(calculating)
          }
          if let route {
            Text(
              "\(Int(route.distance/1000)) km · about \(Int(route.expectedTravelTime/60)) minutes"
            ).font(.subheadline)
          }
          if let routeError { Text(routeError).font(.caption).foregroundColor(.secondary) }
          Divider()
          if stop.status == "Assigned" {
            Button("Mark arrived") { store.mutate(id) { $0.arrive() } }.buttonStyle(
              .borderedProminent)
          } else if stop.status == "Arrived" {
            Text("Proof of delivery").font(.title3.weight(.semibold))
            TextField("Recipient name", text: $recipient).textFieldStyle(.roundedBorder)
            TextField("Delivery note", text: $note).textFieldStyle(.roundedBorder)
            Button(photo == nil ? "Attach delivery photo" : "Replace photo") { importing = true }
            if let photo, let image = UIImage(data: photo) {
              Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).cornerRadius(12)
            }
            Button("Complete delivery") {
              store.mutate(id) { try $0.complete(recipient: recipient, note: note, proof: photo) }
            }.buttonStyle(.borderedProminent).disabled(
              recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photo == nil)
          } else {
            Text("Received by \(stop.recipient)").font(.headline)
            Text(stop.note)
            if let date = stop.completedAt {
              Text(date, style: .date)
              Text(date, style: .time)
            }
            if let data = stop.proof, let image = UIImage(data: data) {
              Image(uiImage: image).resizable().scaledToFit().cornerRadius(12)
            }
          }
        }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
      }.navigationTitle(stop.id).navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.jpeg, .png]) { result in
          do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard data.count <= 5_000_000, UIImage(data: data) != nil else {
              throw CocoaError(.fileReadCorruptFile)
            }
            photo = data
          } catch { store.error = error.localizedDescription }
        }
    }
  }
}
struct RouteMap: UIViewRepresentable {
  let stop: Stop
  let location: CLLocationCoordinate2D?
  let route: MKRoute?
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeUIView(context: Context) -> MKMapView {
    let map = MKMapView()
    map.delegate = context.coordinator
    return map
  }
  func updateUIView(_ map: MKMapView, context: Context) {
    map.removeAnnotations(map.annotations)
    map.removeOverlays(map.overlays)
    let pin = MKPointAnnotation()
    pin.coordinate = CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)
    pin.title = stop.business
    map.addAnnotation(pin)
    if let location {
      let driver = MKPointAnnotation()
      driver.coordinate = location
      driver.title = "Current position"
      map.addAnnotation(driver)
    }
    if let route {
      map.addOverlay(route.polyline)
      map.setVisibleMapRect(
        route.polyline.boundingMapRect,
        edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40), animated: true)
    } else {
      map.showAnnotations(map.annotations, animated: false)
    }
  }
  final class Coordinator: NSObject, MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
      let renderer = MKPolylineRenderer(overlay: overlay)
      renderer.strokeColor = .systemIndigo
      renderer.lineWidth = 5
      return renderer
    }
  }
}
