# Goose Recipe Troubleshooting

---

## Symptom: Good performance yesterday, bad performance today

Recipes producing wrong findings, ignoring their own tool output, or hallucinating results that contradict the raw data returned by kubectl.

### Root causes (check in this order)

**1. Accumulated session DB**

Goose writes every recipe run to a SQLite session DB. Without `--no-session`, the DB grows across the day. While each recipe run creates a new session (not inheriting prior context directly), a bloated DB with many large sessions can degrade Goose's session management overhead.

Check the DB size:
```zsh
ls -lh ~/.local/share/goose/sessions/sessions.db
```

Check today's sessions:
```zsh
sqlite3 ~/.local/share/goose/sessions/sessions.db "
SELECT s.id, s.created_at, COUNT(m.id) as messages, SUM(length(m.content_json)) as bytes
FROM sessions s
LEFT JOIN messages m ON m.session_id = s.id
WHERE date(s.created_at) = date('now')
GROUP BY s.id
ORDER BY s.created_at DESC;"
```

A session with 30+ messages or >30KB of content indicates the model looped — see Recipe Looping below.

**2. A recipe caused the model to loop**

The clearest sign: a session with far more messages than expected (a recipe should complete in 10–15 tool calls). Looping is caused by:

- A recipe step asking the model to do arithmetic or string manipulation in shell/jq that it attempts inline, hits a quoting error, then spirals trying to recover
- A recipe step with no jq filter file backing it, forcing the model to improvise
- An `echo` or `printf` command returning `(no output)` — the model then tries alternative approaches repeatedly

The fix is always in the recipe, not the model — see [Recipe Fixes](#recipe-fixes) below.

**3. Thermal throttling**

If the Mac has been running warm, inference quality degrades. Check:
```zsh
sudo powermetrics --samplers smc -n 1 2>/dev/null | grep -i "cpu die temp"
ollama ps   # check how long the model has been loaded
```

Fix: restart Ollama to force a model reload, or switch to a lighter model for the session.

---

## Session DB maintenance

### Check size
```zsh
goose-size
# or
ls -lh ~/.local/share/goose/sessions/sessions.db
```

### Trim sessions older than 1 day (safe, preserves today)
```zsh
goose-trim
# or
sqlite3 ~/.local/share/goose/sessions/sessions.db "
  DELETE FROM messages WHERE session_id IN (
    SELECT id FROM sessions WHERE created_at < date('now', '-1 day')
  );
  DELETE FROM sessions WHERE created_at < date('now', '-1 day');
  VACUUM;"
```

### Full clear (nuclear — use before important recipe runs)
```zsh
goose-clear
# or
rm ~/.local/share/goose/sessions/sessions.db
```

Goose recreates the DB clean on next run.

### Shell aliases (add to ~/.zshrc)
```zsh
alias goose-size="ls -lh ~/.local/share/goose/sessions/sessions.db"
alias goose-clear="rm ~/.local/share/goose/sessions/sessions.db && echo 'sessions cleared'"
alias goose-trim="sqlite3 ~/.local/share/goose/sessions/sessions.db \"DELETE FROM messages WHERE session_id IN (SELECT id FROM sessions WHERE created_at < date('now', '-1 day')); DELETE FROM sessions WHERE created_at < date('now', '-1 day'); VACUUM;\" && echo 'old sessions trimmed'"
```

---

## Always use --no-session

Every recipe invocation should use `--no-session`. It prevents Goose from loading or writing session state, keeping each run fully isolated regardless of what else has run today.

```zsh
goose run --no-session --model qwen3-coder:30b \
  --recipe <recipe>.yaml \
  --params namespace=<ns>
```

Sessions DB location:
```zsh
goose info   # shows all paths including Sessions DB (sqlite)
```

---

## Recipe Looping

### How to detect it

```zsh
sqlite3 ~/.local/share/goose/sessions/sessions.db "
SELECT s.id, s.created_at, COUNT(m.id) as message_count
FROM sessions s
LEFT JOIN messages m ON m.session_id = s.id
WHERE date(s.created_at) = date('now')
GROUP BY s.id
ORDER BY message_count DESC
LIMIT 5;"
```

A recipe that should complete in ~10 tool calls showing 30–60 messages = looping.

### Inspect what a session was doing

```zsh
sqlite3 ~/.local/share/goose/sessions/sessions.db "
SELECT role, substr(content_json, 1, 300)
FROM messages
WHERE session_id = '<session_id>'
ORDER BY id;"
```

Look for repeating patterns: the same command attempted multiple times, `(no output)` tool responses followed by the model retrying with slight variations, or `/tmp` file writes appearing unexpectedly.

### Common loop triggers in recipes

| Trigger | Symptom | Fix |
|---|---|---|
| Step asks model to calculate % in shell | `jq: syntax error` → model retries with different inline jq | Move calculation to a `.jq` filter file |
| Step asks model to calculate % mentally | Model writes shell arithmetic, hits quoting error | Instruct model to classify by inspection (not calculate) |
| `echo` multi-line report to stdout | `(no output)` from shell tool | Tell model to produce report as its text response, not via shell |
| Missing jq filter file for a step | Model writes inline jq, hits quoting error | Add the filter file; reference it with `jq -f` |
| Scope loop across all namespaces | Shell for-loop with embedded jq fails | Use `--all-namespaces` with a filter file instead |

### Recipe instructions block hardening

Add these lines to the `instructions:` block of any recipe that has shown looping:

```yaml
instructions: |
  STRICT RULE — NO INLINE JQ: Never write your own jq expressions.
  Do NOT write shell loops or arithmetic.
  Do NOT write to /tmp files.
  Do NOT use echo or printf to output the report — produce it as your text response only.
  If a command errors, report it and move on — do not attempt alternatives.
```

---

## Recipe Fixes Applied

### namespace-resource-quota.yaml

**Problem:** Step 5 asked the model to calculate `pct = used/hard * 100` — caused inline jq arithmetic, quoting error, then 40+ message loop trying to recover via `echo`, `/tmp` writes, and shell for-loops.

**Fix:** 
- Added `jq-filters/quota-usage.jq` — extracts used/hard as string pairs, no arithmetic
- Replaced Step 5 with classify-by-inspection instruction (model reads values directly)
- Added explicit prohibitions to instructions block: no shell loops, no `/tmp`, no echo output

---

## Diagnostic Quick Reference

```zsh
# Where does Goose store things?
goose info

# How big is the sessions DB?
goose-size

# What ran today and how many messages?
sqlite3 ~/.local/share/goose/sessions/sessions.db \
  "SELECT id, created_at, (SELECT COUNT(*) FROM messages WHERE session_id = s.id) as msgs
   FROM sessions s WHERE date(created_at) = date('now') ORDER BY created_at DESC;"

# Is the model loaded and how long has it been up?
ollama ps

# Clear everything and start fresh
goose-clear
```

---

## Session DB Schema (Goose 1.31.1)

Useful for ad-hoc queries:

```
sessions   — id, created_at, updated_at, accumulated_total_tokens, recipe_json, provider_name
messages   — id, session_id, role, content_json, created_timestamp, tokens
threads    — id, name, created_at (Goose desktop UI threads)
```

Token tracking (`accumulated_total_tokens`) is not populated when using local Ollama models — Ollama does not return token counts to Goose in the same way cloud providers do. This means Goose cannot enforce context limits automatically when using Ollama, making `--no-session` and recipe discipline more important, not less.
