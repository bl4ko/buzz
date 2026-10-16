import { Button } from "@/shared/ui/button";
import {
  APPROVE_EMOJI,
  approvalDecision,
  DENY_EMOJI,
} from "../lib/threadStatus";

export function ApprovalActions({
  reactions,
  disabled,
  onSelect,
  error,
}: {
  reactions: readonly { emoji: string; reactedByCurrentUser?: boolean }[];
  disabled: boolean;
  onSelect: (emoji: string) => void;
  error?: string | null;
}) {
  const decision = approvalDecision(reactions);
  if (decision) {
    return (
      <p
        className="mt-1.5 text-xs text-muted-foreground"
        data-testid="approval-decision"
      >
        {decision === "approve" ? "You approved" : "You denied"}
      </p>
    );
  }
  return (
    <div className="mt-1.5 flex gap-2" data-testid="approval-actions">
      <Button
        disabled={disabled}
        onClick={() => onSelect(APPROVE_EMOJI)}
        size="sm"
        type="button"
        variant="outline"
      >
        {APPROVE_EMOJI} Approve
      </Button>
      <Button
        disabled={disabled}
        onClick={() => onSelect(DENY_EMOJI)}
        size="sm"
        type="button"
        variant="outline"
      >
        {DENY_EMOJI} Deny
      </Button>
      {error ? (
        <span
          className="self-center text-xs text-destructive"
          data-testid="approval-error"
        >
          {error}
        </span>
      ) : null}
    </div>
  );
}
