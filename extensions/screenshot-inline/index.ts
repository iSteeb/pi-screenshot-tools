import { access, readFile } from "node:fs/promises";
import { constants } from "node:fs";
import { join } from "node:path";
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { type ExtensionAPI, getAgentDir } from "@mariozechner/pi-coding-agent";
import { Container, Image, Text } from "@mariozechner/pi-tui";
import { Type, type Static } from "@sinclair/typebox";

const execFileAsync = promisify(execFile);

const MODES = [
  "full",
  "region",
  "active-window",
  "window",
  "window-id",
  "output",
  "workspace",
  "list-windows",
  "list-outputs",
  "list-workspaces",
] as const;

type Mode = (typeof MODES)[number];

const TOOL_PARAMS = Type.Object({
  mode: Type.String({
    description: `Screenshot mode: ${MODES.join(", ")}`,
  }),
  query: Type.Optional(
    Type.String({
      description:
        'Required for mode="window", mode="window-id", mode="output", and mode="workspace" (unless workspace uses "current").',
    }),
  ),
});

type ToolParams = Static<typeof TOOL_PARAMS>;

type CaptureSuccess = {
  ok: true;
  backend?: string;
  mode?: string;
  path?: string;
  image?: { width?: number; height?: number; bytes?: number };
  geometry?: Record<string, unknown>;
  match?: Record<string, unknown>;
  [key: string]: unknown;
};

type CaptureFailure = {
  ok: false;
  backend?: string;
  mode?: string;
  error?: string;
  details?: Record<string, unknown>;
  [key: string]: unknown;
};

type CaptureResult = CaptureSuccess | CaptureFailure;

type CaptureExecution = {
  result: CaptureResult;
  imageBase64?: string;
};

type ScreenshotMessageDetails = {
  result: CaptureResult;
  imageBase64?: string;
};

function showWithKittenIcat(path: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn("kitten", ["icat", "--stdin=no", path], {
      stdio: ["ignore", "inherit", "inherit"],
      env: process.env,
      detached: true,
    });
    child.on("error", reject);
    child.unref();
    resolve();
  });
}

function getCaptureScriptCandidates(): string[] {
  return [
    join(__dirname, "..", "..", "skills", "screenshot-tools", "capture.sh"),
    join(getAgentDir(), "skills", "screenshot-tools", "capture.sh"),
  ];
}

async function ensureCaptureScript(): Promise<string> {
  const candidates = getCaptureScriptCandidates();
  for (const scriptPath of candidates) {
    try {
      await access(scriptPath, constants.X_OK);
      return scriptPath;
    } catch {
      // try next candidate
    }
  }
  throw new Error(`Could not find executable capture.sh. Tried: ${candidates.join(", ")}`);
}

function buildArgs(params: ToolParams): string[] {
  if (!MODES.includes(params.mode as Mode)) {
    throw new Error(`Unsupported mode: ${params.mode}. Supported: ${MODES.join(", ")}`);
  }

  const args: string[] = [params.mode];

  if ((params.mode === "window" || params.mode === "window-id" || params.mode === "output") && !params.query) {
    throw new Error(`mode=${params.mode} requires query`);
  }
  if (params.mode === "workspace") {
    args.push(params.query?.trim() || "current");
    return args;
  }
  if ((params.mode === "window" || params.mode === "window-id" || params.mode === "output") && params.query) {
    args.push(params.query);
  }
  return args;
}

function parseCaptureResult(stdout: string, stderr: string): CaptureResult {
  const text = stdout.trim() || stderr.trim();
  if (!text) throw new Error("Screenshot tool produced no output.");
  try {
    return JSON.parse(text) as CaptureResult;
  } catch {
    throw new Error(`Screenshot tool did not return valid JSON. Output:\n${text}`);
  }
}

