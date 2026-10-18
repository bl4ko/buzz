import 'package:buzz/shared/theme/theme.dart';
import 'package:buzz/shared/widgets/frosted_app_bar.dart';
import 'package:buzz/shared/widgets/frosted_scroll_under_scope.dart';
import 'package:buzz/shared/widgets/ios_glass_navigation_button.dart';
import 'package:buzz/shared/widgets/ios_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets('iOS conversations request an opaque native bar', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Stack(
            children: [
              FrostedAppBar(
                title: Text('Alice'),
                nativeSubtitle: 'Online',
                opaque: true,
              ),
            ],
          ),
        ),
      ),
    );
    final view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.creationParams, containsPair('opaque', true));
    expect(view.creationParams, containsPair('subtitle', 'Online'));
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'opaque header covers content through its bottom row on ${platform.name}',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.padding = const FakeViewPadding(top: 141);
        addTearDown(tester.view.reset);
        final messenger = tester.binding.defaultBinaryMessenger;
        final views = <MethodChannel>[];
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
          call,
        ) async {
          if (call.method == 'create') {
            final id = (call.arguments as Map)['id'];
            final view = MethodChannel('${IosNavigationBar.viewType}/$id');
            views.add(view);
            messenger.setMockMethodCallHandler(view, (call) async => null);
          }
          return null;
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(
            SystemChannels.platform_views,
            null,
          );
          for (final view in views) {
            messenger.setMockMethodCallHandler(view, null);
          }
        });
        const content = Color(0xFFFF0000);
        final shot = GlobalKey();
        late double headerHeight;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: RepaintBoundary(
                key: shot,
                child: Builder(
                  builder: (context) {
                    headerHeight = frostedAppBarHeight(
                      context,
                      bottomHeight: 40,
                    );
                    return const Stack(
                      children: [
                        Positioned.fill(child: ColoredBox(color: content)),
                        FrostedAppBar(
                          title: Text('Conversation'),
                          opaque: true,
                          bottom: Center(child: Text('Tabs')),
                          bottomHeight: 40,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
        final surface = Theme.of(
          tester.element(find.byType(Stack).first),
        ).colorScheme.surface;
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(shot),
        );
        final pixels = (await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData();
          image.dispose();
          return data!;
        }))!;
        final width = boundary.size.width.toInt();
        Color pixel(int x, int y) {
          final i = (y * width + x) * 4;
          return Color.fromARGB(
            pixels.getUint8(i + 3),
            pixels.getUint8(i),
            pixels.getUint8(i + 1),
            pixels.getUint8(i + 2),
          );
        }

        final bottom = headerHeight.round();
        for (var y = 0; y < bottom - 1; y++) {
          expect(pixel(8, y), surface, reason: 'row $y');
        }
        expect(pixel(8, bottom - 1), isNot(content));
        expect(pixel(8, bottom + 1), content);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets(
    'opaque conversation backdrop stays mounted across scroll and keyboard changes',
    (tester) async {
      final scrolled = ValueNotifier(false);
      addTearDown(scrolled.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ValueListenableBuilder<bool>(
            valueListenable: scrolled,
            builder: (_, value, _) => FrostedScrollUnderScope(
              isScrolledUnder: value,
              child: const Stack(
                children: [
                  FrostedAppBar(title: Text('Conversation'), opaque: true),
                ],
              ),
            ),
          ),
        ),
      );
      final background = find.byKey(
        const ValueKey('frosted-app-bar-background'),
      );
      final backdrop = tester.element(background);
      final initial = tester.widget<Container>(background).decoration;
      expect(
        (initial! as BoxDecoration).color,
        Theme.of(backdrop).colorScheme.surface,
      );
      addTearDown(tester.view.reset);
      for (final under in [true, false, true, false]) {
        scrolled.value = under;
        tester.view.viewInsets = FakeViewPadding(bottom: under ? 300 : 0);
        await tester.pump();
        expect(find.byType(BackdropFilter), findsNothing);
        expect(tester.element(background), same(backdrop));
        expect(tester.widget<Container>(background).decoration, initial);
      }
    },
  );

  testWidgets('title row and reported height grow with accessible text', (
    tester,
  ) async {
    const titleStyle = TextStyle(fontSize: 22, height: 1.3);
    late double reportedHeight;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Builder(
            builder: (context) {
              reportedHeight = frostedAppBarHeight(
                context,
                titleStyle: titleStyle,
              );
              return const Stack(
                children: [
                  FrostedAppBar(title: Text('Search'), titleStyle: titleStyle),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final clip = find.descendant(
      of: find.byType(FrostedAppBar),
      matching: find.byType(ClipRect),
    );
    expect(reportedHeight, greaterThan(48));
    expect(tester.getSize(clip).height, closeTo(reportedHeight, 0.01));
    expect(tester.getSize(find.text('Search')).height, greaterThan(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom multi-line title height matches reported height', (
    tester,
  ) async {
    const titleContentHeight = 64.0;
    late double reportedHeight;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            reportedHeight = frostedAppBarHeight(
              context,
              titleContentHeight: titleContentHeight,
            );
            return const Stack(
              children: [
                FrostedAppBar(
                  titleContentHeight: titleContentHeight,
                  title: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text('Title'), Text('Subtitle')],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final clip = find.descendant(
      of: find.byType(FrostedAppBar),
      matching: find.byType(ClipRect),
    );
    expect(tester.getSize(clip).height, closeTo(reportedHeight, 0.01));
    expect(reportedHeight, closeTo(titleContentHeight + Grid.xs + 1, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('centers a title between asymmetric navigation controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Stack(
          children: [
            FrostedAppBar(
              centerTitle: true,
              leading: SizedBox(width: 48, height: 48),
              title: Text('Profile', key: ValueKey('centered-title')),
              actions: [SizedBox(width: 96, height: 48)],
            ),
          ],
        ),
      ),
    );

    final titleRect = tester.getRect(
      find.byKey(const ValueKey('centered-title')),
    );
    expect(
      titleRect.center.dx,
      closeTo(
        tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
        0.01,
      ),
    );
  });

  testWidgets('uses the UIKit navigation bar back action on iOS', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Stack(
                    children: [
                      FrostedAppBar(
                        title: Text(
                          'Destination',
                          key: ValueKey('destination-title'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final nativeView = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(nativeView.viewType, IosNavigationBar.viewType);
    final navigation = tester.widget<IosNavigationBar>(
      find.byType(IosNavigationBar),
    );
    expect(navigation.title, 'Destination');
    expect(navigation.onBack, isNotNull);
    navigation.onBack!();
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.byType(IosNavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('uses the theme primary color for automatic navigation glyphs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const Stack(
                  children: [FrostedAppBar(title: Text('Destination'))],
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final backButton = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Back',
      ),
    );
    expect(backButton.color, AppTheme.light().colorScheme.primary);
  });

  testWidgets('replaces native glass while a Flutter backdrop is active', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final suppressNativeView = ValueNotifier(false);
    addTearDown(suppressNativeView.dispose);
    var pressCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: IosGlassNavigationButton(
            icon: IosGlassNavigationIcon.back,
            semanticLabel: 'Back',
            onPressed: () => pressCount++,
            nativeViewSuppressed: suppressNativeView,
          ),
        ),
      ),
    );

    expect(find.byType(UiKitView), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ios-glass-navigation-flutter-fallback')),
      findsNothing,
    );
    expect(find.bySemanticsLabel('Back'), findsNothing);

    suppressNativeView.value = true;
    await tester.pump();

    expect(find.byType(UiKitView), findsNothing);
    expect(
      find.byKey(const ValueKey('ios-glass-navigation-flutter-fallback')),
      findsOneWidget,
    );
    final fallbackFinder = find.bySemanticsLabel('Back');
    expect(fallbackFinder, findsOneWidget);
    final fallbackSemantics = tester.getSemantics(fallbackFinder);
    expect(fallbackSemantics.flagsCollection.isButton, isTrue);
    expect(
      fallbackSemantics.flagsCollection.isEnabled.toString(),
      'Tristate.isTrue',
    );
    expect(
      fallbackSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        viewId: tester.view.viewId,
        nodeId: fallbackSemantics.id,
      ),
    );
    await tester.pump();
    expect(pressCount, 1);

    suppressNativeView.value = false;
    await tester.pump();

    expect(find.byType(UiKitView), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
