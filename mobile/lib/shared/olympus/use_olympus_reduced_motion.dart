import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

// iOS reports Reduce Motion only through AccessibilityFeatures.reduceMotion.
bool useOlympusReducedMotion(BuildContext context) {
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  final platform = useState(dispatcher.accessibilityFeatures.reduceMotion);
  useEffect(() {
    final observer = _AccessibilityObserver(
      () => platform.value = dispatcher.accessibilityFeatures.reduceMotion,
    );
    WidgetsBinding.instance.addObserver(observer);
    return () => WidgetsBinding.instance.removeObserver(observer);
  }, const []);
  return MediaQuery.disableAnimationsOf(context) || platform.value;
}

class _AccessibilityObserver with WidgetsBindingObserver {
  _AccessibilityObserver(this.onChange);

  final VoidCallback onChange;

  @override
  void didChangeAccessibilityFeatures() => onChange();
}
