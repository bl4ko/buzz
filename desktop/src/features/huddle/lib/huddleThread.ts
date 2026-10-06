export type HuddleBackendThreadState = {
  phase?: string;
  ephemeral_channel_id?: string | null;
  parent_channel_id?: string | null;
  huddle_thread_event_id?: string | null;
  thread_chat?: boolean;
  agent_pubkeys?: string[];
};

export type HuddleThread = {
  parentChannelId: string;
  rootEventId: string;
};

export type HuddleNotificationQuiet = {
  quietRootIds: ReadonlySet<string>;
  quietAuthorPubkeys: ReadonlySet<string>;
};

export const NO_HUDDLE_NOTIFICATION_QUIET: HuddleNotificationQuiet = {
  quietRootIds: new Set(),
  quietAuthorPubkeys: new Set(),
};

export type HuddleTtsScope = {
  channelId: string;
  threadRootId: string | null;
};

export function huddleThread(
  state: HuddleBackendThreadState | null | undefined,
): HuddleThread | null {
  if (
    !state?.thread_chat ||
    !state.parent_channel_id ||
    !state.huddle_thread_event_id
  ) {
    return null;
  }
  return {
    parentChannelId: state.parent_channel_id,
    rootEventId: state.huddle_thread_event_id,
  };
}

/** Where huddle chat is read: the parent thread, or the old backing channel. */
export function huddleChatDestination(
  state: HuddleBackendThreadState | null,
  fallbackChannelId: string | null,
): { channelId: string; threadRootId: string | null } | null {
  const thread = huddleThread(state);
  if (thread) {
    return {
      channelId: thread.parentChannelId,
      threadRootId: thread.rootEventId,
    };
  }
  const channelId = state?.ephemeral_channel_id ?? fallbackChannelId;
  return channelId ? { channelId, threadRootId: null } : null;
}

export function sameHuddleThreadState(
  left: HuddleBackendThreadState | null,
  right: HuddleBackendThreadState | null,
): boolean {
  return (
    left?.phase === right?.phase &&
    left?.ephemeral_channel_id === right?.ephemeral_channel_id &&
    left?.parent_channel_id === right?.parent_channel_id &&
    left?.huddle_thread_event_id === right?.huddle_thread_event_id &&
    left?.thread_chat === right?.thread_chat
  );
}

export function huddleTtsScope(
  state: HuddleBackendThreadState | null,
  localEphemeralChannelId: string | null,
): HuddleTtsScope | null {
  if (
    !localEphemeralChannelId ||
    state?.ephemeral_channel_id !== localEphemeralChannelId ||
    (state.phase !== "connected" && state.phase !== "active")
  ) {
    return null;
  }
  if (!state.thread_chat) {
    return { channelId: localEphemeralChannelId, threadRootId: null };
  }
  const thread = huddleThread(state);
  return thread
    ? { channelId: thread.parentChannelId, threadRootId: thread.rootEventId }
    : null;
}

export function parseHuddleStartContent(content: string): {
  ephemeralChannelId: string | null;
  threadChat: boolean;
} {
  try {
    const parsed = JSON.parse(content) as {
      ephemeral_channel_id?: unknown;
      chat?: unknown;
    };
    return {
      ephemeralChannelId:
        typeof parsed.ephemeral_channel_id === "string"
          ? parsed.ephemeral_channel_id
          : null,
      threadChat: parsed.chat === "thread",
    };
  } catch {
    return { ephemeralChannelId: null, threadChat: false };
  }
}

/** Silence the live huddle thread except for direct human mentions. */
export function huddleNotificationQuiet(
  state: HuddleBackendThreadState | null,
): HuddleNotificationQuiet {
  const thread =
    state?.phase === "idle" || state?.phase === "leaving"
      ? null
      : huddleThread(state);
  if (!thread) return NO_HUDDLE_NOTIFICATION_QUIET;
  return {
    quietRootIds: new Set([thread.rootEventId]),
    quietAuthorPubkeys: new Set(
      (state?.agent_pubkeys ?? []).map((pubkey) => pubkey.toLowerCase()),
    ),
  };
}

export function sameHuddleNotificationQuiet(
  left: HuddleNotificationQuiet,
  right: HuddleNotificationQuiet,
): boolean {
  const key = (quiet: HuddleNotificationQuiet) =>
    `${[...quiet.quietRootIds].join(",")}|${[...quiet.quietAuthorPubkeys].sort().join(",")}`;
  return key(left) === key(right);
}
