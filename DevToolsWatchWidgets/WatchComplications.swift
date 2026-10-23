import SwiftUI
import WidgetKit
struct WatchEntry:TimelineEntry{let date:Date;let snap:SharedSnapshot}
struct WatchProvider:TimelineProvider {
    func placeholder(in context:Context)->WatchEntry{WatchEntry(date:.now,snap:.placeholder)}
    func getSnapshot(in context:Context,completion:@escaping(WatchEntry)->Void){completion(WatchEntry(date:.now,snap:WatchSnapshot.load()))}
    func getTimeline(in context:Context,completion:@escaping(Timeline<WatchEntry>)->Void){completion(Timeline(entries:[WatchEntry(date:.now,snap:WatchSnapshot.load())],policy:.after(.now.addingTimeInterval(1800))))}
}
enum WatchSnapshot {
    static func load()->SharedSnapshot {
        guard let d=UserDefaults(suiteName:"group.nl.lrvdlinden.devtools.watch")?.data(forKey:"watchSnapshot"),let val=try? JSONDecoder().decode(SharedSnapshot.self,from:d) else{return .placeholder}
        return val
    }
}
struct ComplicationView:View {
    let entry:WatchEntry
    @Environment(\.widgetFamily) var family
    var body:some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing:0){Image(systemName:"hammer.fill");Text("\(entry.snap.apps.count)").font(.headline)}.containerBackground(.clear,for:.widget)
        case .accessoryInline:
            Text("DevTools · \(entry.snap.apps.count) apps · \(entry.snap.inReview) review")
        default:
            VStack(alignment:.leading){Label("DevTools",systemImage:"hammer.fill").font(.caption);Text("\(entry.snap.apps.count) apps").font(.headline);Text("\(entry.snap.inReview) in review").font(.caption2)}.containerBackground(.clear,for:.widget)
        }
    }
}
@main struct DevWatchWidgets:Widget {
    var body:some WidgetConfiguration {
        StaticConfiguration(kind:"DevToolsWatchComplications",provider:WatchProvider()){ComplicationView(entry:$0)}
            .configurationDisplayName("DevTools").description("Developer portfolio").supportedFamilies([.accessoryCircular,.accessoryRectangular,.accessoryInline,.accessoryCorner])
    }
}
