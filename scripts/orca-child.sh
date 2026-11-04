#!/usr/bin/env bash
# Hardset — Orca Child Worktree & Multi-Model Child Agent Manager
# Manages child worktree spawning, inspection, non-destructive merging, and verification
# for Antigravity Orchestrator coordinating Claude Code (claude), OpenCode (opencode), and Codex (codex).
#
# Strictly NO diagrams (no Mermaid, no ASCII box art).
# Commits and operations attributed strictly to FrankieBiz <frankabisignano@gmail.com>.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# -----------------------------------------------------------------------------
# 1. Resolve canonical Orca executable per global rules
# -----------------------------------------------------------------------------
resolve_orca() {
    local candidate=""
    if [ -n "${ORCA_CLI_COMMAND:-}" ]; then
        candidate="$ORCA_CLI_COMMAND"
    elif [ -n "${ORCA_DEV_REPO_ROOT:-}" ] && command -v orca-dev >/dev/null 2>&1; then
        candidate="orca-dev"
    elif [ -n "${DISPLAY:-}" ] && [ -z "${ORCA_TERMINAL:-}" ] && command -v orca-ide >/dev/null 2>&1; then
        candidate="orca-ide"
    elif command -v orca >/dev/null 2>&1; then
        local p
        p=$(which orca)
        if [ "$p" = "/usr/bin/orca" ]; then
            echo "ERROR: /usr/bin/orca is the Linux screen reader. Orca CLI shim required." >&2
            exit 1
        fi
        candidate="$p"
    else
        echo "ERROR: Orca CLI binary could not be resolved." >&2
        exit 1
    fi

    # Probe chosen binary
    if ! "$candidate" --version >/dev/null 2>&1; then
        echo "ERROR: Resolved Orca binary '$candidate' failed version probe." >&2
        exit 1
    fi
    echo "$candidate"
}

ORCA_BIN=$(resolve_orca)

# -----------------------------------------------------------------------------
# 2. Repository Guard
# -----------------------------------------------------------------------------
verify_repo() {
    local cur_path
    cur_path=$("$ORCA_BIN" worktree current --json 2>/dev/null | jq -r '.result.worktree.path // empty' || true)
    if [ -z "$cur_path" ]; then
        echo "ERROR: Current directory is not inside an active Orca worktree." >&2
        exit 1
    fi
    if [ "$cur_path" != "$REPO_ROOT" ]; then
        echo "[orca-child] Context worktree: $cur_path (Repo root: $REPO_ROOT)" >&2
    fi
}

# -----------------------------------------------------------------------------
# 3. Model & Frontier Enforcement
# -----------------------------------------------------------------------------
validate_frontier_model() {
    local m="${1,,}"
    case "$m" in
        *claude-3-5*|*claude-3.5*|*claude-3-7*|*claude-3.7*|*gpt-4*|*gpt-3.5*)
            echo "ERROR: Prohibited legacy model tier '$1'. Must use frontier models only." >&2
            exit 1
            ;;
    esac
}

resolve_selector() {
    local raw="$1"
    if [[ "$raw" == *":"* ]]; then
        echo "$raw"
        return
    fi
    if [ -d "$raw" ]; then
        echo "path:$(cd "$raw" && pwd)"
        return
    fi
    local by_name
    by_name=$("$ORCA_BIN" worktree show --worktree "name:$raw" --json 2>/dev/null | jq -r '.result.worktree.id // empty' || true)
    if [ -n "$by_name" ]; then
        echo "name:$raw"
        return
    fi
    local by_branch
    by_branch=$("$ORCA_BIN" worktree show --worktree "branch:$raw" --json 2>/dev/null | jq -r '.result.worktree.id // empty' || true)
    if [ -n "$by_branch" ]; then
        echo "branch:$raw"
        return
    fi
    echo "name:$raw"
}

# -----------------------------------------------------------------------------
# 4. Commands
# -----------------------------------------------------------------------------

