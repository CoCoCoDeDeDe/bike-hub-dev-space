#!/usr/bin/env bash
#
# bike-hub 工作区管理
#
# 主库与 5 个并行 worktree 的创建、查看、增删。
# 幂等：重复执行 init 不会破坏已有工作区。
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPOS_DIR="$WORKSPACE_ROOT/repos/bh"
MAIN_REPO="$REPOS_DIR/bike-hub"

BH_REMOTE="${BH_REMOTE:-https://github.com/CoCoCoDeDeDe/bike-hub.git}"
BH_BASE="${BH_BASE:-main}"
SIDES="${SIDES:-5}"

if [ -t 1 ]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_INFO=$'\033[36m'; C_OFF=$'\033[0m'
else
  C_OK=""; C_WARN=""; C_ERR=""; C_INFO=""; C_OFF=""
fi

info() { printf '%s•%s %s\n' "$C_INFO" "$C_OFF" "$*"; }
ok()   { printf '%s✓%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '%s!%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
die()  { printf '%s✗%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

wt_path() { printf '%s/bike-hub-side-%s' "$REPOS_DIR" "$1"; }

wt_exists() { [ -e "$(wt_path "$1")/.git" ]; }

require_main() {
  [ -d "$MAIN_REPO/.git" ] || die "主库不存在：$MAIN_REPO（先运行 init）"
}

ensure_main() {
  if [ -d "$MAIN_REPO/.git" ]; then
    info "主库已存在，拉取远程引用"
    git -C "$MAIN_REPO" fetch --prune origin
  else
    info "克隆主库 → $MAIN_REPO"
    mkdir -p "$REPOS_DIR"
    git clone "${BH_REMOTE%.git}" "$MAIN_REPO"
  fi
}

# 创建第 n 个 worktree；分支优先用本地，其次跟踪远程，最后从基线新建
cmd_add() {
  local n="$1"
  local branch="side-$n"
  local path
  path="$(wt_path "$n")"

  if wt_exists "$n"; then
    warn "side-$n 已存在，跳过"
    return 0
  fi

  if [ -d "$path" ] && [ -n "$(ls -A "$path" 2>/dev/null)" ]; then
    die "目录非空且不是 worktree：$path"
  fi

  require_main

  if git -C "$MAIN_REPO" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$MAIN_REPO" worktree add "$path" "$branch"
  elif git -C "$MAIN_REPO" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    git -C "$MAIN_REPO" worktree add "$path" -b "$branch" --track "origin/$branch"
  else
    git -C "$MAIN_REPO" worktree add "$path" -b "$branch" "$BH_BASE"
  fi
  ok "worktree side-$n → $path"
}

cmd_init() {
  ensure_main
  local i
  for i in $(seq 1 "$SIDES"); do
    cmd_add "$i"
  done
  printf '\n'
  cmd_status
}

cmd_status() {
  require_main
  printf '%-20s %-10s %-6s %-6s %s\n' "WORKTREE" "BRANCH" "AHEAD" "BEHIND" "DIRTY"
  printf '%-20s %-10s %-6s %-6s %s\n' "--------" "------" "-----" "------" "-----"
  local d b ahead behind dirty up
  while read -r d; do
    [ -n "$d" ] || continue
    b="$(git -C "$d" branch --show-current 2>/dev/null || true)"
    [ -n "$b" ] || b="(detached)"
    up="$(git -C "$d" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
    if [ -n "$up" ]; then
      ahead="$(git -C "$d" rev-list --count '@{u}..HEAD' 2>/dev/null || echo '?')"
      behind="$(git -C "$d" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo '?')"
    else
      ahead="-"; behind="-"
    fi
    dirty="$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    printf '%-20s %-10s %-6s %-6s %s\n' "$(basename "$d")" "$b" "$ahead" "$behind" "$dirty"
  done < <(git -C "$MAIN_REPO" worktree list --porcelain | awk '/^worktree /{print $2}')
}

cmd_remove() {
  local n="$1" path
  path="$(wt_path "$n")"
  [ -e "$path" ] || die "side-$n 不存在"
  git -C "$MAIN_REPO" worktree remove "$path" --force
  ok "已移除 worktree side-$n（分支 side-$n 保留，用 'git branch -d' 清理）"
}

usage() {
  cat <<'USAGE'
bike-hub 工作区管理

  ./scripts/worktree.sh init              克隆主库并建立 5 个 worktree
  ./scripts/worktree.sh status            查看各 worktree 的同步状态
  ./scripts/worktree.sh add <n>           追加第 n 个 worktree
  ./scripts/worktree.sh remove <n>        移除第 n 个 worktree（保留分支）

环境变量:
  BH_REMOTE   主库地址（默认 https://github.com/CoCoCoDeDeDe/bike-hub.git）
  BH_BASE     基线分支（默认 main）
  SIDES       init 时创建的 worktree 数量（默认 5）

示例:
  SIDES=3 ./scripts/worktree.sh init
USAGE
}

case "${1:-help}" in
  init)   cmd_init ;;
  status) cmd_status ;;
  add)    [ $# -ge 2 ] || die "用法: $0 add <序号>"; cmd_add "$2" ;;
  remove) [ $# -ge 2 ] || die "用法: $0 remove <序号>"; cmd_remove "$2" ;;
  help|-h|--help) usage ;;
  *)      usage; exit 1 ;;
esac
