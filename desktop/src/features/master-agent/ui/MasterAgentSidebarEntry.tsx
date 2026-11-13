import { ShieldCheck } from "lucide-react";

import type { ActiveChannelTurnSummary } from "@/features/agents/activeAgentTurnsStore";
import { usePendingOlympusProposalCount } from "@/features/agents/ui/OlympusProposalsPanel";
import {
  DEFAULT_HOVER_PROFILE_STATUS_GEOMETRY,
  ProfileAvatarWithStatus,
  scaleProfileAvatarStatusGeometry,
} from "@/features/profile/ui/ProfileAvatarWithStatus";
import { ChannelMenuButton } from "@/features/sidebar/ui/SidebarSection";
import { getPlatformKeysById } from "@/shared/lib/keyboard-shortcuts";
import {
  SidebarGroup,
  SidebarMenu,
  SidebarMenuBadge,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/shared/ui/sidebar";
import { useMasterAgent } from "../useMasterAgent";

const AVATAR_SIZE = 24;
const AVATAR_GEOMETRY = scaleProfileAvatarStatusGeometry(
  DEFAULT_HOVER_PROFILE_STATUS_GEOMETRY,
  AVATAR_SIZE,
);

export function MasterAgentSidebarEntry({
  activeWorkingByChannelId,
  isChannelView,
  mutedChannelIds,
  selectedChannelId,
  unreadChannelCounts,
  unreadChannelIds,
}: {
  activeWorkingByChannelId: ReadonlyMap<string, ActiveChannelTurnSummary>;
  isChannelView: boolean;
  mutedChannelIds?: ReadonlySet<string>;
  selectedChannelId: string | null;
  unreadChannelCounts: ReadonlyMap<string, number>;
  unreadChannelIds: ReadonlySet<string>;
}) {
  const master = useMasterAgent();
  const pending = usePendingOlympusProposalCount(master?.agent.pubkey ?? null);
  if (!master) return null;
  const { agent, ask } = master;
  const dm = agent.dmChannel;
  const isActive = Boolean(dm && isChannelView && selectedChannelId === dm.id);
  const hasUnread = Boolean(dm && unreadChannelIds.has(dm.id));
  const activeWorking = dm ? activeWorkingByChannelId.get(dm.id) : undefined;
  const open = () => void ask();

  return (
    <SidebarGroup className="py-0" data-testid="master-agent-entry">
      <SidebarMenu>
        <SidebarMenuItem className="group/menu-item">
          {dm ? (
            <ChannelMenuButton
              activeWorking={activeWorking}
              channel={dm}
              dmParticipants={[
                {
                  avatarUrl: agent.avatarUrl,
                  isAgent: true,
                  label: agent.label,
                  pubkey: agent.pubkey,
                },
              ]}
              hasUnread={hasUnread}
              isActive={isActive}
              isMuted={mutedChannelIds?.has(dm.id)}
              label={agent.label}
              onSelectChannel={open}
              presenceStatus={agent.presence}
            />
          ) : (
            <SidebarMenuButton
              className="data-[active=true]:font-normal"
              onClick={open}
              tooltip={agent.label}
              type="button"
            >
              <span className="relative flex h-6 w-6 shrink-0 items-center justify-center">
                <ProfileAvatarWithStatus
                  avatarClassName="bg-sidebar-accent/80 text-2xs text-sidebar-foreground shadow-none"
                  avatarUrl={agent.avatarUrl}
                  className="h-6 w-6"
                  geometry={AVATAR_GEOMETRY}
                  iconClassName="h-3.5 w-3.5"
                  label={agent.label}
                  shape="squircle"
                  size={AVATAR_SIZE}
                  status={agent.presence}
                />
              </span>
              <span className="min-w-0 flex-1 truncate opacity-80">
                {agent.label}
              </span>
            </SidebarMenuButton>
          )}
          {pending > 0 || (hasUnread && !isActive && dm) ? (
            <SidebarMenuBadge className="right-2 gap-1 px-0">
              {pending > 0 ? (
                <span
                  className="flex h-5 items-center gap-0.5 rounded-full bg-amber-500/20 px-1.5 text-2xs font-semibold text-amber-700 dark:text-amber-300"
                  data-testid="master-agent-pending"
                >
                  <ShieldCheck aria-hidden className="h-3 w-3" />
                  {Math.min(pending, 99)}
                  <span className="sr-only">
                    {pending === 1
                      ? " proposal waits for your approval"
                      : " proposals wait for your approval"}
                  </span>
                </span>
              ) : null}
              {hasUnread && !isActive && dm ? (
                <span
                  className="flex h-5 min-w-5 items-center justify-center rounded-full bg-primary px-1.5 text-2xs font-semibold text-primary-foreground"
                  data-testid="master-agent-unread"
                >
                  {Math.min(unreadChannelCounts.get(dm.id) ?? 1, 99)}
                </span>
              ) : null}
            </SidebarMenuBadge>
          ) : !activeWorking ? (
            <SidebarMenuBadge
              className="right-2 font-normal text-sidebar-foreground/45 opacity-0 transition-opacity group-hover/menu-item:opacity-100 group-data-[collapsible=icon]:hidden"
              data-testid="master-agent-shortcut"
            >
              {getPlatformKeysById("ask-master-agent")}
            </SidebarMenuBadge>
          ) : null}
        </SidebarMenuItem>
      </SidebarMenu>
    </SidebarGroup>
  );
}
