part of '../message_content.dart';

const messageFoldLines = 8;
const _messageFoldFadeExtent = 24.0;
const _maxExpandedMessageFolds = 500;

final expandedMessageFoldsProvider =
    NotifierProvider<ExpandedMessageFolds, Set<String>>(
      ExpandedMessageFolds.new,
    );

class ExpandedMessageFolds extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void set(String id, bool expanded) {
    final next = {...state}..remove(id);
    if (expanded) {
      next.add(id);
      if (next.length > _maxExpandedMessageFolds) next.remove(next.first);
    }
    state = next;
  }
}

class _MessageFold extends HookConsumerWidget {
  final String foldId;
  final double foldHeight;
  final bool forceExpanded;
  final Widget child;

  const _MessageFold({
    required this.foldId,
    required this.foldHeight,
    required this.forceExpanded,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(
      expandedMessageFoldsProvider.select((ids) => ids.contains(foldId)),
    );
    final userToggled = useState(false);
    useEffect(() {
      if (!forceExpanded) return null;
      userToggled.value = false;
      if (!saved) {
        Future.microtask(
          () =>
              ref.read(expandedMessageFoldsProvider.notifier).set(foldId, true),
        );
      }
      return null;
    }, [forceExpanded, foldId]);
    final folded = !saved && !(forceExpanded && !userToggled.value);

    void toggle() {
      userToggled.value = true;
      ref.read(expandedMessageFoldsProvider.notifier).set(foldId, folded);
    }

    return _FoldLayout(
      foldHeight: foldHeight,
      folded: folded,
      children: [
        child,
        TextButton(
          key: const ValueKey('message-fold-toggle'),
          onPressed: toggle,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(Grid.xl, Grid.md),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            alignment: Alignment.centerLeft,
            foregroundColor: context.colors.primary,
            textStyle: context.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Text(folded ? 'Show more' : 'Show less'),
        ),
      ],
    );
  }
}

class _FoldLayout extends MultiChildRenderObjectWidget {
  final double foldHeight;
  final bool folded;

  const _FoldLayout({
    required this.foldHeight,
    required this.folded,
    required super.children,
  });

  @override
  _RenderFoldLayout createRenderObject(BuildContext context) =>
      _RenderFoldLayout(foldHeight: foldHeight, folded: folded);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFoldLayout renderObject,
  ) {
    renderObject
      ..foldHeight = foldHeight
      ..folded = folded;
  }
}

class _FoldParentData extends ContainerBoxParentData<RenderBox> {}

/// Lays out the body and, only when the body is taller than the fold, the
/// toggle below it, in one pass so no later frame changes the row height.
class _RenderFoldLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FoldParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FoldParentData> {
  _RenderFoldLayout({required double foldHeight, required bool folded})
    : _foldHeight = foldHeight,
      _folded = folded;

  final _clipLayer = LayerHandle<ClipRectLayer>();
  final _maskLayer = LayerHandle<ShaderMaskLayer>();
  bool _clipping = false;
  bool _overflow = false;
  double _bodyHeight = 0;

  double _foldHeight;
  set foldHeight(double value) {
    if (value == _foldHeight) return;
    _foldHeight = value;
    markNeedsLayout();
  }

  bool _folded;
  set folded(bool value) {
    if (value == _folded) return;
    _folded = value;
    markNeedsLayout();
  }

  RenderBox get _body => firstChild!;
  RenderBox get _toggle => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FoldParentData) {
      child.parentData = _FoldParentData();
    }
  }

  @override
  bool get alwaysNeedsCompositing => _clipping;

  bool _overflows(double height) => height > _foldHeight + 0.5;

  double _foldedHeight(double height) =>
      _folded && _overflows(height) ? _foldHeight : height;

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _body.getMinIntrinsicWidth(double.infinity),
    _toggle.getMinIntrinsicWidth(double.infinity),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _body.getMaxIntrinsicWidth(double.infinity);

  double _intrinsicHeight(double width) {
    final body = _body.getMaxIntrinsicHeight(width);
    return _foldedHeight(body) +
        (_overflows(body) ? _toggle.getMaxIntrinsicHeight(width) : 0);
  }

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsicHeight(width);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final inner = constraints.copyWith(
      minHeight: 0,
      maxHeight: double.infinity,
    );
    final body = _body.getDryLayout(inner);
    var width = body.width;
    var height = _foldedHeight(body.height);
    if (_overflows(body.height)) {
      final toggle = _toggle.getDryLayout(inner.loosen());
      width = math.max(width, toggle.width);
      height += toggle.height;
    }
    return constraints.constrain(Size(width, height));
  }

  @override
  void performLayout() {
    final inner = constraints.copyWith(
      minHeight: 0,
      maxHeight: double.infinity,
    );
    _body.layout(inner, parentUsesSize: true);
    _overflow = _overflows(_body.size.height);
    final clipping = _folded && _overflow;
    _bodyHeight = clipping ? _foldHeight : _body.size.height;
    var width = _body.size.width;
    var height = _bodyHeight;
    if (_overflow) {
      _toggle.layout(inner.loosen(), parentUsesSize: true);
      (_toggle.parentData! as _FoldParentData).offset = Offset(0, _bodyHeight);
      width = math.max(width, _toggle.size.width);
      height += _toggle.size.height;
    } else {
      _toggle.layout(BoxConstraints.tight(Size.zero));
    }
    size = constraints.constrain(Size(width, height));
    if (clipping != _clipping) {
      _clipping = clipping;
      markNeedsCompositingBitsUpdate();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_overflow) {
      context.paintChild(
        _toggle,
        offset + (_toggle.parentData! as _FoldParentData).offset,
      );
    }
    if (!_clipping) {
      _clipLayer.layer = null;
      _maskLayer.layer = null;
      context.paintChild(_body, offset);
      return;
    }
    final bounds = Offset.zero & Size(_body.size.width, _bodyHeight);
    final fadeStart = _bodyHeight <= _messageFoldFadeExtent
        ? 0.0
        : 1 - _messageFoldFadeExtent / _bodyHeight;
    _clipLayer.layer = context.pushClipRect(needsCompositing, offset, bounds, (
      clipContext,
      clipOffset,
    ) {
      final mask = (_maskLayer.layer ?? ShaderMaskLayer())
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFF000000), Color(0x00000000)],
          stops: [fadeStart, 1],
        ).createShader(bounds)
        ..maskRect = clipOffset & bounds.size
        ..blendMode = BlendMode.dstIn;
      _maskLayer.layer = mask;
      clipContext.pushLayer(
        mask,
        (maskContext, maskOffset) => maskContext.paintChild(_body, maskOffset),
        clipOffset,
      );
    }, oldLayer: _clipLayer.layer);
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _clipping && child == _body
      ? Offset.zero & Size(_body.size.width, _bodyHeight)
      : null;

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    visitor(_body);
    if (_overflow) visitor(_toggle);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (_overflow) {
      final offset = (_toggle.parentData! as _FoldParentData).offset;
      final hit = result.addWithPaintOffset(
        offset: offset,
        position: position,
        hitTest: (result, transformed) =>
            _toggle.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    if (_clipping && position.dy > _bodyHeight) return false;
    return _body.hitTest(result, position: position);
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    _maskLayer.layer = null;
    super.dispose();
  }
}