function summarizeSuccess(result: CaptureSuccess): string {
  const mode = result.mode || "";

  if (mode === "list-windows") {
    const windows = Array.isArray(result.windows) ? result.windows : [];
    const lines = windows.map((window, index) => {
      const entry = window as {
        title?: string;
        app_id?: string;
        id?: number | string;
        address?: string;
        focused?: boolean;
        visible?: boolean;
        workspace?: string;
        monitor?: string;
      };
      const label = entry.title || entry.app_id || "(unnamed window)";
      const idPart = entry.id !== undefined ? ` (id=${entry.id})` : entry.address ? ` (id=${entry.address})` : "";
      const visibilityPart = entry.visible === false ? " [hidden]" : entry.visible === true ? " [visible]" : "";
      const locationPart = entry.workspace ? ` [workspace=${entry.workspace}]` : entry.monitor ? ` [monitor=${entry.monitor}]` : "";
      return `${index + 1}. ${label}${entry.app_id ? ` [${entry.app_id}]` : ""}${entry.focused ? " [focused]" : ""}${visibilityPart}${locationPart}${idPart}`;
    });
    return [`Listed ${windows.length} window(s).`, result.backend ? `Backend: ${result.backend}.` : "", ...lines].filter(Boolean).join("\n");
  }

  if (mode === "list-outputs") {
    const outputs = Array.isArray(result.outputs) ? result.outputs : [];
    const lines = outputs.map((output, index) => {
      const entry = output as { name?: string; focused?: boolean; active?: boolean };
      return `${index + 1}. ${entry.name || "(unnamed output)"}${entry.focused ? " [focused]" : ""}${entry.active ? " [active]" : ""}`;
    });
    return [`Listed ${outputs.length} output(s).`, result.backend ? `Backend: ${result.backend}.` : "", ...lines].filter(Boolean).join("\n");
  }

  if (mode === "list-workspaces") {
    const workspaces = Array.isArray(result.workspaces) ? result.workspaces : [];
    const lines = workspaces.map((workspace, index) => {
      const entry = workspace as { name?: string; focused?: boolean; visible?: boolean };
      return `${index + 1}. ${entry.name || "(unnamed workspace)"}${entry.focused ? " [focused]" : ""}${entry.visible ? " [visible]" : ""}`;
    });
    return [`Listed ${workspaces.length} workspace(s).`, result.backend ? `Backend: ${result.backend}.` : "", ...lines].filter(Boolean).join("\n");
  }

  const parts: string[] = ["Captured screenshot successfully."];
  if (result.backend) parts.push(`Backend: ${result.backend}.`);
  if (result.path) parts.push(`Path: ${result.path}.`);
  if (result.image?.width && result.image?.height) {
    parts.push(`Size: ${result.image.width}×${result.image.height}.`);
  }
  if (result.match && typeof result.match === "object") {
    const title = typeof result.match.title === "string" ? result.match.title : undefined;
    const appId = typeof result.match.app_id === "string" ? result.match.app_id : undefined;
    if (title || appId) parts.push(`Matched: ${title || appId}${title && appId ? ` (${appId})` : ""}.`);
  }
  if (result.workspace_visit === true) {
    parts.push("Visited target workspace for capture.");
  }
  return parts.join(" ");
}

function summarizeFailure(result: CaptureFailure): string {
  const parts: string[] = [result.error || "Screenshot capture failed."];
  if (result.backend) parts.push(`Backend: ${result.backend}.`);
  if (result.details?.matches && Array.isArray(result.details.matches)) {
    parts.push(`Candidates: ${result.details.matches.join(" | ")}`);
  }
  if (result.details?.capture_method && typeof result.details.capture_method === "string") {
    parts.push(`Capture method: ${result.details.capture_method}.`);
  }
  return parts.join(" ");
}

function formatResultText(result: CaptureResult): string {
  return result.ok ? summarizeSuccess(result) : summarizeFailure(result);
}

async function runCapture(params: ToolParams, signal?: AbortSignal, onUpdate?: (update: { content?: Array<{ type: "text"; text: string }>; details?: Record<string, unknown> }) => void): Promise<CaptureExecution> {
  const scriptPath = await ensureCaptureScript();
  const args = buildArgs(params);

  onUpdate?.({
    content: [{ type: "text", text: `Capturing screenshot: ${args.join(" ")}` }],
    details: { scriptPath, args },
  });

  let stdout = "";
  let stderr = "";
  try {
    const execResult = await execFileAsync(scriptPath, args, {
      signal,
      maxBuffer: 10 * 1024 * 1024,
    });
    stdout = execResult.stdout;
    stderr = execResult.stderr;
  } catch (error) {
    const execError = error as { stdout?: string; stderr?: string; message?: string };
    stdout = execError.stdout || "";
    stderr = execError.stderr || execError.message || "";
  }

  const result = parseCaptureResult(stdout, stderr);
  const imageBase64 = result.ok && result.path ? (await readFile(result.path)).toString("base64") : undefined;
  return { result, imageBase64 };
}

