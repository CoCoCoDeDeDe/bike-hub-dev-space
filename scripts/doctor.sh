#!/usr/bin/env bash
#
# bike-hub 环境体检
#
# 开工前跑一次，确认工具链、工作区、硬件通路都就位。
# 只诊断，不修改任何东西。
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 非交互 shell 不会读 ~/.bashrc，手动补上用户级安装目录（gh、pio 等）
export PATH="$HOME/.local/bin:$PATH"

REPOS_DIR="$WORKSPACE_ROOT/repos/bh"
MAIN_REPO="$REPOS_DIR/bike-hub"
EXPECTED_SIDES="${SIDES:-5}"

if [ -t 1 ]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_B=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_B=""; C_OFF=""
fi

PASS=0; WARN=0; FAIL=0

section() { printf '\n%s[%s]%s\n' "$C_B" "$1" "$C_OFF"; }

ok()   { printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$*"; PASS=$((PASS+1)); }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_OFF" "$*"; WARN=$((WARN+1)); }
err()  { printf '  %s✗%s %s\n' "$C_ERR" "$C_OFF" "$*"; FAIL=$((FAIL+1)); }
hint() { printf '    %s→ %s%s\n' "$C_DIM" "$*" "$C_OFF"; }

have() { command -v "$1" >/dev/null 2>&1; }

# ---------- 系统 ----------
section "系统"

if grep -qi microsoft /proc/version 2>/dev/null; then
  ok "WSL2（内核 $(uname -r)）"
else
  warn "非 WSL 环境（$(uname -s)）"
fi

DISK_AVAIL="$(df -h / 2>/dev/null | awk 'NR==2{print $4}')"
if [ -n "$DISK_AVAIL" ]; then
  ok "根分区可用空间 $DISK_AVAIL"
else
  warn "无法读取磁盘信息"
fi

if have git; then
  ok "git $(git --version | awk '{print $3}')"
else
  err "git 未安装"
  hint "sudo apt install git"
fi

GIT_NAME="$(git config --global user.name 2>/dev/null || true)"
if [ -n "$GIT_NAME" ]; then
  ok "git 全局身份 $GIT_NAME"
else
  warn "git 全局身份未设置（仅仓库级有效）"
  hint "git config --global user.name \"...\" && git config --global user.email \"...\""
fi

# ---------- 工具链 ----------
section "工具链"

if have gh; then
  GH_VER="$(gh --version | head -1 | awk '{print $3}')"
  if gh auth status >/dev/null 2>&1; then
    GH_USER="$(gh auth status 2>&1 | grep -oP 'account \K[^ ]+' | head -1)"
    ok "gh $GH_VER — 已登录 ${GH_USER:-?}"
  else
    err "gh $GH_VER — 未登录"
    hint "gh auth login"
  fi
else
  err "gh 未安装"
  hint "https://github.com/cli/cli/releases（解压到 ~/.local/bin）"
fi

if have python3; then
  ok "python3 $(python3 -V 2>&1 | awk '{print $2}')"
else
  err "python3 未安装"
  hint "sudo apt install python3"
fi

if have node; then
  ok "node $(node -v)"
else
  warn "node 未安装（Node-RED 面板需要）"
fi

if have pio || have platformio; then
  PIO_BIN="$(command -v pio || command -v platformio)"
  ok "PlatformIO $("$PIO_BIN" --version 2>/dev/null | grep -oP 'version \K[0-9.]+' | head -1)"
else
  warn "PlatformIO 未安装（固件编译需要）"
  hint "pip install --user platformio   或   pipx install platformio"
fi

if have mosquitto; then
  if ss -ltn 2>/dev/null | grep -q ':1883'; then
    ok "mosquitto 已安装，1883 端口监听中"
  else
    warn "mosquitto 已安装但未运行"
    hint "sudo systemctl start mosquitto   或   mosquitto -p 1883"
  fi
else
  warn "mosquitto 未安装（本地 MQTT broker）"
  hint "sudo apt install mosquitto"
fi

if have node-red; then
  ok "node-red 已安装"
else
  warn "node-red 未安装（手机端控制台）"
  hint "npm install -g node-red"
fi

# ---------- 工作区 ----------
section "工作区"

if [ -d "$MAIN_REPO/.git" ]; then
  ok "主库 $MAIN_REPO"
