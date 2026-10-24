import SwiftUI
import PhotosUI
import CryptoKit
import UniformTypeIdentifiers

// MARK: - Upload helper (App Store Connect asset upload operations)

enum AssetUpload {
    /// Executes the `uploadOperations` Apple returns after reserving an asset.
    static func perform(_ operations: [Any], data: Data) async throws {
        for case let op as [String: Any] in operations {
            guard let urlString = op["url"] as? String, let url = URL(string: urlString) else { continue }
            let offset = op["offset"] as? Int ?? 0
            let length = op["length"] as? Int ?? data.count
            var req = URLRequest(url: url)
            req.httpMethod = op["method"] as? String ?? "PUT"
            for case let h as [String: Any] in (op["requestHeaders"] as? [Any] ?? []) {
                if let n = h["name"] as? String, let v = h["value"] as? String { req.setValue(v, forHTTPHeaderField: n) }
            }
            let end = min(offset + length, data.count)
            guard offset < end else { continue }
            req.timeoutInterval = 120
            let (body, resp) = try await URLSession.shared.upload(for: req, from: data.subdata(in: offset..<end))
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                throw ConnectError(message: L("Uploaden mislukt (\(code)): \(String(decoding: body.prefix(200), as: UTF8.self))"), status: code)
            }
        }
    }

    static func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Image URL from an ImageAsset templateUrl ({w}x{h}bb.{f}).
    static func imageURL(_ asset: [String: Any]?, width: Int = 400) -> URL? {
        guard let t = asset?["templateUrl"] as? String else { return nil }
        let w = asset?["width"] as? Double ?? 1, h = asset?["height"] as? Double ?? 1
        let height = Int(Double(width) * h / max(w, 1))
        return URL(string: t.replacingOccurrences(of: "{w}", with: "\(width)").replacingOccurrences(of: "{h}", with: "\(height)").replacingOccurrences(of: "{f}", with: "png"))
    }
}

enum DisplayTypes {
    static let screenshots: [(String, String)] = [
        ("APP_IPHONE_67", "iPhone 6,9\""), ("APP_IPHONE_65", "iPhone 6,5\""), ("APP_IPHONE_61", "iPhone 6,3\""), ("APP_IPHONE_55", "iPhone 5,5\""),
        ("APP_IPAD_PRO_3GEN_129", "iPad 13\""), ("APP_IPAD_PRO_3GEN_11", "iPad 11\""),
        ("APP_WATCH_ULTRA", "Apple Watch Ultra"), ("APP_WATCH_SERIES_10", "Apple Watch Series 10"), ("APP_WATCH_SERIES_7", "Apple Watch Series 7"),
        ("APP_DESKTOP", "Mac"), ("APP_APPLE_TV", "Apple TV"), ("APP_APPLE_VISION_PRO", "Apple Vision Pro"),
    ]
    static let previews: [(String, String)] = [
        ("IPHONE_67", "iPhone 6,9\""), ("IPHONE_65", "iPhone 6,5\""), ("IPHONE_61", "iPhone 6,3\""),
        ("IPAD_PRO_3GEN_129", "iPad 13\""), ("IPAD_PRO_3GEN_11", "iPad 11\""), ("DESKTOP", "Mac"), ("APPLE_TV", "Apple TV"), ("APPLE_VISION_PRO", "Apple Vision Pro"),
    ]
    static func label(_ raw: String) -> String {
        (screenshots + previews).first { $0.0 == raw }?.1 ?? Pretty.label(raw.replacingOccurrences(of: "APP_", with: ""))
    }
}

// MARK: - Screenshots, previews and product page assets for one version

struct MediaManagerView: View {
    let appID: String
    let versionID: String
    let title: String
    let editable: Bool
    @Environment(DevStore.self) private var store
    @State private var locs: [JRes] = []
    @State private var locID = ""
    @State private var shotSets: [JRes] = []
    @State private var previewSets: [JRes] = []
    @State private var included: [JRes] = []
    @State private var placements: [JRes] = []
    @State private var loading = true
    @State private var working: String?
    @State private var error: String?
    @State private var feedback: String?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var uploadTarget: UploadTarget?

    enum UploadTarget: Equatable {
        case screenshots(setID: String)
        case preview(setID: String)
        case creative(placementType: String)
    }

