import { Button } from "@/shared/ui/button";
import { Textarea } from "@/shared/ui/textarea";
import { CANVAS_DOC_MAX_BYTES, canvasByteLength } from "../lib/canvasDoc";

export function CanvasEditor({
  draft,
  onDraftChange,
  conflictAuthor,
  saving,
  onSave,
  onReload,
  onOverwrite,
  onCancel,
}: {
  draft: string;
  onDraftChange: (value: string) => void;
  conflictAuthor: string | null;
  saving: boolean;
  onSave: () => void;
  onReload: () => void;
  onOverwrite: () => void;
  onCancel: () => void;
}) {
  const bytes = canvasByteLength(draft);
  const tooLarge = bytes > CANVAS_DOC_MAX_BYTES;
  return (
    <div className="space-y-2" data-testid="canvas-editor">
      {conflictAuthor ? (
        <div
          className="flex items-center gap-2 rounded-md border border-amber-500/50 bg-amber-500/10 px-3 py-2 text-sm"
          data-testid="canvas-conflict"
        >
          <span className="flex-1">
            Changed by {conflictAuthor}. Reload or overwrite?
          </span>
          <Button
            data-testid="canvas-reload"
            onClick={onReload}
            size="sm"
            type="button"
            variant="outline"
          >
            Reload
          </Button>
          <Button
            data-testid="canvas-overwrite"
            disabled={saving || tooLarge}
            onClick={onOverwrite}
            size="sm"
            type="button"
            variant="destructive"
          >
            Overwrite
          </Button>
        </div>
      ) : null}
      <Textarea
        className="min-h-[60vh] font-mono text-sm"
        onChange={(event) => onDraftChange(event.target.value)}
        value={draft}
      />
      <div className="flex items-center gap-2">
        <span
          className={
            tooLarge
              ? "text-xs text-destructive"
              : "text-xs text-muted-foreground"
          }
          data-testid="canvas-size"
        >
          {bytes} / {CANVAS_DOC_MAX_BYTES} bytes
        </span>
        <span className="flex-1" />
        <Button onClick={onCancel} size="sm" type="button" variant="ghost">
          Cancel
        </Button>
        <Button
          data-testid="canvas-save"
          disabled={saving || tooLarge || conflictAuthor !== null}
          onClick={onSave}
          size="sm"
          type="button"
        >
          Save
        </Button>
      </div>
    </div>
  );
}