else
  err "主库不存在"
  hint "$SCRIPT_DIR/worktree.sh init"
fi

if [ -d "$MAIN_REPO/.git" ]; then
  WT_COUNT="$(git -C "$MAIN_REPO" worktree list 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$WT_COUNT" -ge $((EXPECTED_SIDES + 1)) ]; then
    ok "worktree 共 $WT_COUNT 个（主库 + $((WT_COUNT - 1)) 个）"
  else
    warn "worktree 只有 $WT_COUNT 个，预期 $((EXPECTED_SIDES + 1))"
    hint "$SCRIPT_DIR/worktree.sh init"
  fi

  DIRTY_LIST=""
  while read -r d; do
    [ -n "$d" ] || continue
    n="$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    [ "$n" -gt 0 ] && DIRTY_LIST="$DIRTY_LIST $(basename "$d")($n)"
  done < <(git -C "$MAIN_REPO" worktree list --porcelain | awk '/^worktree /{print $2}')

  if [ -z "$DIRTY_LIST" ]; then
    ok "所有工作区干净"
  else
    warn "未提交改动：$DIRTY_LIST"
  fi

  BEHIND="$(git -C "$MAIN_REPO" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)"
  if [ "$BEHIND" = "0" ]; then
    ok "main 与 origin/main 同步"
  else
    warn "main 落后 origin/main $BEHIND 个提交"
    hint "git -C $MAIN_REPO pull --ff-only"
  fi
fi

# ---------- 硬件通路 ----------
section "硬件通路"

PORTS=""
for p in /dev/ttyACM* /dev/ttyUSB*; do
  [ -e "$p" ] && PORTS="$PORTS $p"
done
if [ -n "$PORTS" ]; then
  ok "串口设备：$PORTS"
else
  warn "未发现串口设备（/dev/ttyACM* 或 /dev/ttyUSB*）"
  hint "WSL 需要 usbipd 转发：usbipd attach --wsl --busid <id>"
fi

if id -nG 2>/dev/null | grep -qw dialout; then
  ok "当前用户在 dialout 组"
else
  err "当前用户不在 dialout 组，串口无读写权限"
  hint "sudo usermod -aG dialout $USER   （之后需重开终端）"
fi

if command -v usbipd.exe >/dev/null 2>&1; then
  if usbipd.exe list >/dev/null 2>&1; then
    ok "usbipd 可用（Windows 侧）"
  else
    warn "usbipd 已安装但调用失败"
  fi
else
  warn "usbipd 未安装（WSL 看不到 USB 设备）"
  hint "Windows PowerShell: winget install --id usbipd.usbipd-win -e"
fi

if have lsusb; then
  if [ -n "$(lsusb 2>/dev/null)" ]; then
    ok "lsusb 可见设备 $(lsusb 2>/dev/null | wc -l | tr -d ' ') 个"
  else
    warn "lsusb 无输出（未转发 USB 或未安装 usbutils）"
  fi
else
  warn "lsusb 未安装"
  hint "sudo apt install usbutils"
fi

# ---------- 网络 ----------
section "网络"

if curl -sI --max-time 5 https://github.com >/dev/null 2>&1; then
  ok "github.com 可达"
else
  err "github.com 不可达（检查代理）"
  hint "env | grep -i proxy"
fi

if curl -sI --max-time 5 https://api.github.com >/dev/null 2>&1; then
  ok "GitHub API 可达"
else
  warn "GitHub API 不可达（gh 命令会失败）"
fi

# ---------- 汇总 ----------
printf '\n%s%s%s\n' "$C_B" "────────────────────────────" "$C_OFF"
printf '  %s通过 %d%s   %s警告 %d%s   %s失败 %d%s\n' \
  "$C_OK" "$PASS" "$C_OFF" "$C_WARN" "$WARN" "$C_OFF" "$C_ERR" "$FAIL" "$C_OFF"

if [ "$FAIL" -gt 0 ]; then
  printf '\n  %s有 %d 项失败，按上面的 → 提示处理%s\n' "$C_ERR" "$FAIL" "$C_OFF"
  exit 1
elif [ "$WARN" -gt 0 ]; then
  printf '\n  %s可以开工，但有 %d 项待补%s\n' "$C_WARN" "$WARN" "$C_OFF"
  exit 0
else
  printf '\n  %s全部就绪%s\n' "$C_OK" "$C_OFF"
  exit 0
fi