cmd_spawn() {
    local agent="${1:-}"
    local name="${2:-}"
    local prompt="${3:-}"
    local model="${4:-}"
    local effort="${5:-}"

    if [ -z "$agent" ] || [ -z "$name" ] || [ -z "$prompt" ]; then
        echo "Usage: $0 spawn <agent> <name> <prompt> [model] [effort]" >&2
        echo "  agent:  claude | opencode | codex" >&2
        echo "  name:   child worktree and branch name descriptor" >&2
        echo "  prompt: task specification contract" >&2
        echo "  model:  optional frontier model override" >&2
        echo "  effort: optional reasoning effort (high | xhigh)" >&2
        exit 1
    fi

    case "$agent" in
        claude)
            model="${model:-sonnet}"
            effort="${effort:-high}"
            ;;
        opencode)
            case "${model:-}" in
                ""|deepseek-4.1-flash|deepseek-v4.1-flash|deepseek-flash|opencode)
                    model="opencode/deepseek-v4.1-flash-free"
                    ;;
            esac
            effort=""
            ;;
        codex)
            model="${model:-gpt-6.1-sol}"
            effort="${effort:-high}"
            ;;
        *)
            echo "ERROR: Unsupported agent '$agent'. Must be claude, opencode, or codex." >&2
            exit 1
            ;;
    esac

    validate_frontier_model "$model"
    verify_repo

    echo "[orca-child] Spawning child worktree '$name' for agent '$agent' (model: $model)..." >&2

    local args=("$ORCA_BIN" worktree create --name "$name" --agent "$agent" --prompt "$prompt" --parent-worktree active --json)
    if [ -n "$model" ]; then
        args+=(--model "$model")
    fi
    if [ -n "$effort" ]; then
        args+=(--effort "$effort")
    fi

    local resp
    resp=$("${args[@]}")

    local ok
    ok=$(echo "$resp" | jq -r '.ok // false')
    if [ "$ok" != "true" ]; then
        echo "ERROR: Orca child worktree creation failed:" >&2
        echo "$resp" | jq . >&2
        exit 1
    fi

    echo "$resp" | jq '{
        status: "SPAWNED",
        agent: "'"$agent"'",
        model: "'"$model"'",
        name: "'"$name"'",
        worktree_id: .result.worktree.id,
        path: .result.worktree.path,
        branch: .result.worktree.branch,
        parent_worktree_id: .result.worktree.parentWorktreeId
    }'
}

cmd_list() {
    verify_repo
    local cur_id
    cur_id=$("$ORCA_BIN" worktree current --json | jq -r '.result.worktree.id')

    echo "=== Active Orca Child Worktrees for Parent ($cur_id) ==="
    "$ORCA_BIN" worktree list --json | jq --arg pid "$cur_id" '
        [ .result.worktrees[] | select(.parentWorktreeId == $pid) | {
            id: .id,
            displayName: .displayName,
            agent: .createdWithAgent,
            branch: .branch,
            path: .path,
            status: .workspaceStatus,
            lastActivityAt: .lastActivityAt
        } ]
    '
}

cmd_inspect() {
    local target="${1:-}"
    if [ -z "$target" ]; then
        echo "Usage: $0 inspect <worktree-name-or-selector>" >&2
        exit 1
    fi

    local sel
    sel=$(resolve_selector "$target")
    local wt_info
    wt_info=$("$ORCA_BIN" worktree show --worktree "$sel" --json 2>/dev/null || true)
    local target_path
    target_path=$(echo "$wt_info" | jq -r '.result.worktree.path // empty')

    if [ -z "$target_path" ] || [ ! -d "$target_path" ]; then
        if [ -d "$target" ]; then
            target_path="$target"
        else
            echo "ERROR: Could not locate worktree for selector '$target' (resolved: '$sel')" >&2
            exit 1
        fi
    fi

    echo "=== Worktree Status: $target_path ==="
    git -C "$target_path" status -s
    echo ""
    echo "=== Recent Commits ==="
    git -C "$target_path" log -n 5 --oneline
    echo ""
    echo "=== Diff vs HEAD~1 ==="
    git -C "$target_path" diff --stat HEAD~1 2>/dev/null || git -C "$target_path" diff --stat
}

