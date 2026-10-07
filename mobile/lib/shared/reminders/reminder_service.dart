import 'dart:convert';
import 'dart:typed_data';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nostr/nostr.dart' as nostr;

import '../crypto/ecdh.dart';
import '../crypto/nip44.dart';
import '../relay/relay.dart';

/// The message a reminder points back to. Mirrors the desktop
/// `ReminderTarget` shape (`desktop/src/features/reminders/lib/reminderTypes.ts`)
/// so reminders created on mobile are readable by desktop and vice versa.
class ReminderTarget {
  /// Event ID of the target message.
  final String eventId;

  /// Channel ID where the message lives.
  final String channelId;

  /// Preview text of the target message (truncated).
  final String preview;

  /// Author pubkey of the target message.
  final String authorPubkey;

  const ReminderTarget({
    required this.eventId,
    required this.channelId,
    required this.preview,
    required this.authorPubkey,
  });

  Map<String, dynamic> toJson() => {
    'eventId': eventId,
    'channelId': channelId,
    'preview': preview,
    'authorPubkey': authorPubkey,
  };
}

/// Build the NIP-ER reminder plaintext for a new pending reminder.
///
/// Matches the JSON desktop writes in `reminderService.ts#createReminder`:
/// `{"target": {...}, "note": <optional>, "status": "pending"}`. `note` is
/// omitted entirely when absent so both clients parse each other's payloads.
String buildReminderPlaintext({
  ReminderTarget? target,
  String? note,
  String status = 'pending',
}) {
  if (!const ['pending', 'done', 'cancelled'].contains(status)) {
    throw ArgumentError('Invalid reminder status');
  }
  if (target == null && (note == null || note.isEmpty)) {
    throw ArgumentError('A saved item must have a message or note');
  }
  return jsonEncode({
    if (target != null) 'target': target.toJson(),
    if (note != null && note.isNotEmpty) 'note': note,
    'status': status,
  });
}

/// Generate a reminder `d`-tag with 128 bits of entropy (NIP-ER MUST).
String randomReminderDTag() {
  final bytes = secureRandomBytes(16);
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Tags for a new pending reminder event: `d` plus strict-decimal
/// `not_before`, exactly as the relay's NIP-ER validator expects.
List<List<String>> buildReminderTags({required String dTag, int? notBefore}) {
  if (notBefore != null && notBefore < 0) {
    throw ArgumentError('notBefore must be a non-negative Unix timestamp');
  }
  return [
    ['d', dTag],
    if (notBefore != null) ['not_before', '$notBefore'],
  ];
}

/// NIP-44 self-encryption for author-private reminder payloads. Derives the
/// conversation key to the author's own pubkey, matching the desktop's
/// `nip44_encrypt_to_self` Tauri command.
class ReminderCrypto {
  final Uint8List _conversationKey;

  ReminderCrypto(String nsec, String pubkey)
    : _conversationKey = _deriveKey(nsec, pubkey);

  static Uint8List _deriveKey(String nsec, String pubkey) {
    final privkeyHex = nostr.Nip19.decode(payload: nsec).data;
    return getConversationKey(privkeyHex, pubkey);
  }

  String encrypt(String plaintext) => nip44Encrypt(_conversationKey, plaintext);

  String decrypt(String ciphertext) =>
      nip44Decrypt(_conversationKey, ciphertext);
}

/// Creates author-private kind-30300 reminders on the relay.
class ReminderService {
  final SignedEventRelay _signedEventRelay;
  final ReminderCrypto _crypto;
  final _createdAtById = <String, int>{};

  ReminderService({
    required SignedEventRelay signedEventRelay,
    required ReminderCrypto crypto,
  }) : _signedEventRelay = signedEventRelay,
       _crypto = crypto;

  /// Encrypt, sign, and publish a new pending reminder. [notBefore] is a Unix
  /// timestamp in seconds after which clients surface the reminder.
  Future<void> createReminder({
    ReminderTarget? target,
    int? notBefore,
    String? note,
    String status = 'pending',
    String? dTag,
    int? previousCreatedAt,
  }) async {
    final id = dTag ?? randomReminderDTag();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var createdAt = now;
    for (final previous in [previousCreatedAt, _createdAtById[id]]) {
      if (previous != null && previous >= createdAt) createdAt = previous + 1;
    }
    _createdAtById[id] = createdAt;
    final plaintext = buildReminderPlaintext(
      target: target,
      note: note,
      status: status,
    );
    final ciphertext = _crypto.encrypt(plaintext);
    await _signedEventRelay.submit(
      kind: EventKind.eventReminder,
      content: ciphertext,
      tags: buildReminderTags(
        dTag: id,
        notBefore: status == 'pending' ? notBefore : null,
      ),
      createdAt: createdAt,
    );
  }
}

/// Provides a [ReminderService], or null when no signing identity is
/// available (signed out).
final reminderServiceProvider = Provider<ReminderService?>((ref) {
  final relayConfig = ref.watch(relayConfigProvider);
  final pubkey = ref.watch(myPubkeyProvider);

  final nsec = relayConfig.nsec?.trim();
  if (nsec == null || nsec.isEmpty || pubkey == null || pubkey.isEmpty) {
    return null;
  }

  final ReminderCrypto crypto;
  try {
    crypto = ReminderCrypto(nsec, pubkey);
  } catch (_) {
    return null;
  }

  return ReminderService(
    signedEventRelay: SignedEventRelay(
      session: ref.read(relaySessionProvider.notifier),
      nsec: nsec,
    ),
    crypto: crypto,
  );
});
