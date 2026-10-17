import SwiftUI

@main
struct Bl4uzzApp: App {
  @StateObject private var store = WatchStore()
  @Environment(\.scenePhase) private var scenePhase
  @State private var confirmSetup = false
  @State private var confirmSignOut = false

  init() {
    WatchApprovalActions.shared.register()
  }

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        ChannelListView(store: store, onConnect: { confirmSetup = true }, onSignOut: { confirmSignOut = true })
          .onAppear { store.showChannels() }
      }
      .tint(.bee)
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { store.resume() }
      }
      .sheet(isPresented: $confirmSetup) {
        ConnectSheet { store.setupStandalone() }
      }
      .alert("Sign out of watch?", isPresented: $confirmSignOut) {
        Button("Sign out", role: .destructive) { store.signOut() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Remove the saved watch sign-in. Your iPhone stays signed in.")
      }
    }
  }
}
