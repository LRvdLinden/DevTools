import SwiftUI
import Charts
import UniformTypeIdentifiers

struct RootScreen:View {
    @Environment(DevStore.self) private var store
    @Environment(\.horizontalSizeClass) private var size
    var body:some View {
        Group {
            if store.active == nil { AccountScreen() }
            else if size == .regular {
                NavigationSplitView {
                    List {
                        NavigationLink { DashboardScreen() } label: {Label("Home",systemImage:"house.fill")}
                        NavigationLink { AppsScreen() } label: {Label("My Apps",systemImage:"square.stack.fill")}
                        NavigationLink { InsightsScreen() } label: {Label("Insights",systemImage:"chart.xyaxis.line")}
                        NavigationLink { AIScreen() } label: {Label("AI Assistant",systemImage:"sparkles")}
                        NavigationLink { AccountScreen() } label: {Label("Account",systemImage:"person.crop.circle")}
                    }.navigationTitle("DevTools")
                } detail: {DashboardScreen()}
            } else {
                TabView {
                    NavigationStack{DashboardScreen()}.tabItem{Label("Home",systemImage:"house.fill")}
                    NavigationStack{AppsScreen()}.tabItem{Label("My Apps",systemImage:"square.stack.fill")}
                    NavigationStack{InsightsScreen()}.tabItem{Label("Insights",systemImage:"chart.xyaxis.line")}
                    NavigationStack{AIScreen()}.tabItem{Label("AI",systemImage:"sparkles")}
                    NavigationStack{AccountScreen()}.tabItem{Label("Account",systemImage:"person.crop.circle")}
                }
            }
        }
    }
}
struct StatCard:View {
    let label:String
    let value:String
    let icon:String
    var body:some View {
        VStack(alignment:.leading,spacing:9) {
            Image(systemName:icon).foregroundStyle(.blue)
            Text(value).font(.title.bold()).minimumScaleFactor(0.65).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .padding().background(.regularMaterial,in:RoundedRectangle(cornerRadius:15))
    }
}
struct DashboardScreen:View {
    @Environment(DevStore.self) private var store
    private var reviewCount:Int {store.apps.filter{$0.state.contains("REVIEW")}.count}
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18){
                HStack {
                    VStack(alignment:.leading){Text("Developer Overview").font(.largeTitle.bold());Text(store.active?.name ?? "").foregroundStyle(.secondary)}
                    Spacer();if store.loading {ProgressView()}
                }
                HStack {StatCard(label:"My Apps",value:"\(store.apps.count)",icon:"app.badge");StatCard(label:"In Review",value:"\(reviewCount)",icon:"clock.badge.questionmark")}
                HStack {StatCard(label:"Live",value:"\(store.apps.filter{$0.state == "READY_FOR_DISTRIBUTION"}.count)",icon:"checkmark.seal");StatCard(label:"Accounts",value:"\(store.accounts.count)",icon:"person.2")}
                if let error=store.error {ContentUnavailableView("Apple API error",systemImage:"exclamationmark.triangle",description:Text(error))}
                HStack {Text("Your Apps").font(.title2.bold());Spacer();NavigationLink("View all"){AppsScreen()}.font(.subheadline)}
                ForEach(store.apps.prefix(10)){app in NavigationLink {AppDetailScreen(app:app)} label:{AppRow(app:app)}}
                if store.apps.isEmpty && !store.loading && store.error == nil {ContentUnavailableView("No apps found",systemImage:"app.dashed",description:Text("Connect an API key with access to your App Store Connect apps."))}
                if let date=store.lastRefresh {Text("Updated \(date.formatted())").font(.caption2).foregroundStyle(.secondary)}
            }.padding()
        }
        .navigationTitle("Home")
        .refreshable {await store.refresh()}
        .toolbar {ToolbarItem(placement:.topBarTrailing){Button {Task{await store.refresh()}} label:{Image(systemName:"arrow.clockwise")}.disabled(store.loading)}}
    }
}
struct AppRow:View {
    let app:AppSummary
    var body:some View {
        HStack(spacing:12){
            Image(systemName:"app.fill").font(.title2).foregroundStyle(.blue).frame(width:42,height:42).background(.blue.opacity(0.12),in:RoundedRectangle(cornerRadius:10))
            VStack(alignment:.leading){Text(app.name).font(.headline);Text("Version \(app.version) • Build \(app.latestBuild)").font(.caption).foregroundStyle(.secondary)}
            Spacer();Text(app.state.replacingOccurrences(of:"_",with:" ").capitalized).font(.caption2).multilineTextAlignment(.trailing).foregroundStyle(.secondary)
            Image(systemName:"chevron.right").font(.caption).foregroundStyle(.tertiary)
        }.padding(12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12))
    }
}
struct AppsScreen:View {
    @Environment(DevStore.self) private var store
    @State private var query=""
    var body:some View {
        List {
            ForEach(store.apps.filter{query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)}) {app in NavigationLink {AppDetailScreen(app:app)} label:{AppRow(app:app)}.listRowSeparator(.hidden)}
        }.searchable(text:$query).navigationTitle("My Apps").refreshable{await store.refresh()}
    }
}
struct AppDetailScreen:View {
    let app:AppSummary
    @Environment(DevStore.self) private var store
    @State private var versions:[AppleResource<AppleVersionAttributes>]=[]
    @State private var builds:[AppleResource<AppleBuildAttributes>]=[]
    @State private var reviews:[AppleResource<AppleReviewAttributes>]=[]
    @State private var error:String?
    @State private var loading=true
    var body:some View {
        List {
            Section("Overview") {
                LabeledContent("Bundle ID",value:app.bundleID)
                LabeledContent("Latest version",value:app.version)
                LabeledContent("Latest build",value:app.latestBuild)
                LabeledContent("Status",value:app.state)
            }
            Section("App Store Versions") {
                ForEach(versions){v in HStack{Text(v.attributes.versionString ?? "—");Spacer();Text(v.attributes.platform ?? "");Text(v.attributes.appStoreState ?? "").foregroundStyle(.secondary).font(.caption)}}
            }
            Section("TestFlight / Builds") {
                ForEach(builds){b in HStack{Text(b.attributes.version ?? "—");Spacer();Text(b.attributes.processingState ?? "—").foregroundStyle(.secondary).font(.caption)}}
            }
            Section("Customer Reviews (\(reviews.count))") {
                ForEach(reviews){r in VStack(alignment:.leading,spacing:4){
                    Text("\(r.attributes.rating ?? 0) ★  \(r.attributes.title ?? "Review")").font(.headline)
                    Text(r.attributes.body ?? "").font(.subheadline)
                    Text(r.attributes.reviewerNickname ?? "").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical,5)}
            }
            if let error {Text(error).foregroundStyle(.red)}
            if loading {ProgressView()}
        }.navigationTitle(app.name).task(id:app.id){await load()}.refreshable{await load()}
    }
    func load() async {
        loading=true;defer{loading=false};error=nil
        do {
            async let v=store.versions(for:app.id)
            async let b=store.builds(for:app.id)
            async let r=store.reviews(for:app.id)
            versions=try await v;builds=try await b;reviews=try await r
        }catch {self.error=error.localizedDescription}
    }
}
struct InsightsScreen:View {
    @Environment(DevStore.self) private var store
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16){
                Text("Portfolio Insights").font(.largeTitle.bold())
                Text("Live app version and review-status distribution. Sales, proceeds, subscriptions and App Analytics require Apple's separate Sales Reports / Analytics Reports ingestion and are not yet displayed as live figures.").foregroundStyle(.secondary)
                Chart {
                    ForEach(store.apps){app in BarMark(x:.value("App",app.name),y:.value("App",1)).foregroundStyle(by:.value("Status",app.state))}
                }.frame(height:220)
                ForEach(store.apps){app in AppRow(app:app)}
            }.padding()
        }.navigationTitle("Insights")
    }
}
struct AIScreen:View {
    @Environment(DevStore.self) private var store
    @State private var draft=""
    var body:some View {
        Form {
            Section("Release Notes Assistant") {
                Text("Draft release notes from your own changes. AI generation requires a configured AI service and is intentionally not simulated.")
                TextEditor(text:$draft).frame(minHeight:110)
                ShareLink(item:draft.isEmpty ? "Release notes" : draft){Label("Export draft",systemImage:"square.and.arrow.up")}
            }
            Section("Portfolio summary") {
                Text("\(store.apps.count) apps linked • \(store.apps.filter{$0.state.contains("REVIEW")}.count) in review")
                Text("AI trend analysis, reply proposals and automated crash grouping are backend integrations planned for a subsequent connected release.").foregroundStyle(.secondary)
            }
        }.navigationTitle("DevTools AI")
    }
}
struct AccountScreen:View {
    @Environment(DevStore.self) private var store
    @AppStorage("appearance") private var appearance="system"
    @State private var showAdd=false
    var body:some View {
        NavigationStack {
            Form {
                Section("Developer Accounts") {
                    ForEach(store.accounts){item in
                        HStack {VStack(alignment:.leading){Text(item.name);Text(item.keyID).font(.caption).foregroundStyle(.secondary)};Spacer()
                            if item.id == store.selectedID {Image(systemName:"checkmark.circle.fill").foregroundStyle(.blue)}
                        }.contentShape(Rectangle()).onTapGesture {store.select(item)}
                    }.onDelete {idx in for i in idx {store.remove(store.accounts[i])}}
                    Button {showAdd=true} label:{Label("Add Apple Developer Account",systemImage:"plus.circle.fill")}
                }
                Section("Appearance") {
                    Picker("Theme",selection:$appearance){Text("System").tag("system");Text("Light").tag("light");Text("Dark").tag("dark")}
                }
                Section("About") {
                    LabeledContent("App",value:"DevTools")
                    LabeledContent("Version",value:"1.0.0 (6)")
                    Text("Independent companion, not affiliated with Apple. Private API keys remain in your device Keychain.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Account")
                .sheet(isPresented:$showAdd){AddAccountSheet()}
        }
    }
}
struct AddAccountSheet:View {
    @Environment(DevStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name=""
    @State private var issuer=""
    @State private var keyID=""
    @State private var pem=""
    @State private var showPicker=false
    @State private var error:String?
    var body:some View {
        NavigationStack {
            Form {
                Section("App Store Connect API") {
                    TextField("Account label",text:$name)
                    TextField("Issuer ID",text:$issuer).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Key ID",text:$keyID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Import AuthKey_*.p8") {showPicker=true}
                    Text(pem.isEmpty ? "No private key selected" : "Private key imported").font(.caption).foregroundStyle(pem.isEmpty ? Color.secondary : Color.green)
                }
                Section {Text("Generate an App Store Connect API key in Users and Access. The private key is stored in iOS Keychain and never committed to source control.").font(.footnote)}
                if let error {Text(error).foregroundStyle(.red)}
            }.navigationTitle("Connect Account")
                .toolbar {ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Save"){
                    do {try store.add(name:name.isEmpty ? "Apple Developer" : name,issuer:issuer,key:keyID,pem:pem);dismiss();Task{await store.refresh()}}
                    catch {self.error=error.localizedDescription}
                }.disabled(issuer.isEmpty || keyID.isEmpty || pem.isEmpty)}}
                .fileImporter(isPresented:$showPicker,allowedContentTypes:[.data,.plainText],allowsMultipleSelection:false){result in
                    do {let url=try result.get().first!;let ok=url.startAccessingSecurityScopedResource();defer{if ok {url.stopAccessingSecurityScopedResource()}};pem=try String(contentsOf:url,encoding:.utf8)}catch{self.error=error.localizedDescription}
                }
        }
    }
}
