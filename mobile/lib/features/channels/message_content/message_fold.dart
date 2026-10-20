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
    final forced = useState(forceExpanded);
    final overflows = useState(false);
    useEffect(() {
      if (forceExpanded) forced.value = true;
      return null;
    }, [forceExpanded]);
    final folded = !saved && !forced.value;

    void toggle() {
      forced.value = false;
      ref.read(expandedMessageFoldsProvider.notifier).set(foldId, folded);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FoldClip(
          foldHeight: foldHeight,
          folded: folded,
          onOverflowChanged: (value) {
            if (context.mounted) overflows.value = value;
          },
          child: child,
        ),
        if (overflows.value)
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

class _FoldClip extends SingleChildRenderObjectWidget {
  final double foldHeight;
  final bool folded;
  final ValueChanged<bool> onOverflowChanged;

  const _FoldClip({
    required this.foldHeight,
    required this.folded,
    required this.onOverflowChanged,
    required super.child,
  });

  @override
  _RenderFoldClip createRenderObject(BuildContext context) => _RenderFoldClip(
    foldHeight: foldHeight,
    folded: folded,
    onOverflowChanged: onOverflowChanged,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderFoldClip renderObject) {
    renderObject
      ..foldHeight = foldHeight
      ..folded = folded
      ..onOverflowChanged = onOverflowChanged;
  }
}

class _RenderFoldClip extends RenderProxyBox {
  _RenderFoldClip({
    required double foldHeight,
    required bool folded,
    required this.onOverflowChanged,
  }) : _foldHeight = foldHeight,
       _folded = folded;

  ValueChanged<bool> onOverflowChanged;
  final _clipLayer = LayerHandle<ClipRectLayer>();
  final _maskLayer = LayerHandle<ShaderMaskLayer>();
  bool? _reportedOverflow;
  bool _clipping = false;

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

  @override
  bool get alwaysNeedsCompositing => _clipping;

  double _foldedHeight(double height) =>
      _folded && height > _foldHeight + 0.5 ? _foldHeight : height;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    final childSize = child.getDryLayout(
      constraints.copyWith(maxHeight: double.infinity),
    );
    return constraints.constrain(
      Size(childSize.width, _foldedHeight(childSize.height)),
    );
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _foldedHeight(super.computeMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _foldedHeight(super.computeMaxIntrinsicHeight(width));

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      _setClipping(false);
      return;
    }
    child.layout(
      constraints.copyWith(maxHeight: double.infinity),
      parentUsesSize: true,
    );
    final overflow = child.size.height > _foldHeight + 0.5;
    final clipping = _folded && overflow;
    size = constraints.constrain(
      Size(child.size.width, clipping ? _foldHeight : child.size.height),
    );
    _setClipping(clipping);
    if (_reportedOverflow != overflow) {
      _reportedOverflow = overflow;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (attached && _reportedOverflow == overflow) {
          onOverflowChanged(overflow);
        }
      });
    }
  }

  void _setClipping(bool value) {
    if (value == _clipping) return;
    _clipping = value;
    markNeedsCompositingBitsUpdate();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (!_clipping) {
      _clipLayer.layer = null;
      _maskLayer.layer = null;
      context.paintChild(child, offset);
      return;
    }
    final bounds = Offset.zero & size;
    final fadeStart = size.height <= _messageFoldFadeExtent
        ? 0.0
        : 1 - _messageFoldFadeExtent / size.height;
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
        ..maskRect = clipOffset & size
        ..blendMode = BlendMode.dstIn;
      _maskLayer.layer = mask;
      clipContext.pushLayer(
        mask,
        (maskContext, maskOffset) => maskContext.paintChild(child, maskOffset),
        clipOffset,
      );
    }, oldLayer: _clipLayer.layer);
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _clipping ? Offset.zero & size : null;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (_clipping && !(Offset.zero & size).contains(position)) return false;
    return super.hitTestChildren(result, position: position);
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    _maskLayer.layer = null;
    super.dispose();
  }
}
