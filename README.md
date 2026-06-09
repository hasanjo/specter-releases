# Specter

AI-powered code review in your terminal. Run `specter review` inside any git repository and Specter collects your branch's diff, sends it to a locally installed AI agent (`claude`, `codex`, or `opencode`), validates the findings, checks your coding standards, and renders a color-coded report.

```
specter review
```

**Specter never talks to any model API directly.** It shells out to an AI coding CLI you already have installed — authentication, model access, and billing are handled by that CLI, not by Specter.

---

## Table of Contents

1. [Requirements](#requirements)
2. [Install](#install)
3. [First Run](#first-run)
4. [Running a Review](#running-a-review)
5. [Understanding the Report](#understanding-the-report)
6. [Copying Issues to Your Agent](#copying-issues-to-your-agent)
7. [Validation Pass](#validation-pass)
8. [Coding Standards](#coding-standards)
9. [Review History](#review-history)
10. [GitHub PR Comments](#github-pr-comments)
11. [Configuration](#configuration)
12. [Agents and Models](#agents-and-models)

---

## Requirements

- **One AI coding CLI** on your `PATH`:
  - [`claude`](https://github.com/anthropics/claude-code) — Anthropic's Claude Code CLI *(recommended)*
  - `codex` — OpenAI Codex CLI
  - `opencode` — open-source local agent
- **`git`** on your `PATH`
- Windows x64 or ARM64, Linux x64/ARM64, or macOS x64/ARM64

You do **not** need the .NET runtime — the binaries are self-contained.

---

## Install

**Windows (PowerShell):**

```powershell
powershell -c "iex (Invoke-RestMethod https://raw.githubusercontent.com/hasanjo/specter-releases/master/install-local.ps1)"
```

**Linux / macOS (bash):**

```bash
curl -fsSL https://raw.githubusercontent.com/hasanjo/specter-releases/master/install.sh | bash
```

Both scripts download the right prebuilt binary for your OS and architecture into `~/.specter/bin` and add it to your `PATH`. Open a new terminal after install.

**Verify:**

```powershell
specter --version
```

**Update** — run the same install command again at any time. It downloads the latest release and replaces the existing binary.

---

## First Run

Run `specter` with no arguments to open the interactive menu:

```
specter
```

The menu lets you:
- Start a review with the current settings
- Change agent, model, and depth
- Manage coding standards
- View review history
- Get help

For a preview of the report UI without running any AI:

```powershell
specter review --demo
```

---

## Running a Review

```powershell
specter review                          # review current branch vs auto-detected base
specter review --base develop           # compare against a specific branch or ref
specter review --staged                 # review only staged changes (git add first)
specter review --base HEAD~3            # review last 3 commits
specter review --depth fast             # fast: critical issues only
specter review --depth phenomenal       # exhaustive: deep multi-pass review
specter review --no-validate            # skip the validation pass (faster)
specter review --no-standards           # skip the standards check
specter review --agent opencode         # pick a specific AI agent
specter review --model gpt-4.1         # override the model
specter review --pr                     # post findings as GitHub PR comments
```

### How the diff is collected

Specter automatically detects what to review:

| Situation | What gets reviewed |
|---|---|
| On a feature branch with a remote | Changes on this branch vs `origin/main` (or `origin/master`) |
| On main with no remote | Unstaged working-tree changes, or staged changes, or last commit |
| `--staged` flag | Only staged changes (`git add`ed files) |
| `--base <ref>` | Explicitly defined range |

### Depth levels

| Flag | What it does | Speed |
|---|---|---|
| `--depth fast` | Critical issues only (bugs, security, hallucinations) | ~30s |
| `--depth standard` | Balanced review — bugs, logic, security, simplifications | ~1–2 min |
| `--depth phenomenal` | Exhaustive: deep second pass + agent inspects the working tree | ~3–5 min |

---

## Understanding the Report

After the review runs, Specter prints:

```
Found 5 issues  1 critical  ·  2 bugs  ·  2 logic  ·  1 simplify  — validating…
```

Then, after the validation pass confirms the findings, the full report renders:

```
╭─ verdict ────────────────────────────────────────────────╮
│  SUSPECT   intent may be off                              │
│  Implements auth flow but uses deprecated token pattern.  │
╰───────────────────────────────────────────────────────────╯

╭─● BUG  CRITICAL  src/Auth/TokenService.cs:88  1/4  (1 to copy) ─╮
│ RefreshToken not invalidated after use                           │
│ A used refresh token is never removed from the store, allowing   │
│ replay attacks indefinitely.                                     │
│ ╭─ suggested fix ──────────────────────────────────────────────╮ │
│ │ _store.Remove(token);                                        │ │
│ ╰──────────────────────────────────────────────────────────────╯ │
╰──────────────────────────────────────────────────────────────────╯
```

### Category colors

| Color | Category | Meaning |
|---|---|---|
| Magenta | HALLUCINATION | AI invented an API, method, or type that doesn't exist |
| Red | SECURITY | Auth flaw, injection, data exposure |
| Orange | BUG | Crash, incorrect logic, data loss |
| Yellow | LOGIC | Off-by-one, wrong condition, mismatched intent |
| Blue | SIMPLIFY | Overengineered code that can be simplified |

### Severity badges

Each issue carries a severity badge in the panel header:

| Badge | Meaning |
|---|---|
| `CRITICAL` (red) | Data loss, security hole, production crash |
| `major` (orange) | Significant bug or degraded functionality |
| `minor` (grey) | Style, low-risk improvement |

### Verdict banner

| Verdict | Meaning |
|---|---|
| `SOUND` | Logic verified — change appears correct |
| `SUSPECT` | Intent may be off — review carefully |
| `HALLUCINATION` | The AI likely invented APIs or logic |

---

## Copying Issues to Your Agent

After the report, Specter prompts:

```
Type issue # to copy · d<n> to dismiss · Enter to skip:
```

**Type a number** (e.g. `2`) → copies the full issue block to your clipboard, formatted as an instruction for your AI agent:

```
Specter (AI code review tool) flagged the following issue in this codebase. Please:
1. Open the file and read the actual code at the reported location.
2. Verify whether the issue is real given the full context.
3. If confirmed, fix it. If it's a false positive, explain why.

---
Category : BUG
Location : src/Auth/TokenService.cs:88
Title    : RefreshToken not invalidated after use

A used refresh token is never removed...

Suggested fix:
_store.Remove(token);
---
```

Paste this directly into Claude Code, Cursor, or any AI agent — it will open the file, verify, and fix it.

**Type `d2`** → dismisses issue #2 as a false positive. Specter remembers dismissed patterns and biases future validation passes to deprioritize similar findings.

---

## Validation Pass

After the initial review, Specter runs a second AI call that re-checks every finding:

- `VALID` — confirmed real issue
- `PARTIAL` — partially correct (e.g. file is right, line is wrong)
- `INVALID` — false positive, ruled out

**Only confirmed findings are shown in the final report.** Invalid findings are silently filtered out before rendering.

Skip validation with `--no-validate` if you want faster results or are using a slower agent.

---

## Coding Standards

Specter checks every diff against a set of coding standards. There are three tiers:

| Label | Source | Managed by |
|---|---|---|
| `[GLOBAL]` | `~/.specter/standards.json` | You (applies to all repos) |
| `[LEARNED]` | `~/.specter/standards/<repo-id>.json` | Auto-learned per repo |
| `[TEAM]` | `<repo>/.specter/standards.json` | Committed to the repo |

### Auto-learning

On your **first review** of a repo, Specter automatically analyzes the codebase (recent commits + key files like controllers, services, entities) and learns the team's patterns — naming conventions, architecture style, error handling approach, etc. These are saved to `~/.specter/standards/<repo-id>.json`.

Every **7 days**, the standards are refreshed automatically.

### View active standards

```powershell
specter standards list
```

### Manually re-learn standards

```powershell
specter standards learn
```

Specter analyzes the full codebase and asks you to confirm before saving. Useful after a major refactor or architecture change.

### Skip standards check

```powershell
specter review --no-standards
```

---

## Review History

Specter remembers the findings from your last review on each branch.

After each review, issues are labelled:

| Label | Meaning |
|---|---|
| `NEW` | First time this issue has appeared |
| `RECURRING` | Also appeared in the previous review |
| `FIXED` | Was in the prior review, not found this time |

View the last saved review for the current repo:

```
specter          → Options → Review history
```

---

## GitHub PR Comments

Post findings directly as comments on a GitHub pull request:

```powershell
specter review --pr          # auto-detect the open PR for this branch
specter review --pr 42       # target a specific PR number
```

Requires the [`gh` CLI](https://cli.github.com/) installed and authenticated (`gh auth login`).

---

## Configuration

All settings persist to `~/.specter/config.json` and are managed through the TUI:

```
specter          → Options
```

| Setting | Default | CLI flag |
|---|---|---|
| Agent | `claude` | `--agent claude/codex/opencode` |
| Model | *(agent default)* | `--model <value>` |
| Depth | `standard` | `--depth fast/standard/phenomenal` |
| Validation | enabled | `--no-validate` |
| Standards | enabled | `--no-standards` |

---

## Agents and Models

### Claude (default)

```powershell
specter review --agent claude --model sonnet
specter review --agent claude --model opus
specter review --agent claude --model haiku
```

Requires [`claude`](https://github.com/anthropics/claude-code) CLI installed and authenticated.

### Codex (OpenAI)

```powershell
specter review --agent codex --model o3
specter review --agent codex --model gpt-4.1
specter review --agent codex --model o4-mini
```

Requires `codex` CLI with an OpenAI API key.

### Opencode

```powershell
specter review --agent opencode --model zai-coding-plan/glm-5.1
```

Requires `opencode` CLI. Run `specter` → Options → Change model to browse all available models with their provider names.

