#!/usr/bin/env python3
"""Generate semantic-convention attribute lookup files for skill references.

Source: https://getsentry.github.io/sentry-conventions/api/attributes.json
Writes stable-only domain files under src/references/semantics/.
Re-run when conventions change. Generated markdown is checked in on purpose.
"""

from __future__ import annotations

import json
import urllib.request
from collections import defaultdict
from pathlib import Path

SOURCE_URL = "https://getsentry.github.io/sentry-conventions/api/attributes.json"
REPO_ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = REPO_ROOT / "src" / "references" / "semantics"
SKILL_PATH = REPO_ROOT / "src" / "skills" / "sentry-instrument" / "SKILL.md"
TOC_START = "<!-- semantics-toc:start -->"
TOC_END = "<!-- semantics-toc:end -->"

# One-line domain intros shown at the top of each file. Keep these about the
# domain, not about how the file was generated.
DOMAIN_BLURBS: dict[str, str] = {
    "angular": "Attributes from Angular framework instrumentation.",
    "app": "Application identity and lifecycle attributes for mobile and desktop apps.",
    "art": "Android Runtime (ART) profiling and runtime attributes.",
    "aws": "AWS service, region, and request attributes for cloud instrumentation.",
    "browser": "Browser environment and web-vital attributes on client spans.",
    "cache": "Cache read/write attributes — key, hit/miss, item size.",
    "client": "Client address and port for the side that initiated a connection.",
    "cloud": "Generic cloud provider attributes shared across AWS, GCP, and others.",
    "cloudflare": "Cloudflare Workers, bindings, and edge platform attributes.",
    "code": "Source location attributes — function, file, line, namespace.",
    "culture": "Locale and cultural preference attributes.",
    "db": "Database query attributes — system, operation, statement summary, and collection.",
    "device": "Device hardware and form-factor attributes for mobile and desktop.",
    "error": "Error classification attributes attached to failures.",
    "event": "Event identity attributes for discrete application events.",
    "exception": "Exception type, message, and stack details on error spans.",
    "faas": "Function-as-a-service / serverless invocation attributes.",
    "file": "File path and I/O operation attributes.",
    "flag": "Feature-flag evaluation attributes.",
    "gcp": "Google Cloud Platform service and resource attributes.",
    "gen_ai": "LLM and agent attributes — model, tokens, cost, tools, and conversation id.",
    "general": "Uncategorized stable attributes that do not belong to a named domain.",
    "graphql": "GraphQL operation name, type, and document attributes.",
    "grpc": "gRPC method, status, and service attributes.",
    "http": "HTTP client and server attributes — method, route, status, timing, and headers.",
    "jsonrpc": "JSON-RPC method and request identity attributes.",
    "jvm": "JVM runtime and memory attributes.",
    "koa": "Koa framework middleware and request attributes.",
    "logger": "Logger name and logging-context attributes.",
    "mcp": "Model Context Protocol attributes for MCP client/server spans.",
    "mdc": "Mapped diagnostic context (MDC) attributes from logging frameworks.",
    "messaging": "Message queue / pubsub attributes — destination, operation, and message id.",
    "middleware": "Middleware layer name and ordering attributes.",
    "navigation": "Client-side navigation and route-change attributes.",
    "nel": "Network Error Logging (NEL) report attributes.",
    "network": "Network transport attributes — protocol, connection type, carrier.",
    "os": "Operating system name, version, and type attributes.",
    "otel": "OpenTelemetry bridge attributes carried into Sentry.",
    "params": "Request or route parameter attributes.",
    "process": "Process identity and runtime attributes (pid, executable, command).",
    "react": "React component and rendering attributes.",
    "remix": "Remix framework route and loader attributes.",
    "resource": "Browser resource-load attributes (script, css, image, etc.).",
    "rpc": "Generic RPC system attributes outside gRPC-specific keys.",
    "score": "Score and rating attributes (for example web-vital grades).",
    "sentry": "Sentry SDK and product attributes (sample rates, origins, mechanism).",
    "server": "Server address and port for the receiving side of a connection.",
    "service": "Service name and version attributes for the instrumented unit.",
    "session": "Session identity attributes for user sessions.",
    "state": "Application or request state attributes.",
    "thread": "Thread id and name attributes.",
    "timber": "Timber logging framework attributes.",
    "trpc": "tRPC procedure and path attributes.",
    "ui": "UI component and rendering attributes for client interfaces.",
    "url": "URL components — full, path, query, fragment, template.",
    "user": "End-user identity attributes (id, email, username, geo).",
    "user_agent": "User-agent string and parsed client attributes.",
    "vercel": "Vercel platform and deployment attributes.",
}


