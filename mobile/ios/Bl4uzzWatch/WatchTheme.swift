import SwiftUI

extension Color {
  static let bee = Color(red: 215 / 255, green: 215 / 255, blue: 46 / 255)
}

enum WatchPalette {
  static let avatars: [Color] = [
    Color(red: 1, green: 0.70, blue: 0.25),
    Color(red: 0.39, green: 0.82, blue: 1),
    Color(red: 0.85, green: 0.56, blue: 1),
    Color(red: 0.19, green: 0.82, blue: 0.35),
    Color(red: 1, green: 0.39, blue: 0.51),
    Color(red: 0.45, green: 0.62, blue: 1),
  ]
  static let danger = Color(red: 1, green: 0.41, blue: 0.38)
  static let success = Color(red: 0.19, green: 0.82, blue: 0.35)
  static let backdrop = LinearGradient(
    colors: [Color.bee.opacity(0.34), Color.bee.opacity(0.08), .black],
    startPoint: .top, endPoint: .bottom
  )

  static func avatar(_ name: String) -> Color { avatars[WatchAvatar.colorIndex(for: name) % avatars.count] }
}

extension View {
  @ViewBuilder
  func watchGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
    if #available(watchOS 26.0, *) {
      glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
    } else {
      background((tint ?? .white).opacity(tint == nil ? 0.13 : 0.24), in: shape)
    }
  }

  func watchBackdrop() -> some View {
    containerBackground(WatchPalette.backdrop, for: .navigation)
  }

  func toolbarGlyph() -> some View {
    foregroundStyle(.white).tint(Color(white: 0.24))
  }
}

struct BeeMark: View {
  var color: Color = .bee

  var body: some View {
    Canvas { context, size in
      let scale = min(size.width / 806, size.height / 535)
      let x0 = (size.width - 806 * scale) / 2
      let y0 = (size.height - 535 * scale) / 2
      func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: x0 + (x - 111) * scale, y: y0 + (y - 233) * scale, width: width * scale, height: height * scale)
      }
      let fill = GraphicsContext.Shading.color(color)
      context.fill(Path(ellipseIn: box(110, 342, 316, 316)), with: fill)
      context.fill(Path(ellipseIn: box(602, 342, 316, 316)), with: fill)
      context.fill(Path(roundedRect: box(331, 233, 365, 535), cornerRadius: 84 * scale), with: fill)
      context.blendMode = .clear
      context.fill(Path(ellipseIn: box(398, 333, 92, 92)), with: fill)
      context.fill(Path(ellipseIn: box(540, 333, 92, 92)), with: fill)
      context.fill(Path(roundedRect: box(398, 507, 235, 64), cornerRadius: 10 * scale), with: fill)
      context.fill(Path(roundedRect: box(400, 640, 235, 65), cornerRadius: 10 * scale), with: fill)
    }
    .aspectRatio(806 / 535, contentMode: .fit)
    .accessibilityHidden(true)
  }
}

struct BeeButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    StyledButton(configuration: configuration, prominent: true, tint: nil)
  }
}

struct GlassPillStyle: ButtonStyle {
  var tint: Color?

  func makeBody(configuration: Configuration) -> some View {
    StyledButton(configuration: configuration, prominent: false, tint: tint)
  }
}

private struct StyledButton: View {
  let configuration: ButtonStyleConfiguration
  let prominent: Bool
  let tint: Color?
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    let label = configuration.label
      .font(.body.weight(.semibold))
      .lineLimit(2)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: 44)
      .contentShape(Capsule())
    Group {
      if prominent {
        label
          .foregroundStyle(isEnabled ? Color.black : Color.white.opacity(0.4))
          .background(isEnabled ? Color.bee : Color.white.opacity(0.12), in: Capsule())
      } else {
        label
          .foregroundStyle(isEnabled ? (tint ?? .white) : Color.white.opacity(0.4))
          .watchGlass(in: Capsule(), tint: tint?.opacity(0.35), interactive: isEnabled)
      }
    }
    .scaleEffect(configuration.isPressed ? 0.96 : 1)
    .opacity(configuration.isPressed ? 0.85 : 1)
    .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct SendButtonStyle: ButtonStyle {
  var sending = false

  func makeBody(configuration: Configuration) -> some View {
    SendButton(configuration: configuration, sending: sending)
  }
}

