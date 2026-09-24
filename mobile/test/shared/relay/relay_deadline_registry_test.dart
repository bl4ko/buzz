import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  final deadline = RelayException(503, '{"error":"query timed out"}');

  test('records only deadlines and clears on request', () {
    final registry = RelayDeadlineRegistry();
    expect(registry.record('a', Exception('reset')), isFalse);
    expect(registry.isTerminal('a'), isFalse);
    expect(registry.record('a', deadline), isTrue);
    expect(registry.terminalError('a'), same(deadline));
    registry.clear('a');
    expect(registry.isTerminal('a'), isFalse);
  });

  test('a relay or account switch starts an empty registry', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final config = container.read(relayConfigProvider.notifier);
    config.update(baseUrl: 'https://one.example');
    container.read(relayDeadlineRegistryProvider).record('k', deadline);
    expect(container.read(relayDeadlineRegistryProvider).isTerminal('k'), true);
    config.update(baseUrl: 'https://two.example');
    expect(
      container.read(relayDeadlineRegistryProvider).isTerminal('k'),
      false,
    );
    container.read(relayDeadlineRegistryProvider).record('k', deadline);
    config.update(baseUrl: 'https://two.example', nsec: 'nsec1other');
    expect(
      container.read(relayDeadlineRegistryProvider).isTerminal('k'),
      false,
    );
  });
}