def fetch_attributes() -> list[dict]:
    with urllib.request.urlopen(SOURCE_URL, timeout=60) as resp:
        return json.load(resp)


def domain_blurb(cat: str) -> str:
    if cat in DOMAIN_BLURBS:
        return DOMAIN_BLURBS[cat]
    label = cat.replace("_", " ")
    return f"Stable `{cat}.*` attributes for {label} instrumentation."


def domain_title(cat: str) -> str:
    # Prefer readable titles for multi-word / known acronyms.
    special = {
        "gen_ai": "Gen AI",
        "user_agent": "User agent",
        "jsonrpc": "JSON-RPC",
        "grpc": "gRPC",
        "graphql": "GraphQL",
        "trpc": "tRPC",
        "mcp": "MCP",
        "jvm": "JVM",
        "aws": "AWS",
        "gcp": "GCP",
        "http": "HTTP",
        "db": "Database",
        "os": "OS",
        "ui": "UI",
        "faas": "FaaS",
        "otel": "OpenTelemetry",
        "nel": "NEL",
        "mdc": "MDC",
        "art": "ART",
    }
    if cat in special:
        return f"{special[cat]} attributes"
    return f"{cat.replace('_', ' ').capitalize()} attributes"


def main() -> None:
    attrs = fetch_attributes()
    stable = [a for a in attrs if not a.get("deprecated")]
    by_cat: dict[str, list[dict]] = defaultdict(list)
    for a in stable:
        cat = a.get("category") or "general"
        by_cat[cat].append(a)

    for cat in by_cat:
        by_cat[cat].sort(key=lambda a: a["key"])

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for old in OUT_DIR.glob("*.md"):
        old.unlink()

    unknown = sorted(set(by_cat) - set(DOMAIN_BLURBS))
    if unknown:
        print(f"warning: domains missing custom blurbs (using fallback): {', '.join(unknown)}")

    for cat, items in sorted(by_cat.items()):
        lines = [
            f"# {domain_title(cat)}",
            "",
            domain_blurb(cat),
            "",
            "| Key | Type | Brief |",
            "| --- | --- | --- |",
        ]
        for a in items:
            key = a["key"].replace("|", "\\|")
            typ = str(a.get("type", "")).replace("|", "\\|")
            brief = str(a.get("brief", "")).replace("|", "\\|").replace("\n", " ")
            lines.append(f"| `{key}` | `{typ}` | {brief} |")
        lines.append("")
        (OUT_DIR / f"{cat}.md").write_text("\n".join(lines), encoding="utf-8")

    skill = SKILL_PATH.read_text(encoding="utf-8")
    before, marker, tail = skill.partition(TOC_START)
    if not marker:
        raise RuntimeError(f"missing {TOC_START} in {SKILL_PATH}")
    _, marker, after = tail.partition(TOC_END)
    if not marker:
        raise RuntimeError(f"missing {TOC_END} in {SKILL_PATH}")
    links = "\n".join(
        f"- [`{cat}`](references/semantics/{cat}.md)" for cat in sorted(by_cat)
    )
    SKILL_PATH.write_text(
        f"{before}{TOC_START}\n{links}\n{TOC_END}{after}", encoding="utf-8"
    )

    print(
        f"wrote {len(by_cat)} domain files ({len(stable)} stable attrs) and refreshed "
        f"{SKILL_PATH.relative_to(REPO_ROOT)}"
    )


if __name__ == "__main__":
    main()
