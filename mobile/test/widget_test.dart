import 'package:buzz/shared/hosted/hosted_environment.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:buzz/shared/community/paired_community_landing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buzz/app.dart';
import 'package:buzz/features/age_gate/age_signal_provider.dart';
import 'package:buzz/shared/auth/auth.dart';
import 'package:buzz/shared/olympus/olympus_bolt_spinner.dart';
import 'package:buzz/shared/olympus/olympus_colors.dart';
import 'package:buzz/shared/olympus/olympus_splash.dart';
import 'package:buzz/shared/relay/app_lifecycle_provider.dart';
import 'package:buzz/shared/relay/relay_closed_policy.dart';
import 'package:buzz/shared/theme/theme_provider.dart';

void main() {
  testWidgets('pairing loading cover blocks hidden input and semantics', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => _FakeAuthNotifier()),
        ageSignalProvider.overrideWith(() => _AllowedAgeSignalNotifier()),
        savedPrefsProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    final semantics = tester.ensureSemantics();
    String semanticsTree() => tester
        .binding
        .renderViews
        .single
        .owner!
        .semanticsOwner!
        .rootSemanticsNode!
        .toStringDeep();
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    await tester.pump();
    var taps = 0;
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: TextButton(
                onPressed: () => taps++,
                child: const Text('Hidden action'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.text('Hidden action');
    final location = tester.getCenter(button);
    expect(semanticsTree(), contains('Hidden action'));
    container
        .read(pairedCommunityLandingProvider.notifier)
        .request(
          Community(
            id: 'test',
            addedAt: DateTime(2026),
            name: 'Test',
            relayUrl: 'https://relay.test',
          ),
        );
    await tester.pump();
    await tester.tapAt(location);
    expect(taps, 0);
    expect(semanticsTree(), isNot(contains('Hidden action')));
    container.read(pairedCommunityLandingProvider.notifier).clear();
    await tester.pump();
    expect(semanticsTree(), contains('Hidden action'));
    await tester.tapAt(location);
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets('App renders pairing page when unauthenticated', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(() => _FakeAuthNotifier()),
          ageSignalProvider.overrideWith(() => _AllowedAgeSignalNotifier()),
          savedPrefsProvider.overrideWithValue(prefs),
        ],
        child: const App(),
      ),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('Olympus'), findsOneWidget);
    expect(find.text('Sign in with email').hitTestable(), findsNothing);
    expect(
      find.text('or sign in with email'),
      HostedEnvironment.enabled ? findsOneWidget : findsNothing,
    );
    expect(find.text('Scan a QR code'), findsOneWidget);
  });

  testWidgets('starts on the navy Olympus splash, then shows the welcome', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final auth = Completer<AuthState>();
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(() => _PendingAuthNotifier(auth.future)),
          ageSignalProvider.overrideWith(() => _AllowedAgeSignalNotifier()),
          savedPrefsProvider.overrideWithValue(prefs),
        ],
        child: const App(),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<ColoredBox>(find.byKey(const Key('olympus-splash'))).color,
      OlympusColors.navy,
    );
    expect(
      tester.widget<OlympusBoltSpinner>(find.byType(OlympusBoltSpinner)).color,
      OlympusColors.gold,
    );
    expect(
      tester.getCenter(find.byType(OlympusSplash)),
      tester.getCenter(find.byType(App)),
    );
    expect(find.bySemanticsLabel('Starting Buzz'), findsOneWidget);

    auth.complete(const AuthState(status: AuthStatus.unauthenticated));
    await tester.pump();
    await tester.pump();
    expect(find.byType(OlympusSplash), findsNothing);
    expect(find.bySemanticsLabel('Olympus'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('unavailable secure storage offers retry instead of pairing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var builds = 0;
    var listBuilds = 0;

    await tester.pumpWidget(
      ProviderScope(
        retry: relayProviderRetry,
        overrides: [
          communityListProvider.overrideWith(
            () => _FakeCommunityList(() => listBuilds++),
          ),
          authProvider.overrideWith(
            () => _FakeAuthNotifier(() {
              if (++builds < 3) throw const SecureStorageUnavailableException();
            }),
          ),
          appLifecycleProvider.overrideWith(_IdleLifecycle.new),
          ageSignalProvider.overrideWith(() => _AllowedAgeSignalNotifier()),
          savedPrefsProvider.overrideWithValue(prefs),
        ],
        child: const App(),
      ),
    );
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Scan a QR code'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(builds, 2);
    expect(listBuilds, 2);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(builds, 3);
    expect(find.text('Scan a QR code'), findsOneWidget);
  });
}

class _PendingAuthNotifier extends AuthNotifier {
  _PendingAuthNotifier(this._state);

  final Future<AuthState> _state;

  @override
  Future<AuthState> build() => _state;
}

class _FakeCommunityList extends CommunityListNotifier {
  _FakeCommunityList(this._onBuild);

  final void Function() _onBuild;

  @override
  Future<List<Community>> build() async {
    _onBuild();
    return [];
  }
}

class _IdleLifecycle extends AppLifecycleNotifier {
  @override
  AppLifecycleState build() => AppLifecycleState.resumed;
}

class _AllowedAgeSignalNotifier extends AgeSignalNotifier {
  @override
  AgeSignalState build() => AgeSignalState.allowed;

  @override
  Future<void> request() async {}
}

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier([this._onBuild]);

  final void Function()? _onBuild;

  @override
  Future<AuthState> build() async {
    _onBuild?.call();
    return const AuthState(status: AuthStatus.unauthenticated);
  }
}
