import ActivityKit
import AppIntents
import BuzzPushKit
import SwiftUI
import WidgetKit

struct ApprovalsLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: BuzzApprovalsActivityAttributes.self) { context in
      ApprovalsActivityView(model: ApprovalsCardModel(context: context))
        .activityBackgroundTint(ApprovalsPalette.card)
        .activitySystemActionForegroundColor(.white)
        .widgetURL(ApprovalsCardModel(context: context).tasksURL)
    } dynamicIsland: { context in
      let model = ApprovalsCardModel(context: context)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading, priority: 1) {
          ApprovalsHeader(title: "Needs you · \(model.state.openCount)", iconSize: 22, font: 13)
            .minimumScaleFactor(0.8)
            .padding(.leading, 6)
        }
        DynamicIslandExpandedRegion(.bottom) {
          ApprovalsBody(model: model, askFont: 15, showsMeta: false)
            .padding(.horizontal, 6)
        }
      } compactLeading: {
        Circle().fill(ApprovalsPalette.dot).frame(width: 8, height: 8)
      } compactTrailing: {
        Text(model.compactTitle)
          .font(.system(size: 12, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      } minimal: {
        ZStack {
          Circle().fill(ApprovalsPalette.dot).frame(width: 8, height: 8).offset(x: -7, y: -7)
          Text("\(model.state.openCount)").font(.system(size: 12, weight: .semibold))
        }
      }
      .widgetURL(model.tasksURL)
      .keylineTint(ApprovalsPalette.dot)
    }
    .supplementalActivityFamilies([.small])
  }
}

struct ApprovalsCardModel {
  let origin: String
  let state: BuzzApprovalsContentState
  let isStale: Bool

  init(origin: String, state: BuzzApprovalsContentState, isStale: Bool) {
    self.origin = origin
    self.state = state
    self.isStale = isStale
  }

  init(context: ActivityViewContext<BuzzApprovalsActivityAttributes>) {
    self.init(origin: context.attributes.origin, state: context.state, isStale: context.isStale)
  }

  var tasksURL: URL? { BuzzLiveActivityLink.tasks(origin: origin, askEventID: state.askEventID) }
  var isDone: Bool { state.openCount <= 0 || state.askEventID.isEmpty }
  var moreCount: Int { max(0, state.openCount - 1) }
  var askedAt: Date { Date(timeIntervalSince1970: TimeInterval(state.askedAt)) }
  var compactTitle: String {
    isDone ? "Done" : state.openCount == 1 ? "1 approval" : "\(state.openCount) approvals"
  }
}

enum ApprovalsPalette {
  static let card = Color(red: 30 / 255, green: 30 / 255, blue: 34 / 255).opacity(0.82)
  static let secondary = Color(white: 0.67)
  static let meta = Color(white: 0.6)
  static let pill = Color(red: 58 / 255, green: 58 / 255, blue: 64 / 255)
  static let pillText = Color(white: 0.87)
  static let caseText = Color(red: 157 / 255, green: 180 / 255, blue: 255 / 255)
  static let bee = Color(red: 215 / 255, green: 215 / 255, blue: 46 / 255)
  static let denyFill = Color(red: 1, green: 69 / 255, blue: 58 / 255).opacity(0.18)
  static let denyText = Color(red: 1, green: 107 / 255, blue: 97 / 255)
  static let approveFill = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
  static let approveText = Color(red: 4 / 255, green: 33 / 255, blue: 13 / 255)
  static let dot = Color(red: 1, green: 159 / 255, blue: 10 / 255)
}

struct ApprovalsActivityView: View {
  @Environment(\.activityFamily) private var family
  let model: ApprovalsCardModel

  var body: some View {
    if family == .small {
      ApprovalsWatchCard(model: model)
    } else {
      ApprovalsLockScreenCard(model: model)
    }
  }
}

struct ApprovalsLockScreenCard: View {
  let model: ApprovalsCardModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        ApprovalsHeader(title: "Bl4uzz · Needs you", iconSize: 26, font: 13)
        Spacer(minLength: 4)
        ApprovalsMoreLink(model: model)
      }
      ApprovalsBody(model: model, askFont: 17, showsMeta: true)
    }
    .padding(.horizontal, 14)
    .padding(.top, 14)
    .padding(.bottom, 12)
    .foregroundStyle(.white)
  }
}

struct ApprovalsWatchCard: View {
  let model: ApprovalsCardModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ApprovalsHeader(title: "Needs you · \(model.state.openCount)", iconSize: 20, font: 11)
      if model.isDone {
        Text("All done").font(.system(size: 14, weight: .semibold)).padding(.top, 4)
      } else {
        if let caseID = model.state.caseID, !caseID.isEmpty {
          Text(caseID)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ApprovalsPalette.bee)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.top, 4)
        }
        Text(model.state.ask)
          .font(.system(size: 14, weight: .semibold))
          .lineLimit(2)
          .padding(.top, 2)
        ApprovalsActions(model: model, height: 32, font: 13, spacing: 6, watch: true)
          .padding(.top, 9)
      }
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 10)
    .foregroundStyle(.white)
  }
}

struct ApprovalsHeader: View {
  let title: String
  let iconSize: CGFloat
  let font: CGFloat

  var body: some View {
    HStack(spacing: 8) {
      RoundedRectangle(cornerRadius: iconSize * 0.27)
        .fill(.black)
        .frame(width: iconSize, height: iconSize)
        .overlay(Text("🐝").font(.system(size: iconSize * 0.58)))
      Text(title)
        .font(.system(size: font))
        .foregroundStyle(ApprovalsPalette.secondary)
        .lineLimit(1)
    }
  }
}

