import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../shared/theme/theme.dart';

/// Paints the composer dock on an opaque page-colour band and reports its
/// laid-out height, which message timelines use as scroll padding.
class ComposerDockSizeReporter extends HookWidget {
  final ValueChanged<double> onHeightChanged;
  final Widget child;

  const ComposerDockSizeReporter({
    super.key,
    required this.onHeightChanged,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final sizeKey = useMemoized(GlobalKey.new);
    final lastHeight = useRef<double?>(null);

    void reportHeight() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final renderObject = sizeKey.currentContext?.findRenderObject();
        if (renderObject is! RenderBox || !renderObject.hasSize) return;
        final height = renderObject.size.height;
        final previous = lastHeight.value;
        if (previous != null && (previous - height).abs() < 0.5) return;
        lastHeight.value = height;
        onHeightChanged(height);
      });
    }

    useEffect(() {
      reportHeight();
      return null;
    }, const []);

    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        reportHeight();
        return true;
      },
      child: SizeChangedLayoutNotifier(
        child: KeyedSubtree(
          key: sizeKey,
          child: DecoratedBox(
            key: const ValueKey('composer-dock-band'),
            decoration: BoxDecoration(
              color: context.colors.surface,
              border: Border(
                top: BorderSide(
                  color: navigationDivider(context, 0.05),
                  width: 1,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: Grid.xxs),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