private struct SendButton: View {
  let configuration: ButtonStyleConfiguration
  let sending: Bool
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    let active = isEnabled || sending
    configuration.label
      .font(.system(size: 17, weight: .bold))
      .foregroundStyle(active ? Color.black : Color.white.opacity(0.35))
      .frame(width: 42, height: 42)
      .background(active ? Color.bee : Color.white.opacity(0.12), in: Circle())
      .contentShape(Circle())
      .scaleEffect(configuration.isPressed ? 0.9 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct ChipStyle: ButtonStyle {
  var selected = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.footnote.weight(.semibold))
      .lineLimit(1)
      .foregroundStyle(selected ? Color.bee : .white)
      .padding(.horizontal, 11)
      .frame(minHeight: 32)
      .watchGlass(in: Capsule(), tint: selected ? Color.bee.opacity(0.35) : nil, interactive: true)
      .contentShape(Capsule())
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct FlowLayout: Layout {
  var spacing: CGFloat = 5

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    arrange(width: proposal.width ?? .infinity, subviews: subviews).size
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for (subview, frame) in zip(subviews, arrange(width: bounds.width, subviews: subviews).frames) {
      subview.place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size)
      )
    }
  }

  private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
    var frames: [CGRect] = []
    var origin = CGPoint.zero
    var rowHeight: CGFloat = 0
    var widest: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if origin.x > 0 && origin.x + size.width > width {
        origin = CGPoint(x: 0, y: origin.y + rowHeight + spacing)
        rowHeight = 0
      }
      frames.append(CGRect(origin: origin, size: size))
      origin.x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
      widest = max(widest, origin.x - spacing)
    }
    return (CGSize(width: widest, height: origin.y + rowHeight), frames)
  }
}

struct AvatarView: View {
  let name: String
  var size: CGFloat = 32

  var body: some View {
    let color = WatchPalette.avatar(name)
    Text(WatchAvatar.initials(for: name))
      .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
      .minimumScaleFactor(0.6)
      .foregroundStyle(color)
      .frame(width: size, height: size)
      .background(color.opacity(0.24), in: Circle())
      .accessibilityHidden(true)
  }
}

struct ChannelTile: View {
  var size: CGFloat = 32

  var body: some View {
    Image(systemName: "number")
      .font(.system(size: size * 0.5, weight: .heavy))
      .foregroundStyle(Color.bee)
      .frame(width: size, height: size)
      .background(Color.bee.opacity(0.22), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
      .accessibilityHidden(true)
  }
}

struct SymbolBadge: View {
  let systemName: String
  var color: Color = .bee
  var size: CGFloat = 36

  var body: some View {
    Image(systemName: systemName)
      .font(.system(size: size * 0.48, weight: .semibold))
      .foregroundStyle(color)
      .frame(width: size, height: size)
      .background(color.opacity(0.22), in: Circle())
      .accessibilityHidden(true)
  }
}

struct NoticeCard<Actions: View>: View {
  let message: String
  var symbol = "exclamationmark.triangle.fill"
  var tint: Color = WatchPalette.danger
  var symbolColor: Color = .orange
  @ViewBuilder var actions: Actions

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: symbol)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(symbolColor)
          .accessibilityHidden(true)
        Text(message)
          .font(.footnote)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
      }
      actions
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .watchGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), tint: tint.opacity(0.28))
  }
}

struct LoadingRow: View {
  let title: String

  var body: some View {
    HStack(spacing: 8) {
      ProgressView().frame(width: 22, height: 22)
      Text(title).font(.footnote).foregroundStyle(.secondary)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .frame(maxWidth: .infinity, minHeight: 44)
    .watchGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }
}

struct EmptyStateView: View {
  let symbol: String
  let title: String
  let message: String

  var body: some View {
    VStack(spacing: 6) {
      SymbolBadge(systemName: symbol, size: 46)
      Text(title).font(.headline)
      Text(message).font(.footnote).foregroundStyle(.secondary)
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 14)
    .accessibilityElement(children: .combine)
  }
}

#if DEBUG
  #Preview("Components") {
    ScrollView {
      VStack(spacing: 8) {
        BeeMark().frame(height: 36)
        HStack { AvatarView(name: "Mia Novak"); AvatarView(name: "Zeus"); ChannelTile() }
        Button("Connect") {}.buttonStyle(BeeButtonStyle())
        Button("Refresh", systemImage: "arrow.clockwise") {}.buttonStyle(GlassPillStyle())
        FlowLayout { ForEach(WatchComposer.quickReplies, id: \.self) { Button($0) {}.buttonStyle(ChipStyle()) } }
        NoticeCard(message: "Could not connect to the server.") { EmptyView() }
        LoadingRow(title: "Loading channels")
        EmptyStateView(symbol: "bubble.left.and.bubble.right.fill", title: "No channels yet", message: "Join a channel on your iPhone.")
      }
    }
  }
#endif
