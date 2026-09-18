import ActivityKit
import SwiftUI
import WidgetKit

@main struct ReunionWidget: Widget {

    // MARK: - Body

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReunionAttributes.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Label("다시 만나", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.caption.bold())
                    Spacer()
                    Text(context.attributes.isDemo ? "체험 모드" : context.isStale ? "업데이트 지연" : "재합류 중")
                        .font(.caption2)
                }
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(context.attributes.place)
                            .font(.headline)
                        Text(context.state.friendStatus)
                            .font(.caption)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(context.state.arrival, style: .time)
                            .font(.title2.bold())
                        Text("출발 시 계산한 도착 예상")
                            .font(.system(size: 9))
                    }
                }
                Text(context.isStale ? "마지막 상태예요. 앱을 열어 확인하세요." : context.state.status)
                    .font(.caption)
            }
            .padding(18).activityBackgroundTint(Color(red: 0.12, green: 0.37, blue: 0.32))
            .activitySystemActionForegroundColor(.white)
            .foregroundStyle(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("다시 만나", systemImage: "figure.walk")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.arrival, style: .time)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .center, spacing: 5) {
                        Text(context.attributes.place)
                        Text(context.isStale ? "업데이트 지연 · 앱에서 확인" : context.state.friendStatus)
                            .font(.caption)
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.walk")
            } compactTrailing: {
                Text(context.state.arrival, style: .time)
                    .font(.caption)
            } minimal: {
                Image(systemName: "figure.walk")
            }
        }
    }
}
