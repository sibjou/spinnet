import SwiftUI
import MapKit
import CoreLocation

// MARK: - Найденное место
struct PlaceCandidate: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let latitude: Double
    let longitude: Double
}

// MARK: - Предложить место встречи
// Три способа: найти по названию (клуб, парк), поставить точку на карте нажатием
// или просто написать название. Разрешение на геолокацию не нужно.
struct ProposePlaceSheet: View {
    let city: String
    let currentLatitude: Double?
    let currentLongitude: Double?
    let onSend: (_ name: String, _ latitude: Double?, _ longitude: Double?, _ note: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool

    @State private var query = ""
    @State private var results: [PlaceCandidate] = []
    @State private var isSearching = false
    @State private var searchMessage: String? = nil

    @State private var name = ""
    @State private var autoName = ""
    @State private var note = ""
    @State private var moderationMessage: String? = nil
    @State private var pin: CLLocationCoordinate2D? = nil
    @State private var position: MapCameraPosition = .automatic

    private static let nameLimit = 80
    private static let noteLimit = 140

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var markerTitle: String { trimmedName.isEmpty ? "Здесь" : trimmedName }
    private var showsResults: Bool { !results.isEmpty || searchMessage != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar

                ZStack {
                    mapView
                    if showsResults {
                        resultsList
                    }
                }

                detailsPanel
            }
            .navigationTitle("Место встречи")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .task { centerOnStart() }
            .onChange(of: name) { _, value in
                if value.count > Self.nameLimit { name = String(value.prefix(Self.nameLimit)) }
            }
            .onChange(of: note) { _, value in
                if value.count > Self.noteLimit { note = String(value.prefix(Self.noteLimit)) }
            }
        }
    }

    // MARK: Поиск

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Найти клуб, парк, адрес", text: $query)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { search() }
                .autocorrectionDisabled()
            if isSearching {
                ProgressView()
            } else if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    searchMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .accessibilityLabel("Очистить")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var resultsList: some View {
        List {
            if let searchMessage {
                Text(searchMessage).foregroundColor(.secondary)
            }
            ForEach(results) { candidate in
                Button {
                    choose(candidate)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.name).foregroundColor(.primary)
                        if !candidate.subtitle.isEmpty {
                            Text(candidate.subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .background(Color(.systemBackground))
    }

    // MARK: Карта

    private var mapView: some View {
        MapReader { proxy in
            Map(position: $position) {
                if let pin {
                    Marker(markerTitle, coordinate: pin)
                }
            }
            .onTapGesture { point in
                searchFocused = false
                if let coordinate = proxy.convert(point, from: .local) {
                    dropPin(at: coordinate)
                }
            }
            .overlay(alignment: .top) {
                if pin == nil {
                    Text("Нажмите на карту, чтобы поставить точку")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: Название и отправка

    private var detailsPanel: some View {
        VStack(spacing: 10) {
            TextField("Название места (клуб, парк, адрес)", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Как найти (необязательно)", text: $note)
                .textFieldStyle(.roundedBorder)

            if let moderationMessage {
                Text(moderationMessage)
                    .font(.caption)
                    .foregroundColor(AppColor.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if pin == nil && !trimmedName.isEmpty {
                Text("Точка на карте не выбрана — партнёр увидит только название.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                send()
            } label: {
                Text("Предложить это место")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(trimmedName.isEmpty)
        }
        .padding(16)
        .background(.bar)
    }

    // MARK: Действия

    private func centerOnStart() {
        if let latitude = currentLatitude, let longitude = currentLongitude {
            position = .region(region(latitude: latitude, longitude: longitude, span: 0.012))
            return
        }
        let town = city.trimmingCharacters(in: .whitespaces)
        guard !town.isEmpty else { return }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = town
        MKLocalSearch(request: request).start { response, _ in
            DispatchQueue.main.async {
                guard pin == nil, let item = response?.mapItems.first else { return }
                let center = item.placemark.coordinate
                position = .region(region(latitude: center.latitude, longitude: center.longitude, span: 0.12))
            }
        }
    }

    private func region(latitude: Double, longitude: Double, span: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return }

        searchFocused = false
        isSearching = true
        searchMessage = nil

        let request = MKLocalSearch.Request()
        let town = city.trimmingCharacters(in: .whitespaces)
        request.naturalLanguageQuery = town.isEmpty ? text : "\(text), \(town)"

        MKLocalSearch(request: request).start { response, error in
            DispatchQueue.main.async {
                isSearching = false
                guard let items = response?.mapItems, !items.isEmpty else {
                    results = []
                    searchMessage = error == nil
                        ? "Ничего не найдено. Попробуйте другое название или поставьте точку на карте"
                        : "Поиск не удался. Проверьте интернет или поставьте точку на карте"
                    return
                }
                results = items.prefix(8).map { item in
                    PlaceCandidate(
                        name: item.name ?? text,
                        subtitle: item.placemark.title ?? "",
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude
                    )
                }
            }
        }
    }

    private func choose(_ candidate: PlaceCandidate) {
        pin = CLLocationCoordinate2D(latitude: candidate.latitude, longitude: candidate.longitude)
        name = String(candidate.name.prefix(Self.nameLimit))
        autoName = name
        results = []
        searchMessage = nil
        query = ""
        searchFocused = false
        position = .region(region(latitude: candidate.latitude, longitude: candidate.longitude, span: 0.008))
    }

    /// Точка поставлена нажатием: пробуем подставить адрес, но не затираем название, которое человек уже написал
    private func dropPin(at coordinate: CLLocationCoordinate2D) {
        pin = coordinate
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            DispatchQueue.main.async {
                guard let place = placemarks?.first else { return }
                let street = [place.thoroughfare, place.subThoroughfare]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                let suggestion = street.isEmpty ? (place.name ?? "") : street
                guard !suggestion.isEmpty else { return }
                if name.isEmpty || name == autoName {
                    name = String(suggestion.prefix(Self.nameLimit))
                    autoName = name
                }
            }
        }
    }

    private func send() {
        guard !trimmedName.isEmpty else { return }
        guard ContentModeration.isAcceptableMessage(trimmedName),
              ContentModeration.isAcceptableMessage(trimmedNote) else {
            moderationMessage = "В тексте есть недопустимые выражения. Перефразируйте."
            return
        }
        onSend(trimmedName, pin?.latitude, pin?.longitude, trimmedNote)
        dismiss()
    }
}
