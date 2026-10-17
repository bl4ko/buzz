import SwiftUI

struct ChannelListView: View {
  @ObservedObject var store: WatchStore
  let onConnect: () -> Void
  let onSignOut: () -> Void

  private var home: WatchHome {
    WatchHome(
      independent: store.independent, synced: store.synced, reachable: store.reachable,
      busy: store.busy, hasError: store.error != nil, channelsEmpty: store.channels.isEmpty
    )
  }

  var body: some View {
    let home = home
    ScrollView {
      VStack(spacing: 6) {
        if home.showsWelcome {
          WelcomeCard(store: store, home: home, onConnect: onConnect)
        } else {
          ConnectionPill(connection: home.connection)
          if let error = store.error {
            NoticeCard(message: error) { RefreshButton(store: store) }
          } else if home.showsRefresh {
            RefreshButton(store: store)
          }
        }
        if home.showsLoading { LoadingRow(title: "Loading channels") }
        WatchGlassGroup {
          VStack(spacing: 6) {
            ForEach(store.channels) { channel in
              NavigationLink {
                ConversationView(channel: channel, store: store)
              } label: {
                ChannelRow(channel: channel, draft: draft(for: channel))
              }
              .buttonStyle(.plain)
              .disabled(store.busy)
            }
          }
        }
        if home.showsEmpty {
          EmptyStateView(
            symbol: "bubble.left.and.bubble.right.fill", title: "No channels yet",
            message: "Join a channel on your iPhone."
          )
        }
      }
    }
    .navigationTitle("Bl4uzz")
    .watchBackdrop()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
          SettingsView(store: store, onConnect: onConnect, onSignOut: onSignOut)
        } label: {
          Image(systemName: "gearshape.fill")
        }
        .toolbarGlyph()
        .accessibilityLabel("Settings")
      }
    }
  }

  private func draft(for channel: WatchChannel) -> String? {
    guard !store.scope.isEmpty else { return nil }
    let value = UserDefaults.standard.string(forKey: WatchKeys.draft(scope: store.scope, channelID: channel.id))
    return value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? value : nil
  }
}

struct ConnectionPill: View {
  let connection: WatchConnection

  var body: some View {
    let (title, color): (String, Color) =
      switch connection {
      case .direct: ("Direct connection", WatchPalette.success)
      case .phone: ("Connected to iPhone", .bee)
      case .unreachable: ("iPhone not reachable", WatchPalette.danger)
      }
    HStack(spacing: 5) {
      Circle().fill(color).frame(width: 7, height: 7).shadow(color: color.opacity(0.8), radius: 3)
      Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
    }
    .padding(.leading, 8)
    .padding(.trailing, 10)
    .padding(.vertical, 4)
    .watchGlass(in: Capsule())
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

struct WelcomeCard: View {
  @ObservedObject var store: WatchStore
  let home: WatchHome
  let onConnect: () -> Void

  var body: some View {
    VStack(spacing: 8) {
      BeeMark().frame(height: 30)
      Text("Welcome to Bl4uzz").font(.headline)
      Text(message)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if home.showsRefresh {
        Button("Refresh", systemImage: "arrow.clockwise") { store.refresh() }
          .buttonStyle(BeeButtonStyle())
          .disabled(store.busy)
      }
      if home.showsConnect {
        Button("Connect without iPhone", systemImage: "applewatch") { onConnect() }
          .buttonStyle(GlassPillStyle())
          .disabled(!home.canConnect)
      }
    }
    .multilineTextAlignment(.center)
    .padding(10)
    .watchGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
  }

  private var message: String {
    if let error = store.error { return error }
    return store.reachable
      ? "Load your channels from your iPhone, or connect this watch directly."
      : "Open Bl4uzz on your paired iPhone."
  }
}

struct RefreshButton: View {
  @ObservedObject var store: WatchStore

  var body: some View {
    Button("Refresh", systemImage: "arrow.clockwise") { store.refresh() }
      .buttonStyle(GlassPillStyle())
      .disabled(store.busy)
  }
}

struct ChannelRow: View {
  let channel: WatchChannel
  let draft: String?

  var body: some View {
    HStack(spacing: 10) {
      if channel.dm == true {
        AvatarView(name: channel.name)
      } else {
        ChannelTile()
      }
      VStack(alignment: .leading, spacing: 1) {
        Text(channel.name)
          .font(.headline)
          .lineLimit(2)
        if let draft {
          Text("Draft: \(draft)")
            .font(.caption2)
            .foregroundStyle(Color.bee)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    .watchGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityHint(channel.dm == true ? "Direct message" : "Channel")
  }
}

#if DEBUG
  #Preview("Rows") {
    ScrollView {
      VStack(spacing: 6) {
        ConnectionPill(connection: .direct)
        ChannelRow(channel: WatchChannel(id: "1", name: "deploys", dm: false), draft: "I will check.")
        ChannelRow(channel: WatchChannel(id: "2", name: "Mia Novak", dm: true), draft: nil)
      }
    }
  }
#endif