cmd_merge() {
    local target="${1:-}"
    local skip_verify="${2:-}"
    if [ -z "$target" ]; then
        echo "Usage: $0 merge <worktree-name-or-branch> [--no-verify]" >&2
        exit 1
    fi

    verify_repo

    local sel
    sel=$(resolve_selector "$target")
    local wt_info
    wt_info=$("$ORCA_BIN" worktree show --worktree "$sel" --json 2>/dev/null || true)
    local child_branch
    child_branch=$(echo "$wt_info" | jq -r '.result.worktree.branch // empty')
    local child_path
    child_path=$(echo "$wt_info" | jq -r '.result.worktree.path // empty')

    if [ -z "$child_branch" ]; then
        child_branch="$target"
    fi

    if [ -n "$child_path" ] && [ -d "$child_path" ]; then
        local uncommitted
        uncommitted=$(git -C "$child_path" status --porcelain)
        if [ -n "$uncommitted" ]; then
            echo "ERROR: Child worktree '$child_path' has uncommitted changes:" >&2
            echo "$uncommitted" >&2
            echo "Please commit or stash in child worktree before merging." >&2
            exit 1
        fi
    fi

    echo "[orca-child] Inspecting child branch '$child_branch'..."
    git log -n 5 --oneline "$child_branch"

    echo "[orca-child] Merging '$child_branch' into active branch non-destructively..."
    if ! git merge --no-ff "$child_branch" -m "Integrate child worktree $target"; then
        echo "ERROR: Merge conflict encountered. Aborting merge." >&2
        git merge --abort || true
        exit 1
    fi

    if [ "$skip_verify" != "--no-verify" ]; then
        echo "[orca-child] Running configured verification gate (make check)..."
        if ! make check; then
            echo "ERROR: Verification failed after merge! Rolling back merge..." >&2
            git reset --hard HEAD~1
            exit 1
        fi
        echo "✓ Verification passed cleanly after merge."
    fi

    echo "✓ Successfully integrated '$child_branch'."
}

cmd_cleanup() {
    local target="${1:-}"
    if [ -z "$target" ]; then
        echo "Usage: $0 cleanup <worktree-selector>" >&2
        exit 1
    fi
    local sel
    sel=$(resolve_selector "$target")
    echo "[orca-child] Removing child worktree '$sel'..."
    "$ORCA_BIN" worktree rm --worktree "$sel" --delete-branch --force --json
}

# -----------------------------------------------------------------------------
# Entry Point
# -----------------------------------------------------------------------------
case "${1:-}" in
    spawn)
        shift
        cmd_spawn "$@"
        ;;
    list)
        shift
        cmd_list "$@"
        ;;
    inspect)
        shift
        cmd_inspect "$@"
        ;;
    merge)
        shift
        cmd_merge "$@"
        ;;
    cleanup)
        shift
        cmd_cleanup "$@"
        ;;
    help|--help|-h|"")
        echo "Hardset — Orca Child Worktree Manager"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  spawn <agent> <name> <prompt> [model] [effort]  Spawn child worktree for claude, opencode, or codex"
        echo "  list                                            List child worktrees of current workspace"
        echo "  inspect <worktree-selector>                     Inspect git status and diffs of child"
        echo "  merge <worktree-selector> [--no-verify]         Merge child branch non-destructively & verify"
        echo "  cleanup <worktree-selector>                     Remove settled child worktree"
        echo ""
        echo "Resolved Orca CLI: $ORCA_BIN"
        ;;
    *)
        echo "Unknown command: $1" >&2
        echo "Run '$0 help' for usage." >&2
        exit 1
        ;;
esac
