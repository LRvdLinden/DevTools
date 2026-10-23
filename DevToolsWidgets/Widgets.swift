import SwiftUI
import WidgetKit

struct DevEntry:TimelineEntry { let date:Date; let snapshot:SharedSnapshot }
struct DevProvider:TimelineProvider {
    func placeholder(in context:Context)->DevEntry{DevEntry(date:.now,snapshot:.placeholder)}
    func getSnapshot(in context:Context,completion:@escaping(DevEntry)->Void){completion(DevEntry(date:.now,snapshot:SharedSnapshot.load()))}
    func getTimeline(in context:Context,completion:@escaping(Timeline<DevEntry>)->Void){completion(Timeline(entries:[DevEntry(date:.now,snapshot:SharedSnapshot.load())],policy:.after(.now.addingTimeInterval(1800))))}
}
struct DevWidgetView:View {
    let entry:DevEntry
    var body:some View {
        VStack(alignment:.leading,spacing:8){
            Label("DevTools",systemImage:"hammer.fill").font(.caption.bold()).foregroundStyle(.blue)
            Text("\(entry.snapshot.apps.count)").font(.system(size:39,weight:.bold,design:.rounded))
            Text("My Apps").font(.caption).foregroundStyle(.secondary)
            Divider()
            Label("\(entry.snapshot.inReview) in review",systemImage:"clock") .font(.caption)
            Text("\(entry.snapshot.updated,style:.time)").font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).padding().containerBackground(.background,for:.widget)
    }
}
struct AppPortfolioWidget:Widget {
    let kind="AppPortfolioWidget"
    var body:some WidgetConfiguration {
        StaticConfiguration(kind:kind,provider:DevProvider()){DevWidgetView(entry:$0)}
            .configurationDisplayName("DevTools Overview").description("Apps and review statuses").supportedFamilies([.systemSmall,.systemMedium,.systemLarge])
    }
}
struct ReviewWidget:Widget {
    let kind="DevReviewWidget"
    var body:some WidgetConfiguration {
        StaticConfiguration(kind:kind,provider:DevProvider()){entry in
            VStack(alignment:.leading,spacing:9){Label("Review Status",systemImage:"checkmark.seal").foregroundStyle(.blue)
                Text("\(entry.snapshot.inReview)").font(.largeTitle.bold());Text("Apps in review").font(.caption)
                ForEach(entry.snapshot.apps.prefix(3)){a in Text("\(a.name): \(a.state)").font(.caption2).lineLimit(1)}
            }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).padding().containerBackground(.background,for:.widget)
        }.configurationDisplayName("App Reviews").description("Review status overview").supportedFamilies([.systemSmall,.systemMedium])
    }
}
@main struct DevWidgets:WidgetBundle {var body:some Widget {AppPortfolioWidget();ReviewWidget()}}
