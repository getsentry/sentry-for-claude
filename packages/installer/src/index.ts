import { readFileSync } from "node:fs";
import { join } from "node:path";
import { defineCommand, runMain } from "citty";
import { buildHarnesses } from "./harnesses";
import { captureAndFlush, initTelemetry } from "./instrument";
import { runInstaller, runRemover } from "./ui";

// Initialize telemetry before citty parses arguments so that any startup errors
// are captured. We pre-scan raw argv for --no-telemetry ourselves here because
// citty has not run yet. DO_NOT_TRACK=1 also disables telemetry.
const DO_NOT_TRACK_VALUES = new Set(["1", "true", "yes"]);

const telemetryEnabled =
  !DO_NOT_TRACK_VALUES.has((process.env.DO_NOT_TRACK ?? "").toLowerCase()) &&
  !process.argv.slice(2).includes("--no-telemetry");

initTelemetry(telemetryEnabled);

const { version, description } = JSON.parse(
  readFileSync(join(__dirname, "../package.json"), "utf8"),
) as { version: string; description: string };

// Both subcommands take the same agent-selection flags.
const agentSelectionArgs = {
  // citty turns `--no-interactive` into `interactive: false` via its built-in
  // boolean negation, so the flag is modeled as `interactive` (default true)
  // rather than a separate `no-interactive` arg.
  interactive: {
    type: "boolean",
    description: "Prompt to select agents; pass --no-interactive to act on every detected agent",
    default: true,
  },
  yes: {
    type: "boolean",
    alias: "y",
    description: "Alias for --no-interactive",
    default: false,
  },
  telemetry: {
    type: "boolean",
    description:
      "Send crash reports to Sentry (default: on). Pass --no-telemetry or set DO_NOT_TRACK=1 to disable.",
    default: true,
  },
} as const;

const install = defineCommand({
  meta: {
    name: "install",
    description: "Install the Sentry plugin into your detected AI coding assistants",
  },
  args: {
    instruction: {
      type: "positional",
      description: "Instruction to include in the prompt copied after installation",
      required: false,
    },
    ...agentSelectionArgs,
  },
  async run({ args }) {
    const interactive = args.interactive && !args.yes;
    try {
      const ok = await runInstaller(buildHarnesses(), {
        interactive,
        instruction: args.instruction,
      });
      process.exit(ok ? 0 : 1);
    } catch (err) {
      // Unexpected error outside the Listr runner: capture and flush before exit
      // so crashes during the command execution path are not silently dropped.
      await captureAndFlush(err);
      throw err;
    }
  },
});

const remove = defineCommand({
  meta: {
    name: "remove",
    description: "Remove the Sentry plugin from your detected AI coding assistants",
  },
  args: agentSelectionArgs,
  async run({ args }) {
    const interactive = args.interactive && !args.yes;
    try {
      const ok = await runRemover(buildHarnesses(), { interactive });
      process.exit(ok ? 0 : 1);
    } catch (err) {
      await captureAndFlush(err);
      throw err;
    }
  },
});

const main = defineCommand({
  meta: {
    name: "sentry-agent-plugin",
    version,
    description,
  },
  subCommands: {
    install,
    remove,
    // `uninstall` is an alias for `remove`; citty resolves subcommands by key,
    // so registering the same command under both names exposes both.
    uninstall: remove,
  },
});

const SUBCOMMANDS = new Set(["install", "remove", "uninstall"]);
const PASSTHROUGH = new Set(["--help", "-h", "--version"]);

// citty has no concept of a default subcommand, so `npx @sentry/agent-plugin` with no
// arguments would just print the help menu. Default to `install` instead unless
// the user gave an explicit subcommand or asked for help/version.
function withDefaultCommand(argv: string[]): string[] {
  const [first] = argv;
  if (first !== undefined && (SUBCOMMANDS.has(first) || PASSTHROUGH.has(first))) {
    return argv;
  }
  return ["install", ...argv];
}

runMain(main, { rawArgs: withDefaultCommand(process.argv.slice(2)) });
