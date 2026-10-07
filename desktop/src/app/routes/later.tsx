import { createFileRoute } from "@tanstack/react-router";
import { LaterScreen } from "@/features/reminders/ui/LaterScreen";

export const Route = createFileRoute("/later")({ component: LaterScreen });
