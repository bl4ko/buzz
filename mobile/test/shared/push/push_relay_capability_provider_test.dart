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

    var requests = 0;
    await startBuzzPushRegistrationIfCapable(
      descriptor,
      startRegistration: () async => requests += 1,
    );
    expect(requests, 1);
  });

  test(
    'valid capability starts independent permission and APNs registration',
    () async {
      var requests = 0;

      await startBuzzPushRegistrationIfCapable(
        _descriptor,
        startRegistration: () async {
          requests += 1;
        },
      );

      expect(requests, 1);
    },
  );

  test(
    'missing capability cannot start permission or APNs registration',
    () async {
      var requests = 0;

      await startBuzzPushRegistrationIfCapable(
        null,
        startRegistration: () async {
          requests += 1;
        },
      );

      expect(requests, 0);
    },
  );

  for (final failure in <Object>[
    const FormatException('malformed descriptor'),
    StateError('relay unreachable'),
  ]) {
    test('$failure keeps capability inactive without registration', () async {
      final descriptor = await discoverBuzzPushRelayCapability(
        'https://relay.example',
        fetchDescriptor: (_) async => throw failure,
      );
      var requests = 0;

      await startBuzzPushRegistrationIfCapable(
        descriptor,
        startRegistration: () async {
          requests += 1;
        },
      );

      expect(descriptor, isNull);
      expect(requests, 0);
    });
  }
}

const _descriptor = BuzzPushLeaseDescriptor(
  origin: 'wss://relay.example',
  executorKeyId: 'relay-v1',
  executorPubkey:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  transport: 'apns',
  maxLeaseTtlSeconds: 3600,
  maxContentLength: 4096,
  maxPlaintextLength: 4096,
  maxEndpointLength: 2048,
  maxStringLength: 512,
);
