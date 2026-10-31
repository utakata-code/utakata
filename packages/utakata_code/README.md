# utakata

**utakata** is a Dart CLI tool by **[utakata code](https://github.com/utakata-code)**, designed for **client, developer, and AI agent** collaboration on Flutter apps through **specification-driven development**.

> 日本語のドキュメントは [README_ja.md](README_ja.md) を参照してください。

[![pub.dev](https://img.shields.io/pub/v/utakata.svg)](https://pub.dev/packages/utakata)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

---

## Features

- 🤖 **Claude Code Native**: `create` generates `.mcp.json` + `.claude/` (hooks, skills, an agent) + a project `CLAUDE.md`. `utakata mcp` exposes a read-only, stateless MCP server so an agent can inspect structure/plan/logs/agreements/config without writing to them. How much an agent may write back to `doc/records/` is a three-way choice (`records.agent_write: none | append | full`).
- 🧭 **Master config (`utakata.yaml`)**: one file declares the architecture, the `team` (client / developer / AI agents and who decides what), the `skills` to sync into `.claude/skills/`, and an optional remote `knowledge_repo` — pinned by commit SHA in `utakata.lock` via `utakata arch get`. Without it, everything ships bundled and fully offline.
- 🏗️ **Multi-Architecture Support**: Ships with **Clean Architecture (4-layer)** and **MVVM (3-layer)**. Customize by ejecting a definition with `utakata arch eject <id>`.
- 🔍 **One Structural Check**: `utakata check` reports missing files, unexpected files, and naming violations in a single pass against your `arch_definition.yaml` — with GUIDE excerpts inline so the fix is obvious.
- 📋 **Intent-Level Plan**: Declare features (name, permission, entities) in `doc/specs/plan.yaml`; `utakata apply` scaffolds exactly what's missing — layer directories *and* the required files as empty stubs, so file existence is plan-controlled too. `utakata plan adopt` detects code that isn't in the plan yet and appends it, format-preserving.
- 🔗 **Deterministic Import Audit**: `utakata imports` verifies dependency *direction*, not just file placement — a layer dependency graph declared in `arch_definition.yaml` (`import_rules`), and external packages constrained by *placement declarations* (version + allowed layers in one `dependencies/core_stack.yaml`; undeclared packages are not judged).
- 🎚️ **Per-Layer Granularity**: A feature doesn't have to mean *every* layer. Declare only the layers you need (`layers:`), mark one as not applicable with an empty list, and pin exact files even where naming is free-form. `utakata plan expand` writes the auto-derived baseline into the plan so you can edit it.
- 📚 **Knowledge stays out of your repo — and out of the package**: guides live in [utakata_arch_lib](https://github.com/utakata-code/utakata_arch_lib) and are fetched on demand (version-pinned, cached in `~/.utakata/`). The package bundles only the machine-readable definitions, so `create`/`apply`/`check` work fully offline; projects contain only the app + `doc/` + config — no copied guide tree, and `apply` no longer writes per-directory GUIDE.md files (use `guide for <file>`).
- 🗂️ **Client-Facing Knowledge Vault**: point `vault:` at your own repo of how-to-obtain-an-account / pricing / review-requirement notes, and the generated `utakata-client-explainer` skill writes client explanations from it — checking each entry's recorded verification date instead of quoting prices from memory.
- 💬 **Client Conversation Tracking**: `utakata log` records summarized conversations, `utakata message` keeps the **verbatim** correspondence you sent and received (unmodified, append-only), and `utakata agree` tracks agreements. All JSONL and append-only; how much an agent may add is set by `records.agent_write` (`append` lets it add entries via the CLI without ever editing past records).
- 📝 **Implementation Plans & Summary**: `utakata impl` tracks each feature's plan on **two axes** — implementation (`todo → in_progress → review → done`) and verification (`todo → in_progress → review → done`, or `not_required`) — and the plan file moves between lane directories (`doc/impl/2_in_progress/`, `4_test_todo/` …) as it advances, with a board regenerated at `doc/preview/impl_board.md`. Set `enforcement.impl_plan: on` to refuse scaffolding a feature that has no plan yet. `utakata summary` regenerates the agreement ledger section of your project summary.
- 🌐 **Internationalized**: CLI messages support English and Japanese.

---

## Installation

```sh
dart pub global activate utakata
```

Make sure `$HOME/.pub-cache/bin` is added to your `PATH`.

### Environment variables

| Variable | Purpose |
|---|---|
| `UTAKATA_FLUTTER` | The command line that starts flutter, as space-separated words. Takes precedence over everything below. Run directly without a shell: `Process.run(word1, [word2…, <flutter args>])`. Use it when the `flutter` script cannot be executed directly (e.g. no execute bit on Android): `UTAKATA_FLUTTER="/system/bin/sh /data/…/flutter/bin/flutter"` |
| `FLUTTER_PATH` | Full path to the `flutter` executable |
| `FLUTTER_ROOT` | Flutter SDK root (`{root}/bin/flutter` is used) |
| `UTAKATA_GIT` | The command line that starts git (same format as `UTAKATA_FLUTTER`). Only `arch get` / `vault get` use git |
| `UTAKATA_LANG` | CLI message language (`ja` / `en`; inferred from `LANG` when unset) |

flutter is looked up in the order `UTAKATA_FLUTTER` → `FLUTTER_PATH` → `FLUTTER_ROOT` → `PATH` (`which` / `where`). In `UTAKATA_FLUTTER` / `UTAKATA_GIT`, quote words that contain spaces with `'...'` or `"..."`, or escape a space with `\`; there is no variable expansion. Because `\` is an escape character, quote Windows paths with single quotes (`'C:\flutter\bin\flutter.bat'`). An unterminated quote is an error.

---

## Quick Start

```sh
# (Optional) Set up the doc/ workspace before the app exists yet (pre-contract phase)
utakata doc init

# Create a new Flutter project (also writes .mcp.json + .claude/)
utakata create my_app --org com.example

# Declare a feature in doc/specs/plan.yaml, then scaffold it
utakata apply --scope feature

# Check structure, naming, and required files in one pass
utakata check
```

`doc/specs/plan.yaml`:

```yaml
schema: 1
project:
  architecture: clean_architecture
features:
  - name: todo
    permission: user
    entities: [todo]
```

If you have an existing project using the older `AI/`-based layout, run `utakata doctor --migrate` to move it over (dry-run by default).

---

## Built-in Architectures

```sh
utakata arch list         # List all available architectures
utakata arch show mvvm    # Show layer structure and naming rules
```

| Architecture | Layers | Description |
|---|---|---|
| `clean_architecture` | 4 | Domain → Infrastructure → Application → Presentation |
| `mvvm` | 3 | Model → ViewModel → View |

Per-feature architecture override is supported in `plan.yaml`:

```yaml
features:
  - name: todo
    permission: user
    entities: [todo]
    architecture: clean_architecture   # overrides project default
```

---

## Command Reference

### Project setup

| Command | Description |
|---|---|
| `utakata doc init` | Create the `doc/` workspace (specs/records/preview/impl/knowledge/archive) + `utakata.yaml`, ahead of the Flutter project itself |
| `utakata doc show <config\|plan\|imports\|records\|impl>` / `utakata doc list` | Print the bundled reference for `utakata.yaml` / `doc/specs/plan.yaml` / `import_rules` / records policy (matches the installed version; also available as the MCP `doc_get` tool) |
| `utakata create <name> [--org] [--platforms] [--arch] [--mcp ...]` | Create a new Flutter project with the chosen architecture, plus `.mcp.json` + `.claude/`. Takes the same `--mcp` / `--mcp-url` / `--mcp-header` / `--mcp-name` as `claude init` (see [MCP destination](#mcp-destination)) |
| `utakata doctor [--migrate]` | Diagnose the project; `--migrate` moves a legacy `AI/`-based layout (or an ad-hoc `doc/`) to the current one |

### Structure

| Command | Description |
|---|---|
| `utakata feature add <name> [--entity] [--permission] [--template <id>]` | Scaffold one feature. `--template` applies a feature preset (`manifest.yaml` resolved from the project or `~/.utakata/feature_templates/`) and registers it in `plan.yaml` in the same step |
| `utakata apply [--scope all\|feature\|core] [--dry-run]` | Generate whatever `plan.yaml` declares but `lib/` is missing |
| `utakata plan adopt [-y]` | Detect features present in `lib/features/` but absent from `plan.yaml`, and append them (keeps existing comments/formatting) |
| `utakata plan expand [--dry-run] [--feature <name>]` | Materialize the auto-derived per-layer file lists into `plan.yaml`, so you can then edit them by hand |
| `utakata plan add <feature> <layer> <item...>` / `remove <feature> <layer> <item>` | Add or remove one item in a layer's list (for AI agents and scripts; format-preserving) |
| `utakata check [--json] [--file <path>]` | Report missing files, extra files, and naming violations in one pass |
| `utakata imports [--json] [--arch <id>]` | Audit import health: layer dependency graph (`import_rules`) + package placement declarations (`dependencies/*.yaml`); exits 1 on violations |
| `utakata status [--brief] [--write-report]` | Flutter version + lint + `check` summary. `--brief` skips flutter calls entirely (used by Claude Code hooks) |
| `utakata arch list\|show\|eject\|export` | Inspect architecture definitions or eject one locally to customize |
| `utakata arch get [--update]` | Fetch the opt-in `knowledge_repo` from `utakata.yaml` and pin its commit SHA in `utakata.lock` |

### Client & records (append-only; AI access set by `records.agent_write`)

| Command | Description |
|---|---|
| `utakata log add "..." -s client\|developer\|system\|third_party [--at] [--thread] [--tag] [--reply-to] [--draft]` | Append one conversation entry (`doc/records/log/YYYY-MM.jsonl`) |
| `utakata log show [--date] [--thread] [--tag]` / `utakata log render` | Query entries / regenerate the Markdown preview under `doc/preview/` |
| `utakata log import claude-session [--list\|--last\|--session <id>] [--full] [-y]` | Human-driven import of a Claude Code session transcript into `doc/records/sessions/` (user/assistant text only by default, secrets `[REDACTED]`, interactive confirmation) |
| `utakata message add -d inbound\|outbound [-c <channel>] [--at] [--from\|--to] [--subject] [--thread] [--external-id] "..."` | Record verbatim correspondence, unmodified (`doc/records/messages/YYYY-MM.jsonl`) |
| `utakata message import --format jsonl\|md [--file <path>] [--channel] [--dry-run]` | Bulk-import existing correspondence; duplicates skipped by `external_id` or content |
| `utakata message list\|show\|render\|link` | Query / print in full / regenerate `doc/preview/messages/` / attach a log or agreement reference |
| `utakata agree add --title "..." --kind client_agreement\|internal_decision\|tentative [--amount] [--from <msg ids>]` | Record an agreement (`doc/records/agreements.jsonl`, append-only) |
| `utakata agree status <id> <status>` / `correct <id>` / `reflect <id> --plan\|--spec` / `list [--unreflected]` | Update, supersede, or link an agreement; list unreflected ones |
| `utakata impl new [kind:]<target> [--agreement] [--spec] [--message] [--basis] [--backlog] [--supersedes]` | Open an implementation plan (`doc/impl/1_todo/PLAN-NNNN_{feature}.md`). `kind` is `feat` (default), `fix`, `refactor`, `docs`, `chore` or `test`; `--supersedes` links the plan it replaces |
| `utakata impl note <id> "text"` / `revise <id> --reason` | Append a progress note (stdin works) / accept edits to a frozen plan as a revision |
| `utakata impl start\|review\|done\|archive <id>` | Advance the implementation axis; the file moves to the matching lane |
| `utakata impl test start\|review\|done\|todo\|skip <id>` | Advance the verification axis (only once implementation is `done`; `skip --reason` declares testing unnecessary) |
| `utakata impl list [--status] [--test] [--lane] [--json]` / `board` / `sync [--dry-run]` | Query, print the lane board (regenerates `doc/preview/impl_board.md`), or move files back to the lane their frontmatter implies |
| `utakata summary` | Regenerate the agreement-ledger section of `doc/summary.md`, leaving hand-written sections untouched |

### Knowledge

| Command | Description |
|---|---|
| `utakata guide list\|show\|eject [--arch]` | Browse a layer's guide, or eject one locally to start customizing |
| `utakata guide for <file> [--json]` | Deterministically resolve the layer guide for a file under `lib/features/` (fix-context for lint errors) |

### AI integration

| Command | Description |
|---|---|
| `utakata mcp` | Start a stateless, read-only MCP server over stdio (`structure_get`, `check_run`, `plan_get`, `log_query`, `agreements_query`, `guide_get`, `guide_for_file`, `config_get`, `doc_get`, `vault_list`, `vault_get`, plus `message_query` when `records.agent_read.messages` is enabled) |
| `utakata vault list\|show\|get` | Browse the personal knowledge vault used to write client-facing explanations (configured via `vault:`, usually in `~/.utakata/config.yaml`) |
| `utakata skills sync [--force]` | Sync the architecture's bundled SKILLs listed in `utakata.yaml` into `.claude/skills/` (managed-marker protection: human files are never overwritten) |
| `utakata claude init [--only <target>] [--force] [--mcp ...]` | Add or repair the Claude Code integration (`.claude/` + `.mcp.json` + `CLAUDE.md`) in an existing project. Default writes missing files only. `--only skills` (targets: `skills` / `agents` / `mcp` / `settings` / `claude-md`, repeatable) regenerates just those, overwriting them. `--force` regenerates everything; `settings.json` and `CLAUDE.md` are overwritten as whole files. `.mcp.json` only ever gets `mcpServers.utakata` (or the `--mcp-name` key) added/replaced; other servers are kept. `--mcp` / `--mcp-url` / `--mcp-header` / `--mcp-name` choose what that entry points to (see [MCP destination](#mcp-destination)) |

`diff` remains as a permanent alias for `check`. `scan`, `validate`, `feature init`, `core`, and `arch create` have been removed/renamed — see [CHANGELOG.md](CHANGELOG.md).

---

## For AI Agents

`utakata create` writes `.mcp.json` and `.claude/settings.json` with:
- **SessionStart** → `utakata status --brief` (project state, no flutter calls)
- **PostToolUse** (Edit/Write) → `utakata check --json` (immediate feedback on the file just touched)
- **Stop** → `utakata status --brief --write-report`
- **deny** rules on `Edit`/`Write` under `doc/records/**` and `doc/preview/**` — the write path for conversation logs and agreements is human-only, enforced by the host, not just documentation

Prefer the `utakata` CLI to extend project structure rather than creating files by hand, and run `utakata check` before committing.

### MCP destination

By default `.mcp.json` launches `utakata mcp` over stdio. When the MCP server is provided elsewhere (e.g. an IDE that serves MCP over HTTP) or `utakata` is not on `PATH` for the MCP client, choose the destination with flags on `claude init` / `create`:

| Option | Meaning |
|---|---|
| `--mcp=stdio\|http\|none` | `stdio` (default) = `{"command": "utakata", "args": ["mcp"]}`. `http` = `{"type": "http", "url": ..., "headers": {...}}`. `none` = never touch `.mcp.json` (`--only mcp` then does nothing) |
| `--mcp-url <url>` | URL for `http` (required). Giving `--mcp-url` alone implies `--mcp=http`. Written verbatim, so `${VAR}` is left for Claude Code to expand from the environment |
| `--mcp-header 'Name: value'` | Header for `http` (repeatable). Split at the first `:` and trimmed. `headers` is omitted when none are given |
| `--mcp-name <name>` | Key under `mcpServers` that utakata adds/replaces (default `utakata`). Other servers are kept |

Contradicting combinations (`--mcp=http` without a URL, `--mcp-url` / `--mcp-header` with `stdio` / `none`, `--mcp-name` with `none`, a header without `:`) exit with 64 and write nothing.

```bash
# Point Claude Code at an IDE's HTTP MCP server; ${...} is expanded by Claude Code
utakata claude init --only mcp \
  --mcp-url '${MIDE_MCP_URL}' \
  --mcp-header 'Authorization: Bearer ${MIDE_MCP_TOKEN}' \
  --mcp-name mobile-ide
```

```json
{
  "mcpServers": {
    "mobile-ide": {
      "type": "http",
      "url": "${MIDE_MCP_URL}",
      "headers": { "Authorization": "Bearer ${MIDE_MCP_TOKEN}" }
    }
  }
}
```

These flags only change `.mcp.json`. The hooks in `.claude/settings.json` and the skills still call the `utakata` CLI (the MCP server is read-only; writes such as `impl new` / `log add` / `apply` need the CLI), so keep `utakata` available to the hooks even with `http` / `none`. The choice is not saved anywhere: when you regenerate `.mcp.json` later (`--force` / `--only mcp`), pass the same flags again, otherwise the default `mcpServers.utakata` stdio entry is added.

---

## Architecture

`utakata` itself is implemented using Clean Architecture:

```
packages/utakata_code/lib/src/
├── 0_templates/       # Architecture templates (clean_architecture, mvvm)
├── 1_domain/          # Entities, repository interfaces, use cases, pure services
├── 2_infrastructure/  # Filesystem/YAML/JSONL/process data sources, models, repository impls
└── 3_application/     # Command handlers, runner, presenters, MCP server
```

### Standalone executable and bundled files

`dart compile exe bin/utakata.dart` produces a single binary. Because a compiled binary cannot locate the package directory, the files it reads at runtime (`lib/src/0_templates/**` and `doc/*.md`) are embedded in `lib/src/bundled_assets.g.dart` and written once to `~/.utakata/cache/bundled-<version>/` on first use.

Bundled files are looked up in this order:

1. `UTAKATA_ASSETS_DIR` — a directory laid out like the package root (`lib/src/0_templates/`, `doc/`)
2. The package directory (`dart run` / `dart pub global activate`)
3. The embedded copy above

After changing anything under `lib/src/0_templates/` (including `tool/sync_arch_lib.dart`) or `doc/*.md`, regenerate the embedded copy (a test fails if it is stale):

```sh
dart run tool/generate_bundled_assets.dart
```

---

## License

This project uses a **dual license**:

1. **Open Source (GNU GPL v3)**
   Free to use, fork, and modify for personal/open-source projects under the [GNU GPL v3](LICENSE).

2. **Commercial Use**
   Commercial use of this tool or any code generated by it requires a separate commercial license.
   Contact the author ([@code_utakata](https://x.com/code_utakata)) for details.

---

## Links

- [Repository](https://github.com/utakata-code/utakata)
- [pub.dev](https://pub.dev/packages/utakata)
- [X (Twitter) @code_utakata](https://x.com/code_utakata)
- [utakata code](https://github.com/utakata-code)