    var body: some View {
        List {
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            if let working {
                HStack(spacing: 10) { ProgressView(); Text(working).font(.footnote) }.listRowBackground(Color.clear)
            }
            if locs.count > 1 {
                Section {
                    Picker("Taal", selection: $locID) {
                        ForEach(locs) { l in Text("\(Locales.flag(l.str("locale"))) \(Locales.name(l.str("locale")))").tag(l.id) }
                    }
                }
                .cardRows()
            }

            creativeSection

            Section {
                ForEach(shotSets.sorted { order($0.str("screenshotDisplayType")) < order($1.str("screenshotDisplayType")) }) { set in
                    let shots = items(set, rel: "appScreenshots")
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(DisplayTypes.label(set.str("screenshotDisplayType"))).font(.subheadline.weight(.semibold))
                            Text("\(shots.count)/10").font(.caption).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            if editable && shots.count < 10 {
                                Button { uploadTarget = .screenshots(setID: set.id) } label: { Image(systemName: "plus.circle.fill") }
                                    .buttonStyle(.borderless)
                            }
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(shots.enumerated()), id: \.element.id) { index, shot in
                                    thumb(shot)
                                        .contextMenu {
                                            if editable {
                                                if index > 0 { Button { Task { await move(set, shots, from: index, by: -1) } } label: { Label("Naar links", systemImage: "arrow.left") } }
                                                if index < shots.count - 1 { Button { Task { await move(set, shots, from: index, by: 1) } } label: { Label("Naar rechts", systemImage: "arrow.right") } }
                                                Button(role: .destructive) { Task { await deleteAsset("/v1/appScreenshots/\(shot.id)") } } label: { Label("Verwijder", systemImage: "trash") }
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if editable {
                    Menu {
                        ForEach(DisplayTypes.screenshots.filter { t in !shotSets.contains { $0.str("screenshotDisplayType") == t.0 } }, id: \.0) { t in
                            Button(t.1) { Task { await createSet(type: t.0, preview: false) } }
                        }
                    } label: { Label("Schermformaat toevoegen", systemImage: "plus.rectangle.on.rectangle") }
                }
            } header: { Text("Screenshots") } footer: {
                Text(editable ? "Houd een screenshot ingedrukt om te verplaatsen of te verwijderen. Maximaal 10 per formaat." : "Deze versie kan niet meer worden aangepast.")
            }
            .cardRows()

            Section {
                ForEach(previewSets) { set in
                    let previews = items(set, rel: "appPreviews")
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(DisplayTypes.label(set.str("previewType"))).font(.subheadline.weight(.semibold))
                            Text("\(previews.count)/3").font(.caption).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            if editable && previews.count < 3 {
                                Button { uploadTarget = .preview(setID: set.id) } label: { Image(systemName: "plus.circle.fill") }.buttonStyle(.borderless)
                            }
                        }
                        ForEach(previews) { p in
                            HStack(spacing: 10) {
                                AsyncImage(url: AssetUpload.imageURL(p.obj("previewImage"), width: 160)) { img in img.resizable().scaledToFit() } placeholder: { Theme.cardRaised }
                                    .frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading) {
                                    Text(p.str("fileName")).font(.caption).lineLimit(1)
                                    Text(Pretty.label((p.obj("videoDeliveryState") ?? p.obj("assetDeliveryState"))?["state"] as? String)).font(.caption2).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                if editable {
                                    Button(role: .destructive) { Task { await deleteAsset("/v1/appPreviews/\(p.id)") } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
                if editable {
                    Menu {
                        ForEach(DisplayTypes.previews.filter { t in !previewSets.contains { $0.str("previewType") == t.0 } }, id: \.0) { t in
                            Button(t.1) { Task { await createSet(type: t.0, preview: true) } }
                        }
                    } label: { Label("Previewformaat toevoegen", systemImage: "film.stack") }
                }
            } header: { Text("App-previews (video)") } footer: {
                Text("Video's van 15–30 seconden, .mov of .mp4. Apple verwerkt ze na het uploaden.")
            }
            .cardRows()
        }
        .themedList()
        .overlay { if loading && shotSets.isEmpty && locs.isEmpty { ProgressView() } }
        .navigationTitle("Screenshots en previews")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadLocs() }
        .onChange(of: locID) { Task { await loadMedia() } }
        .refreshable { await loadMedia() }
        .photosPicker(isPresented: Binding(get: { uploadTarget != nil }, set: { if !$0 && pickerItems.isEmpty { uploadTarget = nil } }),
                      selection: $pickerItems, maxSelectionCount: 10, matching: pickerFilter)
        .onChange(of: pickerItems) {
            guard !pickerItems.isEmpty, let target = uploadTarget else { return }
            let picked = pickerItems
            pickerItems = []
            uploadTarget = nil
            Task { await upload(picked, to: target) }
        }
        .actionFeedback($feedback)
    }

    private var pickerFilter: PHPickerFilter {
        if case .preview = uploadTarget { return .videos }
        return .images
    }

    private var creativeSection: some View {
        Section {
            ForEach([("PRODUCT_PAGE_HEADER_ASSET", "Header (21:9, 3840 × 1646)"), ("APP_STORE_SEARCH_RESULTS_ASSET", "Search Results (3:2, 1920 × 1280 – 3840 × 2560)")], id: \.0) { type, label in
                let current = placements.filter { $0.str("placementType") == type }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(label).font(.subheadline.weight(.semibold))
                        Spacer()
                        if editable {
                            Button { uploadTarget = .creative(placementType: type) } label: { Image(systemName: current.isEmpty ? "plus.circle.fill" : "arrow.triangle.2.circlepath.circle.fill") }
                                .buttonStyle(.borderless)
                        }
                    }
                    if current.isEmpty {
                        Text("Nog geen afbeelding").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(current) { p in
                        let image = included.first { $0.id == p.rel("image") }
                        HStack(spacing: 10) {
                            AsyncImage(url: AssetUpload.imageURL(image?.obj("imageAsset"), width: 300)) { img in img.resizable().scaledToFit() } placeholder: { Theme.cardRaised }
                                .frame(width: 120, height: 60).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(image?.s("fileName") ?? image?.s("referenceName") ?? L("Afbeelding")).font(.caption).lineLimit(1)
                                Text(Pretty.label(p.s("state"))).font(.caption2).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            if editable {
                                Button(role: .destructive) { Task { await deleteAsset("/v1/appAssetLibraryPlacements/\(p.id)") } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        } header: { Text("Header en Search Results") } footer: {
            Text("Afbeeldingen zonder transparantie. Ze gaan via de Asset Library van App Store Connect en worden samen met de versie beoordeeld.")
        }
        .cardRows()
    }

    private func order(_ type: String) -> Int {
        DisplayTypes.screenshots.firstIndex { $0.0 == type } ?? 99
    }

    /// Included resources for a set, in the order of the relationship.
    private func items(_ set: JRes, rel: String) -> [JRes] {
        set.relIDs(rel).compactMap { id in included.first { $0.id == id } }
    }

    private func thumb(_ shot: JRes) -> some View {
        let state = (shot.obj("assetDeliveryState")?["state"] as? String) ?? ""
        return ZStack {
            AsyncImage(url: AssetUpload.imageURL(shot.obj("imageAsset"), width: 240)) { img in img.resizable().scaledToFit() } placeholder: {
                RoundedRectangle(cornerRadius: 8).fill(Theme.cardRaised)
            }
            if state != "COMPLETE" && !state.isEmpty {
                Text(Pretty.label(state)).font(.caption2.weight(.semibold)).padding(4).background(.ultraThinMaterial, in: Capsule())
            }
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Loading

    private func loadLocs() async {
        guard let api = store.api else { return }
        do {
            locs = try await api.jget("/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations", [("limit", "50")]).data
            if locID.isEmpty { locID = locs.first(where: { $0.str("locale").hasPrefix("en") })?.id ?? locs.first?.id ?? "" }
            if locs.count <= 1 { await loadMedia() }
        } catch { self.error = error.localizedDescription; loading = false }
    }

    private func loadMedia() async {
        guard let api = store.api, !locID.isEmpty else { loading = false; return }
        loading = true
        defer { loading = false }
        do {
            async let s = api.jget("/v1/appStoreVersionLocalizations/\(locID)/appScreenshotSets", [("limit", "50"), ("include", "appScreenshots")])
            async let p = api.jget("/v1/appStoreVersionLocalizations/\(locID)/appPreviewSets", [("limit", "50"), ("include", "appPreviews")])
            async let pl = api.jget("/v1/appStoreVersionLocalizations/\(locID)/placements", [("limit", "50"), ("include", "image")])
            let sd = try await s
            let pd = (try? await p) ?? JDoc()
            let pld = (try? await pl) ?? JDoc()
            shotSets = sd.data
            previewSets = pd.data
            placements = pld.data.filter { ["PRODUCT_PAGE_HEADER_ASSET", "APP_STORE_SEARCH_RESULTS_ASSET"].contains($0.str("placementType")) }
            included = sd.included + pd.included + pld.included
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    // MARK: Actions

    private func createSet(type: String, preview: Bool) async {
        guard let api = store.api else { return }
        do {
            if preview {
                try await api.jcreate("/v1/appPreviewSets", type: "appPreviewSets", attributes: ["previewType": type],
                                      relationships: ["appStoreVersionLocalization": ("appStoreVersionLocalizations", locID)])
            } else {
                try await api.jcreate("/v1/appScreenshotSets", type: "appScreenshotSets", attributes: ["screenshotDisplayType": type],
                                      relationships: ["appStoreVersionLocalization": ("appStoreVersionLocalizations", locID)])
            }
            await loadMedia()
        } catch { self.error = error.localizedDescription }
    }

    private func deleteAsset(_ path: String) async {
        guard let api = store.api else { return }
        do { try await api.jdelete(path); feedback = L("Verwijderd"); await loadMedia() }
        catch { self.error = error.localizedDescription }
    }

    private func move(_ set: JRes, _ shots: [JRes], from index: Int, by delta: Int) async {
        guard let api = store.api else { return }
        var ids = shots.map(\.id)
        let to = index + delta
        guard ids.indices.contains(to) else { return }
        ids.swapAt(index, to)
        do {
            try await api.jsend("PATCH", "/v1/appScreenshotSets/\(set.id)/relationships/appScreenshots",
                                ["data": ids.map { ["type": "appScreenshots", "id": $0] }])
            await loadMedia()
        } catch { self.error = error.localizedDescription }
    }

    private func upload(_ picked: [PhotosPickerItem], to target: UploadTarget) async {
        guard let api = store.api else { return }
        defer { working = nil }
        do {
            for (n, item) in picked.enumerated() {
                working = L("Uploaden \(n + 1) van \(picked.count)…")
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
                let ext = isVideo ? (item.supportedContentTypes.contains { $0.conforms(to: .mpeg4Movie) } ? "mp4" : "mov") : "png"
                let name = "DevTools-\(Int(Date().timeIntervalSince1970))-\(n + 1).\(ext)"
                switch target {
                case .screenshots(let setID):
                    let png = Self.flattenedPNG(data) ?? data
                    guard let res = try await api.jcreate("/v1/appScreenshots", type: "appScreenshots",
                                                          attributes: ["fileName": name, "fileSize": png.count],
                                                          relationships: ["appScreenshotSet": ("appScreenshotSets", setID)]) else { continue }
                    try await AssetUpload.perform(res.list("uploadOperations"), data: png)
                    try await api.jpatch("/v1/appScreenshots/\(res.id)", type: "appScreenshots", id: res.id,
                                         attributes: ["uploaded": true, "sourceFileChecksum": AssetUpload.md5(png)])
                case .preview(let setID):
                    guard let res = try await api.jcreate("/v1/appPreviews", type: "appPreviews",
                                                          attributes: ["fileName": name, "fileSize": data.count, "mimeType": ext == "mp4" ? "video/mp4" : "video/quicktime"],
                                                          relationships: ["appPreviewSet": ("appPreviewSets", setID)]) else { continue }
                    try await AssetUpload.perform(res.list("uploadOperations"), data: data)
                    try await api.jpatch("/v1/appPreviews/\(res.id)", type: "appPreviews", id: res.id,
                                         attributes: ["uploaded": true, "sourceFileChecksum": AssetUpload.md5(data)])
                case .creative(let placementType):
                    let png = Self.flattenedPNG(data) ?? data
                    try await uploadCreative(api: api, data: png, name: name, placementType: placementType)
                }
            }
            feedback = L("Geüpload. Apple verwerkt de bestanden nu.")
            await loadMedia()
        } catch { self.error = error.localizedDescription }
    }

    /// Header / Search Results asset: upload to the app's Asset Library, then place it on this localization.
    private func uploadCreative(api: ConnectAPI, data: Data, name: String, placementType: String) async throws {
        guard let library = try await api.jget("/v1/apps/\(appID)/assetLibrary").data.first else {
            throw ConnectError(message: L("Geen Asset Library gevonden voor deze app."))
        }
        guard let image = try await api.jcreate("/v1/appAssetLibraryImages", type: "appAssetLibraryImages",
                                                attributes: ["category": "CREATIVE_ASSETS", "fileName": name, "fileSize": data.count, "referenceName": name],
                                                relationships: ["assetLibrary": ("appAssetLibraries", library.id)]) else { return }
        try await AssetUpload.perform(image.list("uploadOperations"), data: data)
        try await api.jpatch("/v1/appAssetLibraryImages/\(image.id)", type: "appAssetLibraryImages", id: image.id, attributes: ["uploaded": true])
        // Remove the current placement of this type, then place the new image.
        for old in placements where old.str("placementType") == placementType {
            try? await api.jdelete("/v1/appAssetLibraryPlacements/\(old.id)")
        }
        // The image must finish processing before it can be placed.
        var lastError: Error?
        for _ in 0..<10 {
            do {
                try await api.jcreate("/v1/appAssetLibraryPlacements", type: "appAssetLibraryPlacements",
                                      attributes: ["placementType": placementType],
                                      relationships: ["image": ("appAssetLibraryImages", image.id),
                                                      "appStoreVersionLocalization": ("appStoreVersionLocalizations", locID)])
                return
            } catch {
                lastError = error
                try? await Task.sleep(for: .seconds(3))
            }
        }
        if let lastError { throw lastError }
    }

    /// Re-encodes an image as PNG without alpha channel (Apple rejects transparency).
    static func flattenedPNG(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.pngData()
    }
}
