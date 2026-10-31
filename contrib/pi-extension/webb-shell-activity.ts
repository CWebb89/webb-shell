// webb-shell-activity — publishes this pi session's live state for the desktop
// shell. The shell's PiActivity service watches the JSON and renders a bar
// module plus a completion toast; nothing here talks to the shell directly, so
// a shell restart never disturbs a running session.
//
// TUI sessions only: headless runs (--print, --mode json, --mode rpc) would
// overwrite the state of the visible session, and the shell's own Quick Ask
// popup runs `pi --print`.
import { mkdirSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const SCHEMA = 1;

type Phase = "idle" | "thinking" | "tool";

interface Activity {
  schema: number;
  pid: number;
  mode: string;
  sessionId: string;
  sessionName: string;
  sessionFile: string;
  cwd: string;
  model: string;
  busy: boolean;
  phase: Phase;
  tool: string;
  turns: number;
  runTokens: number;
  runCost: number;
  runMs: number;
  startedAt: number | null;
  settledAt: number | null;
  lastSummary: string;
  updatedAt: number;
}

function statePath(): string {
  const base = process.env.XDG_STATE_HOME || join(homedir(), ".local", "state");
  return join(base, "webb-shell", "pi-activity.json");
}

function modelLabel(ctx: ExtensionContext): string {
  const model = ctx.model as { id?: string; name?: string } | undefined;
  return String(model?.id ?? model?.name ?? "");
}

function summaryOf(message: unknown): string {
  const content = (message as { content?: unknown })?.content;
  if (!Array.isArray(content)) return "";
  for (let i = content.length - 1; i >= 0; i--) {
    const block = content[i] as { type?: string; text?: string };
    if (block?.type === "text" && typeof block.text === "string" && block.text.trim() !== "") {
      return block.text.replace(/\s+/g, " ").trim().slice(0, 180);
    }
  }
  return "";
}

function usageOf(message: unknown): { tokens: number; cost: number } {
  const usage = (message as { usage?: { totalTokens?: number; cost?: { total?: number } } })?.usage;
  return {
    tokens: Number(usage?.totalTokens ?? 0),
    cost: Number(usage?.cost?.total ?? 0),
  };
}

export default function (pi: ExtensionAPI) {
  let state: Activity | null = null;
  let startedAt = 0;

  function publish(patch: Partial<Activity> = {}) {
    if (!state) return;
    state = { ...state, ...patch, updatedAt: Date.now() };
    const path = statePath();
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(`${path}.tmp`, `${JSON.stringify(state)}\n`);
    renameSync(`${path}.tmp`, path);
  }

  function track(ctx: ExtensionContext, patch: Partial<Activity> = {}) {
    if (ctx.mode !== "tui") return;
    state = {
      schema: SCHEMA,
      pid: process.pid,
      mode: ctx.mode,
      sessionId: ctx.sessionManager.getSessionId(),
      sessionName: ctx.sessionManager.getSessionName?.() ?? "",
      sessionFile: ctx.sessionManager.getSessionFile() ?? "",
      cwd: ctx.cwd,
      model: modelLabel(ctx),
      busy: !ctx.isIdle(),
      phase: ctx.isIdle() ? "idle" : "thinking",
      tool: "",
      turns: 0,
      runTokens: 0,
      runCost: 0,
      runMs: 0,
      startedAt: null,
      settledAt: null,
      lastSummary: "",
      updatedAt: Date.now(),
      ...patch,
    };
    publish();
  }

  pi.on("session_start", (_event, ctx) => {
    track(ctx);
  });

  pi.on("agent_start", (_event, ctx) => {
    if (ctx.mode !== "tui") return;
    startedAt = Date.now();
    if (!state) {
      track(ctx);
      return;
    }
    publish({
      sessionId: ctx.sessionManager.getSessionId(),
      sessionFile: ctx.sessionManager.getSessionFile() ?? "",
      model: modelLabel(ctx),
      busy: true,
      phase: "thinking",
      tool: "",
      turns: 0,
      runTokens: 0,
      runCost: 0,
      runMs: 0,
      startedAt,
      settledAt: null,
      lastSummary: "",
    });
  });

  pi.on("turn_start", () => {
    if (!state) return;
    publish({ turns: state.turns + 1, phase: "thinking", tool: "" });
  });

  pi.on("tool_execution_start", (event) => {
    if (!state) return;
    publish({ phase: "tool", tool: String(event.toolName ?? "") });
  });

  pi.on("tool_execution_end", () => {
    if (!state) return;
    publish({ phase: "thinking", tool: "" });
  });

  pi.on("message_end", (event) => {
    if (!state) return;
    const message = event.message as { role?: string } | undefined;
    if (message?.role !== "assistant") return;
    const { tokens, cost } = usageOf(message);
    publish({
      runTokens: state.runTokens + tokens,
      runCost: state.runCost + cost,
      lastSummary: summaryOf(message) || state.lastSummary,
    });
  });

  pi.on("agent_settled", (_event, ctx) => {
    if (!state || ctx.isIdle() !== true) return;
    const finished = Date.now();
    publish({
      busy: false,
      phase: "idle",
      tool: "",
      settledAt: finished,
      runMs: startedAt > 0 ? finished - startedAt : 0,
    });
  });

  pi.on("session_shutdown", () => {
    if (!state) return;
    try {
      rmSync(statePath(), { force: true });
    } catch {
      state = null;
      return;
    }
    state = null;
  });
}
