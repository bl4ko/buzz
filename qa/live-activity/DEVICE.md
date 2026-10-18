# Device checks

Run these on the TestFlight build with the owner's iPhone and Watch after `run.sh all` passes. Each needs hardware for the stated reason.

1. Lock the iPhone, tap Approve on the card, cancel Face ID: passcode prompt, no `✅` on the relay. Then approve with Face ID: one `✅`. Reason: the Simulator has no passcode or data protection, so the intent runs without authentication.
2. New ask with the app terminated: card appears (push-to-start), a second ask updates it, a card cleared before the next ask returns after the 30 minute start bound. Reason: `simctl push` cannot deliver `liveactivity` pushes; the suite applies the gateway payloads through a Debug bridge and launches the app to do it.
3. Approval alert from a real ask: title `Approval required`, `approval.wav` sound, Approve and Deny actions. Reason: `simctl push` does not run the Notification Service Extension.
4. Lock the iPhone, force-quit Bl4uzz, new ask, tap the card body: Tasks opens, not sign-in. Reason: the Simulator keychain is readable while locked; the suite emulates the locked keychain.
5. Watch: card in the Smart Stack, Approve on the Watch card and on a mirrored approval alert. Reason: needs real APNs and a paired Watch.
6. Open and reopen the TestFlight copy. Reason: TestFlight installs only on hardware.
