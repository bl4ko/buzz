import SwiftUI

struct ConversationView: View {
  let channel: WatchChannel
  @ObservedObject var store: WatchStore
  @State private var draft = ""
  @State private var draftScope = ""
  @State private var lastSeen: String?
  @State private var newIDs: Set<String> = []
  @Environment(\.scenePhase) private var scenePhase

  private var draftKey: String { WatchKeys.draft(scope: draftScope, channelID: channel.id) }
  private var seenKey: String { WatchKeys.seen(scope: draftScope, channelID: channel.id) }

  var body: some View {
    ScrollView {
      VStack(spacing: 8) {
        if let error = store.error {
          NoticeCard(message: error) {
            Button("Refresh", systemImage: "arrow.clockwise") { store.loadMessages(channel) }
              .buttonStyle(GlassPillStyle())
              .disabled(store.busy || draftScope != store.scope)
          }
        }
        if draftScope == store.scope {
          ComposerCard(
            draft: $draft,
            canSend: WatchComposer.canSend(
              draft: draft, busy: store.busy, independent: store.independent, reachable: store.reachable
            ),
            sending: store.sending,
            send: send
          )
        } else {
          NoticeCard(
            message: "The active account changed. Go back and refresh the channel list.",
            symbol: "person.crop.circle.badge.exclamationmark", tint: .bee, symbolColor: .bee
          ) { EmptyView() }
        }
        if store.busy && store.messages.isEmpty { LoadingRow(title: "Loading messages") }
        if store.messages.isEmpty && !store.busy && store.error == nil {
          EmptyStateView(symbol: "bubble.left.fill", title: "No messages yet", message: "Send the first one.")
        }
        ForEach(store.messages.reversed()) { message in
          MessageRow(message: message, isNew: newIDs.contains(message.id))
        }
      }
    }
    .navigationTitle(channel.name)
    .watchBackdrop()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button { store.loadMessages(channel) } label: {
          Image(systemName: "arrow.clockwise")
        }
        .toolbarGlyph()
        .accessibilityLabel("Refresh")
        .disabled(store.busy || draftScope != store.scope)
      }
    }
    .onAppear {
      draftScope = store.scope
      draft = UserDefaults.standard.string(forKey: draftKey) ?? ""
      lastSeen = UserDefaults.standard.string(forKey: seenKey)
      store.loadMessages(channel)
    }
    .onChange(of: draft) { _, value in
      if value.isEmpty {
        UserDefaults.standard.removeObject(forKey: draftKey)
      } else {
        UserDefaults.standard.set(value, forKey: draftKey)
      }
    }
    .onChange(of: store.messages.map(\.id)) { _, ids in markSeen(ids) }
    .task {
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(15)) } catch { return }
        if scenePhase == .active && !store.busy && store.error == nil && draftScope == store.scope {
          store.loadMessages(channel)
        }
      }
    }
  }

  private func send() {
    let sentDraft = draft
    store.send(sentDraft, to: channel) {
      draft = confirmedWatchDraft(draft, sent: sentDraft)
    }
  }

  private func markSeen(_ ids: [String]) {
    guard draftScope == store.scope, let newest = ids.last else { return }
    let own = Set(store.messages.filter { $0.mine == true }.map(\.id))
    newIDs = WatchUnread.newMessageIDs(ids, lastSeen: lastSeen, excluding: own)
    UserDefaults.standard.set(newest, forKey: seenKey)
  }
}

struct ComposerCard: View {
  @Binding var draft: String
  let canSend: Bool
  var sending = false
  let send: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        TextField("Message", text: $draft, axis: .vertical)
          .lineLimit(1...4)
        Button(action: send) {
          if sending {
            ProgressView().tint(.black).frame(width: 22, height: 22)
          } else {
            Image(systemName: "arrow.up")
          }
        }
        .buttonStyle(SendButtonStyle(sending: sending))
        .accessibilityLabel(WatchComposer.sendLabel(sending: sending))
        .disabled(!canSend)
      }
      WatchGlassGroup {
        FlowLayout {
          ForEach(WatchComposer.quickReplies, id: \.self) { reply in
            Button(reply) { draft = reply }
              .buttonStyle(ChipStyle(selected: draft == reply))
              .accessibilityHint("Quick reply")
          }
        }
      }
      if WatchComposer.isTooLong(draft) {
        Text("Use 2000 characters or fewer.")
          .font(.footnote)
          .foregroundStyle(WatchPalette.danger)
      }
    }
    .padding(8)
    .watchGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
  }
}

struct MessageRow: View {
  let message: WatchMessage
  let isNew: Bool

  private var mine: Bool { message.mine == true }
  private var time: String? { message.createdAt.map { WatchTime.label(createdAt: $0) } }

  var body: some View {
    VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
      HStack(spacing: 5) {
        if isNew {
          Circle().fill(Color.bee).frame(width: 6, height: 6)
        }
        if !mine {
          AvatarView(name: message.author, size: 20)
          Text(message.author)
            .font(.caption.weight(.semibold))
            .foregroundStyle(WatchPalette.avatar(message.author))
            .lineLimit(1)
        }
        if let time {
          if !mine { Spacer(minLength: 4) }
          Text(time).font(.caption2).foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 4)
      bubble
      if let notified = message.notified, !notified.isEmpty {
        Label("Notified: " + notified.joined(separator: ", "), systemImage: "bell.fill")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 4)
      }
    }
    .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }

  @ViewBuilder
  private var bubble: some View {
    let shape = UnevenRoundedRectangle(
      topLeadingRadius: 16, bottomLeadingRadius: mine ? 16 : 6,
      bottomTrailingRadius: mine ? 6 : 16, topTrailingRadius: 16, style: .continuous
    )
    let content = Group {
      if message.text.isEmpty {
        Label("Attachment: open on iPhone.", systemImage: "paperclip")
          .font(.footnote)
          .foregroundStyle(mine ? Color.black.opacity(0.7) : .secondary)
      } else {
        Text(message.text)
          .font(.body)
          .foregroundStyle(mine ? Color.black : .white)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    HStack(spacing: 0) {
      if mine {
        Spacer(minLength: 18)
        content.background(Color.bee, in: shape)
      } else {
        content.background(WatchPalette.bubble, in: shape)
        Spacer(minLength: 18)
      }
    }
  }

  private var accessibilityText: String {
    var parts = [mine ? "You" : message.author]
    if isNew { parts.append("New") }
    parts.append(message.text.isEmpty ? "Attachment: open on iPhone." : message.text)
    if let createdAt = message.createdAt { parts.append(WatchTime.spokenLabel(createdAt: createdAt)) }
    if let notified = message.notified, !notified.isEmpty { parts.append("Notified: " + notified.joined(separator: ", ")) }
    return parts.joined(separator: ", ")
  }
}

#if DEBUG
  #Preview("Messages") {
    ScrollView {
      VStack(spacing: 8) {
        ComposerCard(draft: .constant("Thanks"), canSend: true, send: {})
        MessageRow(
          message: WatchMessage(id: "1", author: "Alex Rivera", text: "Thanks", notified: [], createdAt: Int(Date().timeIntervalSince1970), mine: true),
          isNew: false
        )
        MessageRow(
          message: WatchMessage(id: "2", author: "Argus", text: "Holding the rollback script ready.", notified: ["Zeus"], createdAt: Int(Date().timeIntervalSince1970) - 120, mine: false),
          isNew: true
        )
      }
    }
  }
#endif
