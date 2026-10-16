import * as React from "react";
import { toast } from "sonner";

import { useUsersBatchQuery } from "@/features/profile/hooks";
import { resolveUserLabel } from "@/features/profile/lib/identity";
import { Button } from "@/shared/ui/button";
import { Markdown } from "@/shared/ui/markdown";
import { type CanvasVersion, canvasConflict } from "../lib/canvasDoc";
import { useChannelCanvasDoc } from "../useChannelCanvasDoc";
import { CanvasEditor } from "./CanvasEditor";

export function ChannelCanvasDocTab({
  channelId,
  canvasId,
  canEdit,
}: {
  channelId: string;
  canvasId: string;
  canEdit: boolean;
}) {
  const doc = useChannelCanvasDoc(channelId, canvasId);
  const [editing, setEditing] = React.useState(false);
  const [draft, setDraft] = React.useState("");
  const [base, setBase] = React.useState<string | null>(null);
  const [saving, setSaving] = React.useState(false);
  const latest = doc?.latest ?? null;
  const conflict: CanvasVersion | null = editing
    ? canvasConflict(base, latest)
    : null;
  const profiles = useUsersBatchQuery(conflict ? [conflict.author] : []).data
    ?.profiles;
  const conflictAuthor = conflict
    ? resolveUserLabel({ profiles, pubkey: conflict.author })
    : null;
  const start = () => {
    setDraft(latest?.content ?? "");
    setBase(latest?.eventId ?? null);
    setEditing(true);
  };
  const save = async (force: boolean) => {
    if (!doc) return;
    setSaving(true);
    try {
      const result = await doc.save(draft, base, force);
      if (result === "saved") setEditing(false);
    } catch (error) {
      console.error("Failed to save canvas", error);
      toast.error(
        error instanceof Error ? error.message : "Couldn't save the canvas",
      );
    } finally {
      setSaving(false);
    }
  };
  if (!doc) return null;
  if (editing) {
    return (
      <CanvasEditor
        conflictAuthor={conflictAuthor}
        draft={draft}
        onCancel={() => setEditing(false)}
        onDraftChange={setDraft}
        onOverwrite={() => void save(true)}
        onReload={() => {
          setDraft(latest?.content ?? "");
          setBase(latest?.eventId ?? null);
        }}
        onSave={() => void save(false)}
        saving={saving}
      />
    );
  }
  return (
    <div className="space-y-3" data-testid="canvas-view">
      {canEdit ? (
        <Button onClick={start} size="sm" type="button" variant="outline">
          Edit
        </Button>
      ) : null}
      {latest?.content ? (
        <Markdown content={latest.content} />
      ) : (
        <p className="text-sm text-muted-foreground">This canvas is empty.</p>
      )}
    </div>
  );
}
