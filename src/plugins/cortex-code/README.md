# Sentry for Cortex Code

The Sentry plugin for [Cortex Code](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code) (CoCo). It teaches CoCo how to use Sentry: SDK setup wizards for any platform, production issue debugging via the Sentry MCP server, code review with Sentry context, and monitoring configuration.

> [!IMPORTANT]
> This repository is generated. It is built from
> [getsentry/sentry-for-ai](https://github.com/getsentry/sentry-for-ai) and
> includes every skill in that library. Do not edit files here; make changes in
> that repository and they will be rebuilt into this one.

## Install

From your terminal:

```bash
cortex plugin install getsentry/plugin-cortex-code
```

## What's included

- The full Sentry skill library (SDK setup wizards, debugging and code-review
  workflows, feature setup).
- The hosted Sentry MCP server for querying your Sentry environment.
- `SKILL_TREE.md` routing index so the entry-point skill (`sentry-get-started`)
  can orient the user and hand off to the right specialist skill.
