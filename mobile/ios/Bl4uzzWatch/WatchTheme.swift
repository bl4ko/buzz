import SwiftUI

extension Color {
  static let bee = Color(red: 247 / 255, green: 194 / 255, blue: 52 / 255)
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
  static let bubble = Color.white.opacity(0.14)
  static let success = Color(red: 0.19, green: 0.82, blue: 0.35)
  static let backdrop = LinearGradient(
    colors: [
      Color(red: 31 / 255, green: 41 / 255, blue: 112 / 255),
      Color(red: 14 / 255, green: 22 / 255, blue: 64 / 255),
      .black,
    ],
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

struct WatchGlassGroup<Content: View>: View {
  var spacing: CGFloat = 0
  @ViewBuilder var content: Content

  var body: some View {
    if #available(watchOS 26.0, *) {
      GlassEffectContainer(spacing: spacing) { content }
    } else {
      content
    }
  }
}

struct OlympusMark: View {
  private typealias Points = [(CGFloat, CGFloat)]
  private static let lit: Points = [
    (86, 940), (270, 640), (306, 622), (512, 236), (544, 420), (500, 590), (560, 940),
  ]
  private static let shade: Points = [
    (512, 236), (606, 402), (636, 388), (770, 628), (800, 618), (948, 940), (560, 940), (500, 590), (544, 420),
  ]
  private static let snow: Points = [
    (512, 236), (405, 436), (442, 412), (468, 456), (500, 406), (524, 452), (544, 420), (574, 460), (602, 416),
    (626, 448), (658, 428), (636, 388), (606, 402),
  ]
  private static let bolt: Points = [
    (706, 56), (846, 56), (772, 256), (862, 256), (572, 628), (654, 346), (566, 346),
  ]
  private static let fold: Points = [(770, 56), (846, 56), (772, 256), (862, 256), (572, 628), (704, 304)]

  private static func rgb(_ hex: UInt32) -> Color {
    Color(
      red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255
    )
  }

  private static func polygon(_ points: Points) -> Path {
    var path = Path()
    path.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
    path.closeSubpath()
    return path
  }

  private static func fill(_ colors: [UInt32], from start: CGPoint, to end: CGPoint) -> GraphicsContext.Shading {
    .linearGradient(Gradient(colors: colors.map(rgb)), startPoint: start, endPoint: end)
  }

  private static func vertical(_ colors: [UInt32], _ top: CGFloat, _ bottom: CGFloat) -> GraphicsContext.Shading {
    fill(colors, from: CGPoint(x: 0, y: top), to: CGPoint(x: 0, y: bottom))
  }

  var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height) / 840
      context.translateBy(
        x: (size.width - 840 * scale) / 2 - 92 * scale, y: (size.height - 840 * scale) / 2 - 31 * scale
      )
      context.scaleBy(x: scale, y: scale)
      let ring = Path(ellipseIn: CGRect(x: 168, y: 124, width: 688, height: 688))
      context.fill(
        Path(ellipseIn: CGRect(x: 198, y: 154, width: 628, height: 628)),
        with: .radialGradient(
          Gradient(colors: ([0x7A6CF2, 0x3E40B0, 0x151C56] as [UInt32]).map(Self.rgb)),
          center: CGPoint(x: 512, y: 372), startRadius: 0, endRadius: 400
        )
      )
      var disc = context
      disc.clip(to: ring)
      disc.fill(Self.polygon(Self.lit), with: Self.vertical([0x93A8F6, 0x5068CA, 0x2A3A8E], 236, 940))
      disc.fill(Self.polygon(Self.shade), with: Self.vertical([0x34459A, 0x1C2760, 0x101742], 236, 940))
      disc.fill(Self.polygon(Self.snow), with: Self.vertical([0xFFFFFF, 0xF3E8CC], 236, 460))
      context.stroke(
        ring,
        with: Self.fill(
          [0xFFEFA6, 0xF7C234, 0xE39A16, 0xB46A0C], from: CGPoint(x: 150, y: 110), to: CGPoint(x: 870, y: 830)
        ),
        lineWidth: 84
      )
      context.translateBy(x: 716, y: 342)
      context.scaleBy(x: 1.1, y: 1.1)
      context.translateBy(x: -716, y: -342)
      context.fill(Self.polygon(Self.bolt), with: Self.vertical([0xFFFDF0, 0xFFF0B8, 0xFFD866], 56, 628))
      context.fill(Self.polygon(Self.fold), with: Self.vertical([0xFFDC5C, 0xF6B21E, 0xDC7C0C], 56, 628))
    }
    .aspectRatio(1, contentMode: .fit)
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
        OlympusMark().frame(height: 36)
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