struct ApprovalsMoreLink: View {
  let model: ApprovalsCardModel

  var body: some View {
    if model.moreCount > 0, let url = model.tasksURL {
      Link(destination: url) {
        Text("+\(model.moreCount) more")
          .font(.system(size: 12))
          .foregroundStyle(ApprovalsPalette.pillText)
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(ApprovalsPalette.pill, in: Capsule())
      }
    }
  }
}

struct ApprovalsBody: View {
  let model: ApprovalsCardModel
  let askFont: CGFloat
  let showsMeta: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if model.isDone {
        Text("All done")
          .font(.system(size: askFont, weight: .semibold))
          .padding(.top, 9)
      } else {
        if let caseID = model.state.caseID, !caseID.isEmpty {
          Text(caseID)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ApprovalsPalette.caseText)
            .lineLimit(1)
            .padding(.top, 9)
        }
        Text(model.state.ask)
          .font(.system(size: askFont, weight: .semibold))
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, model.state.caseID?.isEmpty == false ? 2 : 9)
        if showsMeta {
          Text(
            "\(model.state.agent) · \(model.state.channel) · \(.currentDate, format: .reference(to: model.askedAt, allowedFields: [.day, .hour, .minute], maxFieldCount: 1))"
          )
          .font(.system(size: 13))
          .foregroundStyle(ApprovalsPalette.meta)
          .lineLimit(1)
          .padding(.top, 3)
        }
        ApprovalsActions(model: model, height: 40, font: 16, spacing: 10, watch: false)
          .padding(.top, 12)
      }
    }
  }
}

struct ApprovalsActions: View {
  let model: ApprovalsCardModel
  let height: CGFloat
  let font: CGFloat
  let spacing: CGFloat
  let watch: Bool

  var body: some View {
    if model.isStale {
      ApprovalsStatusLine(text: "Open Bl4uzz to refresh", height: height, font: font)
    } else if let pending = model.state.pendingDecision {
      ApprovalsStatusLine(text: pending == .approve ? "Approving…" : "Denying…", height: height, font: font)
    } else {
      HStack(spacing: spacing) {
        button(.deny, fill: ApprovalsPalette.denyFill, text: ApprovalsPalette.denyText)
        button(.approve, fill: ApprovalsPalette.approveFill, text: ApprovalsPalette.approveText)
      }
    }
  }

  @ViewBuilder
  private func button(_ decision: BuzzApprovalDecision, fill: Color, text: Color) -> some View {
    let label = Text(decision.title)
      .font(.system(size: font, weight: .semibold))
      .foregroundStyle(text)
      .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
      .background(fill, in: Capsule())
    if watch {
      Button(intent: BuzzWatchApprovalDecisionIntent(origin: model.origin, askEventID: model.state.askEventID, decision: decision)) {
        label
      }
      .buttonStyle(.plain)
    } else {
      Button(intent: BuzzApprovalDecisionIntent(origin: model.origin, askEventID: model.state.askEventID, decision: decision)) {
        label
      }
      .buttonStyle(.plain)
    }
  }
}

struct ApprovalsStatusLine: View {
  let text: String
  let height: CGFloat
  let font: CGFloat

  var body: some View {
    Text(text)
      .font(.system(size: font, weight: .semibold))
      .foregroundStyle(ApprovalsPalette.secondary)
      .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
      .background(Color.white.opacity(0.08), in: Capsule())
  }
}

#if DEBUG
  extension BuzzApprovalsActivityAttributes {
    fileprivate static let preview = BuzzApprovalsActivityAttributes(origin: "https://buzz.bl4ko.com")
  }

  extension BuzzApprovalsContentState {
    fileprivate static let open = BuzzApprovalsContentState(
      askEventID: String(repeating: "ab", count: 32), caseID: "ATH-AGENT-N8N-ENV-ACCESS-001",
      ask: "Approve rotating the n8n env secret?", agent: "Zeus", channel: "agents-coordination", openCount: 3,
      askedAt: Int(Date().timeIntervalSince1970) - 240)
    fileprivate static let approving = open.marking(.approve)
    fileprivate static let done = BuzzApprovalsContentState(
      askEventID: "", ask: "", agent: "", channel: "", openCount: 0, askedAt: Int(Date().timeIntervalSince1970))
  }

  #Preview("Lock Screen", as: .content, using: BuzzApprovalsActivityAttributes.preview) {
    ApprovalsLiveActivity()
  } contentStates: {
    BuzzApprovalsContentState.open
    BuzzApprovalsContentState.approving
    BuzzApprovalsContentState.done
  }

  #Preview("Island expanded", as: .dynamicIsland(.expanded), using: BuzzApprovalsActivityAttributes.preview) {
    ApprovalsLiveActivity()
  } contentStates: {
    BuzzApprovalsContentState.open
  }

  #Preview("Island compact", as: .dynamicIsland(.compact), using: BuzzApprovalsActivityAttributes.preview) {
    ApprovalsLiveActivity()
  } contentStates: {
    BuzzApprovalsContentState.open
  }

  #Preview("Island minimal", as: .dynamicIsland(.minimal), using: BuzzApprovalsActivityAttributes.preview) {
    ApprovalsLiveActivity()
  } contentStates: {
    BuzzApprovalsContentState.open
  }
#endif
