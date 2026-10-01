@main
enum WatchDraftCheck {
  static func main() {
    assert(confirmedWatchDraft("Hello", sent: "Hello").isEmpty)
    assert(confirmedWatchDraft("Hello again", sent: "Hello") == "Hello again")
    assert(confirmedWatchDraft("Different text", sent: "Hello") == "Different text")
    assert(confirmedWatchDraft("", sent: "Hello").isEmpty)
  }
}