function parseCommandArgs(args: string): ToolParams {
  const trimmed = args.trim();
  if (!trimmed) {
    return { mode: "active-window" };
  }

  const [modeToken, ...rest] = trimmed.split(/\s+/);
  const mode = modeToken as ToolParams["mode"];
  const query = rest.join(" ").trim() || undefined;
  return { mode, query };
}

export default function screenshotInline(pi: ExtensionAPI) {
  pi.registerTool({
    name: "capture_screenshot",
    label: "Capture screenshot",
    description:
      "Capture desktop screenshots via the screenshot-tools skill. Returns PNG images inline in supported terminals like Kitty.",
    promptSnippet:
      "Capture screenshots (window, workspace, output, full screen, region) and return the PNG inline when available.",
    promptGuidelines: [
      'Use this tool when the user asks to take, inspect, or show a screenshot.',
      'Use mode="active-window" for the current/focused window.',
      'Use mode="window" with query for a named app/window, mode="window-id" with query for an exact listed window id, mode="output" for a monitor, and mode="workspace" for a workspace.',
      'Use list-windows, list-outputs, or list-workspaces first if the target is ambiguous.',
    ],
    parameters: TOOL_PARAMS,
    async execute(_toolCallId, params: ToolParams, signal, onUpdate) {
      const { result, imageBase64 } = await runCapture(params, signal, onUpdate);

      if (!result.ok) {
        return {
          content: [{ type: "text", text: summarizeFailure(result) }],
          details: {
            result,
            imageBase64,
          } satisfies ScreenshotMessageDetails,
          isError: true,
        };
      }

      const content: Array<{ type: "text"; text: string } | { type: "image"; data: string; mimeType: string }> = [
        { type: "text", text: summarizeSuccess(result) },
      ];

      if (imageBase64) {
        content.push({
          type: "image",
          data: imageBase64,
          mimeType: "image/png",
        });
      }

      return {
        content,
        details: {
          result,
          imageBase64,
        } satisfies ScreenshotMessageDetails,
      };
    },
    renderResult(result, { isPartial }, theme) {
      if (isPartial) {
        return new Text(theme.fg("warning", "Working..."), 0, 0);
      }

      const details = (result.details || {}) as ScreenshotMessageDetails;
      const container = new Container();
      const captureResult = details.result;
      const contentImage = result.content.find(
        (item): item is { type: "image"; data: string; mimeType: string } => item.type === "image",
      );
      const imageBase64 = details.imageBase64 || contentImage?.data;
      const imageMimeType = contentImage?.mimeType || "image/png";

      if (!captureResult) {
        return new Text(theme.fg("error", `Missing screenshot result details.${imageBase64 ? " Image data exists." : ""}`), 0, 0);
      }

      const headline = captureResult.ok
        ? theme.fg("success", captureResult.mode?.startsWith("list-") ? "Screenshot listing" : "Screenshot captured")
        : theme.fg("error", "Screenshot failed");
      container.addChild(new Text(`${headline}\n${formatResultText(captureResult)}`, 0, 0));
      if (imageBase64) {
        container.addChild(new Image(imageBase64, imageMimeType, theme, { maxWidthCells: 120, maxHeightCells: 36 }));
      }
      return container;
    },
  });

  pi.registerMessageRenderer("screenshot-capture", (message, _options, theme) => {
    const details = (message.details || {}) as ScreenshotMessageDetails;
    const container = new Container();
    const headline = details.result?.ok
      ? theme.fg("success", details.result.mode?.startsWith("list-") ? "Screenshot listing" : "Screenshot captured")
      : theme.fg("error", "Screenshot failed");
    container.addChild(new Text(`${headline}\n${formatResultText(details.result)}`, 0, 0));
    if (details.imageBase64) {
      container.addChild(new Image(details.imageBase64, "image/png", theme, { maxWidthCells: 120, maxHeightCells: 36 }));
    }
    return container;
  });

  pi.registerCommand("screenshot", {
    description:
      "Capture a screenshot directly. Usage: /screenshot [active-window|full|region|workspace [name]|window <query>|window-id <id>|output <name>|list-windows|list-outputs|list-workspaces]",
    handler: async (args, ctx) => {
      const params = parseCommandArgs(args);
      const { result, imageBase64 } = await runCapture(params, undefined, (update) => {
        const text = update.content?.[0]?.text;
        if (text) ctx.ui.notify(text, "info");
      });

      const isListingMode = result.ok && typeof result.mode === "string" && result.mode.startsWith("list-");
      if (Boolean(process.env.TMUX) && result.ok && !isListingMode) {
        ctx.ui.notify("In tmux, if inline rendering does not appear, use /screenshot-icat.", "info");
      }

      pi.sendMessage({
        customType: "screenshot-capture",
        content: formatResultText(result),
        display: true,
        details: {
          result,
          imageBase64,
        } satisfies ScreenshotMessageDetails,
      });
    },
  });

  pi.registerCommand("screenshot-debug", {
    description:
      "Debug image rendering paths. Usage: /screenshot-debug [message|overlay] [capture args]. Default: message active-window",
    handler: async (args, ctx) => {
      const trimmed = args.trim();
      const parts = trimmed ? trimmed.split(/\s+/) : [];
      const debugMode = parts[0] === "overlay" || parts[0] === "message" ? parts.shift()! : "message";
      const params = parseCommandArgs(parts.join(" "));
      const { result, imageBase64 } = await runCapture(params, undefined, (update) => {
        const text = update.content?.[0]?.text;
        if (text) ctx.ui.notify(`[debug:${debugMode}] ${text}`, "info");
      });

      if (debugMode === "message") {
        pi.sendMessage({
          customType: "screenshot-capture",
          content: `[debug:message] ${formatResultText(result)}`,
          display: true,
          details: {
            result,
            imageBase64,
          } satisfies ScreenshotMessageDetails,
        });
        return;
      }

      await ctx.ui.custom<void>((_tui, theme, _kb, done) => {
        const container = new Container();
        const title = result.ok ? theme.fg("accent", "Screenshot debug overlay") : theme.fg("error", "Screenshot debug overlay (failed)");
        container.addChild(new Text(`${title}\n${formatResultText(result)}\n\nPress Esc or Enter to close.`, 0, 0));
        if (imageBase64) {
          container.addChild(new Image(imageBase64, "image/png", theme, { maxWidthCells: 120, maxHeightCells: 36 }));
        }
        return {
          render: (w) => container.render(w),
          invalidate: () => container.invalidate(),
          handleInput: (data) => {
            if (data === "\r" || data === "\n" || data === "\x1b") done(undefined);
          },
        };
      }, { overlay: true });
    },
  });

  pi.registerCommand("screenshot-icat", {
    description:
      "Capture a screenshot and display it with kitten icat. Useful as a tmux fallback. Usage: /screenshot-icat [active-window|full|region|workspace [name]|window <query>|window-id <id>|output <name>]",
    handler: async (args, ctx) => {
      const params = parseCommandArgs(args);
      const { result } = await runCapture(params, undefined, (update) => {
        const text = update.content?.[0]?.text;
        if (text) ctx.ui.notify(text, "info");
      });

      if (!result.ok) {
        pi.sendMessage({
          customType: "screenshot-capture",
          content: formatResultText(result),
          display: true,
          details: { result } satisfies ScreenshotMessageDetails,
        });
        return;
      }

      if (!result.path) {
        ctx.ui.notify("No screenshot path returned.", "error");
        return;
      }

      try {
        await showWithKittenIcat(result.path);
        ctx.ui.notify(`Displayed via kitten icat: ${result.path}. If pi's prompt looks stuck, press Esc to force a redraw.`, "success");
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        ctx.ui.notify(`kitten icat failed: ${message}`, "error");
      }
    },
  });
}
