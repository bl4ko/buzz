import 'dart:io';

import 'package:buzz/shared/push/dev_push_lease.dart';
import 'package:buzz/shared/push/push_relay_capability_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('NIP-11 extensions preserve valid relay push capability', () async {
    final information = await File(
      'test/shared/push/fixtures/relay_information_with_extensions.json',
    ).readAsString();
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://buzz.bl4ko.com/');
      expect(request.headers['Accept'], 'application/nostr+json');
      return http.Response(
        information,
        200,
        headers: {'content-type': 'application/nostr+json; charset=utf-8'},
      );
    });
    addTearDown(client.close);

    final descriptor = await discoverBuzzPushRelayCapability(
      'https://buzz.bl4ko.com',
      fetchDescriptor: (origin) =>
          fetchBuzzPushLeaseDescriptor(origin, client: client),
    );
    expect(descriptor, isNotNull);
    expect(descriptor!.origin, 'wss://buzz.bl4ko.com');
    expect(descriptor.executorKeyId, 'relay-v1');
    expect(descriptor.transport, 'apns');
  });

  for (final failure in <Object>[
    const FormatException('malformed descriptor'),
    StateError('relay unreachable'),
  ]) {
    test('$failure keeps capability inactive', () async {
      final descriptor = await discoverBuzzPushRelayCapability(
        'https://relay.example',
        fetchDescriptor: (_) async => throw failure,
      );

      expect(descriptor, isNull);
    });
  }
}
