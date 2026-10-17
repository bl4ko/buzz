import SwiftUI

struct SettingsView: View {
  @ObservedObject var store: WatchStore
  let onConnect: () -> Void
  let onSignOut: () -> Void

  var body: some View {
    ScrollView {
      VStack(spacing: 8) {
        ConnectionCard(independent: store.independent, reachable: store.reachable)
        Button("Refresh", systemImage: "arrow.clockwise") { store.refresh() }
          .buttonStyle(GlassPillStyle())
          .disabled(store.busy)
        if !store.independent {
          Button("Connect without iPhone", systemImage: "applewatch") { onConnect() }
            .buttonStyle(BeeButtonStyle())
            .disabled(store.busy || !store.reachable)
        } else {
          Button("Sign out of watch", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
            onSignOut()
          }
          .buttonStyle(GlassPillStyle(tint: WatchPalette.danger))
        }
        if let error = store.error {
          Text(error)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        Text(versionLine)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .padding(.top, 2)
      }
    }
    .navigationTitle("Settings")
    .watchBackdrop()
  }

  private var versionLine: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? ""
    let build = info?["CFBundleVersion"] as? String ?? ""
    return "Bl4uzz \(version) (\(build))"
  }
}

struct ConnectionCard: View {
  let independent: Bool
  let reachable: Bool

  var body: some View {
    let (symbol, color, title, detail): (String, Color, String, String) =
      if independent {
        ("antenna.radiowaves.left.and.right", WatchPalette.success, "Direct connection", "Wi-Fi or cellular, no iPhone.")
      } else if reachable {
        ("iphone", .bee, "Via iPhone", "Your iPhone relays messages.")
      } else {
        ("iphone.slash", WatchPalette.danger, "iPhone not reachable", "Open Bl4uzz on the iPhone.")
      }
    HStack(spacing: 10) {
      SymbolBadge(systemName: symbol, color: color)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
        Text(detail).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .watchGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}

struct ConnectSheet: View {
  let onConnect: () -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ScrollView {
      VStack(spacing: 8) {
        HStack(spacing: 6) {
          SymbolBadge(systemName: "iphone", size: 40)
          Image(systemName: "arrow.right")
            .font(.footnote.weight(.bold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
          SymbolBadge(systemName: "applewatch", size: 40)
        }
        Text("Connect without iPhone?")
          .font(.headline)
        Text(
          "Copy your current iPhone sign-in to this watch's Keychain. Then use Wi-Fi or cellular without the iPhone. Open Bl4uzz on your iPhone for this setup step."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        Button("Connect") {
          onConnect()
          dismiss()
        }
        .buttonStyle(BeeButtonStyle())
        Button("Cancel", role: .cancel) { dismiss() }
          .buttonStyle(GlassPillStyle())
      }
      .multilineTextAlignment(.center)
    }
    .presentationBackground {
      ZStack {
        Color.black
        WatchPalette.backdrop
      }
      .ignoresSafeArea()
    }
  }
}

#if DEBUG
  #Preview("Connection") {
    ScrollView {
      VStack(spacing: 8) {
        ConnectionCard(independent: true, reachable: false)
        ConnectionCard(independent: false, reachable: true)
        ConnectionCard(independent: false, reachable: false)
      }
    }
  }

  #Preview("Connect sheet") {
    ConnectSheet(onConnect: {})
  }
#endif
