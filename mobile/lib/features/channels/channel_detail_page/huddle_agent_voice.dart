part of '../channel_detail_page.dart';

class _HuddleAgentVoice extends HookConsumerWidget {
  const _HuddleAgentVoice({
    required this.parentChannelId,
    required this.ephemeralChannelId,
  });

  final String parentChannelId;
  final String ephemeralChannelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return const SizedBox.shrink();
    }

    final config = ref.watch(relayConfigProvider);
    final speech = useMemoized(
      () => HuddleSpeech(
        baseUrl: config.baseUrl,
        nsec: config.nsec,
        channelId: ephemeralChannelId,
      ),
      [config.baseUrl, config.nsec, ephemeralChannelId],
    );
    final voices = useMemoized(speech.voices, [speech]);
    final selected = useState<String?>(null);
    final voiceId = useState<String?>(null);
    final status = useState<String>('Add an agent to speak');
    final heardText = useState<String?>(null);
    final microphoneMode = useState<String?>(null);
    final agentSpeaking = useValueListenable(speech.agentSpeaking);
    final selecting = useRef(false);
    final selectedAt = useRef(0);
    final heard = useMemoized(() => <String>{});
    final parentMembers =
        ref.watch(channelMembersProvider(parentChannelId)).asData?.value ??
        const <ChannelMember>[];
    final agents = huddleAgentCandidates(
      members: parentMembers,
      profiles: ref.watch(userCacheProvider),
      directory:
          ref.watch(agentDirectoryProvider).asData?.value ??
          const <AgentDirectoryEntry>[],
      channelId: parentChannelId,
    );
    final eligiblePubkeys = {
      for (final entry in agents) entry.pubkey.toLowerCase(),
    };
    final childMembers =
        ref.watch(channelMembersProvider(ephemeralChannelId)).asData?.value ??
        const <ChannelMember>[];
    final bots = [
      for (final member in childMembers)
        if (member.isBot &&
            eligiblePubkeys.contains(member.pubkey.toLowerCase()))
          member.pubkey.toLowerCase(),
    ];

    Future<void> selectAgent(String pubkey) async {
      if (selecting.value ||
          !eligiblePubkeys.contains(pubkey) ||
          (bots.isNotEmpty && !bots.contains(pubkey))) {
        return;
      }
      selecting.value = true;
      status.value = 'Joining agent';
      try {
        final actions = ref.read(channelActionsProvider);
        if (!bots.contains(pubkey)) {
          await actions.addMembers(
            channelId: ephemeralChannelId,
            pubkeys: [pubkey],
            role: 'bot',
          );
        }
        if (!context.mounted) return;
        selectedAt.value = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        selected.value = pubkey;
        voiceId.value = ref
            .read(savedPrefsProvider)
            .getString('huddle.voice.$pubkey');
        await speech.start(
          agentName: agents
              .where((entry) => entry.pubkey.toLowerCase() == pubkey)
              .map((entry) => entry.displayName)
              .firstOrNull,
        );
        if (context.mounted) status.value = 'Listening on this device';
        final mode = await speech.microphoneMode();
        if (context.mounted) microphoneMode.value = mode;
      } catch (error) {
        if (context.mounted) {
          selected.value = null;
          status.value = error is PlatformException
              ? error.message ?? error.code
              : error.toString();
        }
      } finally {
        selecting.value = false;
      }
    }

    useEffect(() {
      if (bots.length == 1 && selected.value == null) {
        unawaited(
          Future.microtask(() async {
            if (context.mounted) await selectAgent(bots.first);
          }),
        );
      }
      return null;
    }, [bots.join(',')]);

    useEffect(() {
      if (selected.value == null) return null;
      final timer = Timer.periodic(const Duration(seconds: 2), (_) {
        unawaited(
          speech
              .microphoneMode()
              .then((mode) {
                if (context.mounted) microphoneMode.value = mode;
              })
              .catchError((Object _) {}),
        );
      });
      return timer.cancel;
    }, [speech, selected.value]);

    useEffect(() {
      return () {
        unawaited(
          speech.stop().catchError((Object error) {
            debugPrint('[HuddleSpeech] stop failed: $error');
          }),
        );
        speech.dispose();
      };
    }, [speech]);

    speech.onTranscript = (text) {
      if (!context.mounted) return;
      final agent = selected.value;
      if (agent == null) {
        status.value = 'Add an agent to speak';
        return;
      }
      if (ref.read(huddleSessionProvider).isMuted) {
        status.value = 'Microphone muted. Unmute to talk to the agent.';
        return;
      }
      status.value = 'Sending speech';
      heardText.value = text;
      unawaited(
        ref
            .read(sendMessageProvider)
            .call(
              channelId: ephemeralChannelId,
              content: text,
              mentionPubkeys: [agent],
            )
            .then((_) {
              if (context.mounted) status.value = 'Waiting for agent';
            })
            .catchError((Object error) {
              if (context.mounted) {
                status.value = 'Could not send speech: $error';
              }
            }),
      );
    };

    speech.onStatus = (message) {
      if (context.mounted) status.value = message;
    };

    speech.onError = (message) {
      if (context.mounted) status.value = message;
    };

    ref.listen(channelMessagesProvider(ephemeralChannelId), (previous, next) {
      final agent = selected.value;
      if (agent == null) return;
      for (final event in next.asData?.value ?? const <NostrEvent>[]) {
        if (event.pubkey.toLowerCase() != agent ||
            (event.kind != EventKind.streamMessage &&
                event.kind != EventKind.streamMessageEdit) ||
            event.getTagValue('voice') != 'final' ||
            event.createdAt < selectedAt.value ||
            !heard.add(
              event.kind == EventKind.streamMessageEdit
                  ? event.getTagValue('e') ?? event.id
                  : event.id,
            )) {
          continue;
        }
        unawaited(
          speech.speak(event.content, voiceId: voiceId.value).catchError((
            Object error,
          ) {
            if (context.mounted) status.value = 'Could not speak reply: $error';
          }),
        );
      }
    });

    final agent = selected.value;
    final selectedName = agents
        .where((entry) => entry.pubkey.toLowerCase() == agent)
        .map((entry) => entry.displayName ?? entry.pubkey.substring(0, 8))
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Grid.sm),
      child: Column(
        children: [
          if (agent == null && bots.isEmpty && agents.isEmpty)
            const Text('No agents in this channel')
          else if (agent == null && bots.isEmpty)
            PopupMenuButton<String>(
              tooltip: 'Add an agent to this Huddle',
              onSelected: (pubkey) => unawaited(selectAgent(pubkey)),
              itemBuilder: (_) => [
                for (final entry in agents)
                  PopupMenuItem(
                    value: entry.pubkey.toLowerCase(),
                    child: Text(
                      entry.displayName ?? entry.pubkey.substring(0, 8),
                    ),
                  ),
              ],
              child: const Text('Add agent'),
            )
          else if (agent == null)
            TextButton(
              onPressed: () => unawaited(selectAgent(bots.first)),
              child: const Text('Start agent speech'),
            )
          else
            Text(selectedName ?? 'Agent', style: context.textTheme.titleSmall),
          if (agent != null)
            FutureBuilder<List<HuddleVoice>>(
              future: voices,
              builder: (context, snapshot) => PopupMenuButton<String>(
                tooltip: 'Choose agent voice',
                enabled: snapshot.hasData && snapshot.data!.isNotEmpty,
                onSelected: (id) {
                  voiceId.value = id;
                  ref
                      .read(savedPrefsProvider)
                      .setString('huddle.voice.$agent', id);
                },
                itemBuilder: (_) => [
                  for (final voice in snapshot.data ?? const <HuddleVoice>[])
                    PopupMenuItem(value: voice.id, child: Text(voice.name)),
                ],
                child: Text(
                  snapshot.data
                          ?.where((voice) => voice.id == voiceId.value)
                          .firstOrNull
                          ?.name ??
                      'Choose voice',
                ),
              ),
            ),
          if (agent != null)
            TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => _HuddleAgentChat(
                  channelId: ephemeralChannelId,
                  agentPubkey: agent,
                  agentName: selectedName ?? 'Agent',
                ),
              ),
              child: const Text('Huddle chat'),
            ),
          if (agent != null && microphoneMode.value != null)
            TextButton(
              onPressed: () => unawaited(
                speech.showMicrophoneModes().catchError((Object _) {}),
              ),
              child: Text(switch (microphoneMode.value) {
                'voiceIsolation' => 'Mic mode: Voice Isolation',
                'wideSpectrum' =>
                  'Mic mode: Wide Spectrum. Use Voice Isolation',
                _ => 'Mic mode: Standard. Use Voice Isolation',
              }),
            ),
          if (agent != null && agentSpeaking)
            TextButton(
              onPressed: () => unawaited(
                speech.stopSpeaking().catchError((Object error) {
                  if (context.mounted) status.value = 'Could not stop: $error';
                }),
              ),
              child: const Text('Stop speaking'),
            ),
          Semantics(
            liveRegion: true,
            child: Text(status.value, style: context.textTheme.bodySmall),
          ),
          if (heardText.value != null)
            Text(
              'You: ${heardText.value}',
              style: context.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

List<AgentDirectoryEntry> huddleAgentCandidates({
  required List<ChannelMember> members,
  required Map<String, UserProfile> profiles,
  required List<AgentDirectoryEntry> directory,
  required String channelId,
}) {
  final directoryByPubkey = {
    for (final entry in directory) entry.pubkey.toLowerCase(): entry,
  };
  final agents = <AgentDirectoryEntry>[];
  for (final member in members) {
    final pubkey = member.pubkey.toLowerCase();
    final entry = directoryByPubkey[pubkey];
    if (!member.isBot && profiles[pubkey]?.isAgent != true && entry == null) {
      continue;
    }
    if (entry != null &&
        entry.channelIds.isNotEmpty &&
        !entry.channelIds.contains(channelId)) {
      continue;
    }
    agents.add(
      entry ??
          AgentDirectoryEntry(
            pubkey: pubkey,
            displayName: profiles[pubkey]?.displayName ?? member.displayName,
          ),
    );
  }
  return agents;
}

class _HuddleAgentChat extends HookConsumerWidget {
  const _HuddleAgentChat({
    required this.channelId,
    required this.agentPubkey,
    required this.agentName,
  });

  final String channelId;
  final String agentPubkey;
  final String agentName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final input = useTextEditingController();
    final sending = useState(false);
    final error = useState<String?>(null);
    final currentPubkey = ref.watch(
      huddleSessionProvider.select((session) => session.currentPubkey),
    );
    final messages = [
      for (final event
          in ref.watch(channelMessagesProvider(channelId)).asData?.value ??
              const <NostrEvent>[])
        if (event.kind == EventKind.streamMessage) event,
    ];

    Future<void> send() async {
      final text = input.text.trim();
      if (text.isEmpty || sending.value) return;
      sending.value = true;
      error.value = null;
      try {
        await ref
            .read(sendMessageProvider)
            .call(
              channelId: channelId,
              content: text,
              mentionPubkeys: [agentPubkey],
            );
        input.clear();
      } catch (failure) {
        error.value = 'Could not send message: $failure';
      } finally {
        sending.value = false;
      }
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Huddle chat', style: context.textTheme.titleLarge),
            ),
            Expanded(
              child: ListView.builder(
                reverse: true,
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final event = messages[messages.length - 1 - index];
                  final name = event.pubkey.toLowerCase() == agentPubkey
                      ? agentName
                      : event.pubkey.toLowerCase() ==
                            currentPubkey?.toLowerCase()
                      ? 'You'
                      : event.pubkey.substring(0, 8);
                  return ListTile(
                    title: Text(name),
                    subtitle: Text(event.content),
                  );
                },
              ),
            ),
            if (error.value != null) Text(error.value!),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: input,
                        decoration: InputDecoration(
                          hintText: 'Message $agentName',
                        ),
                        onSubmitted: (_) => unawaited(send()),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Send message',
                      onPressed: sending.value ? null : () => unawaited(send()),
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
