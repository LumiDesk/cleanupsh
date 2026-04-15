#!/usr/bin/env bash
# =============================================================================
#  cleanup.sh — Ubuntu 开发环境一键缓存清理脚本
#  适用工具: apt / uv / Go / Java+Maven / npm / pnpm / Cargo
# =============================================================================

set -euo pipefail

# ---------- 颜色 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ---------- 工具函数 ----------
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[SKIP]${RESET}  $*"; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${CYAN}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════${RESET}"; }

# 释放的空间统计
FREED=0

# 计算目录大小（MB），目录不存在返回 0
dir_size_mb() {
  local path="$1"
  if [[ -d "$path" || -f "$path" ]]; then
    { du -sm "$path" 2>/dev/null || true; } | awk 'NR==1{print $1+0} END{if(NR==0) print 0}'
  else
    echo 0
  fi
}

# 安全删除目录内容（保留目录本身）
clean_dir() {
  local path="$1"
  if [[ -d "$path" ]]; then
    local mb
    mb=$(dir_size_mb "$path")
    rm -rf "${path:?}"/*  2>/dev/null || true
    FREED=$((FREED + mb))
    ok "已清理 $path  (~${mb} MB)"
  else
    warn "$path 不存在，跳过"
  fi
}

# 安全删除整个路径
clean_path() {
  local path="$1"
  if [[ -e "$path" ]]; then
    local mb
    mb=$(dir_size_mb "$path")
    rm -rf "$path" 2>/dev/null || true
    FREED=$((FREED + mb))
    ok "已删除 $path  (~${mb} MB)"
  else
    warn "$path 不存在，跳过"
  fi
}

# ---------- 检查是否以普通用户运行（sudo 权限用于 apt） ----------
if [[ $EUID -eq 0 ]]; then
  echo -e "${RED}[WARN]${RESET} 请勿直接以 root 运行本脚本，脚本会在需要时自动请求 sudo。"
  exit 1
fi

echo -e "${BOLD}"
echo "  ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗   ██╗██████╗ "
echo " ██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║   ██║██╔══██╗"
echo " ██║     ██║     █████╗  ███████║██╔██╗ ██║██║   ██║██████╔╝"
echo " ██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║   ██║██╔═══╝ "
echo " ╚██████╗███████╗███████╗██║  ██║██║ ╚████║╚██████╔╝██║     "
echo "  ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝     "
echo -e "${RESET}"
echo -e "  Ubuntu 开发环境缓存清理脚本  |  $(date '+%Y-%m-%d %H:%M:%S')\n"

# =============================================================================
#  1. APT
# =============================================================================
section "1/7  APT 缓存"
APT_BEFORE=$(dir_size_mb /var/cache/apt/archives)

info "清理 apt 下载包缓存..."
sudo apt-get clean -y
ok "apt-get clean 完成"

info "删除孤立依赖包..."
sudo apt-get autoremove -y --purge
ok "apt-get autoremove 完成"

info "清理过期的 apt 列表缓存..."
sudo apt-get autoclean -y
ok "apt-get autoclean 完成"

APT_AFTER=$(dir_size_mb /var/cache/apt/archives)
FREED=$((FREED + APT_BEFORE - APT_AFTER))

# =============================================================================
#  2. uv (Python 包管理器)
# =============================================================================
section "2/7  uv 缓存"
UV_CACHE="${UV_CACHE_DIR:-$HOME/.cache/uv}"
if command -v uv &>/dev/null; then
  UV_MB=$(dir_size_mb "$UV_CACHE")
  FREED=$((FREED + UV_MB))
  info "执行 uv cache clean..."
  uv cache clean
  ok "uv cache clean 完成"
else
  warn "uv 未安装，改为直接清理缓存目录"
  clean_dir "$UV_CACHE"
fi

# =============================================================================
#  3. Go
# =============================================================================
section "3/7  Go 缓存"
if command -v go &>/dev/null; then
  # 先统计缓存大小，再清理
  GO_BUILD_CACHE=$(go env GOCACHE 2>/dev/null || echo "$HOME/.cache/go/build")
  if [[ -d "$GO_BUILD_CACHE" ]]; then
    MB=$(dir_size_mb "$GO_BUILD_CACHE")
    FREED=$((FREED + MB))
  fi

  info "清理 Go build 缓存 (go clean -cache)..."
  go clean -cache
  ok "go clean -cache 完成"

  info "清理 Go test 缓存 (go clean -testcache)..."
  go clean -testcache
  ok "go clean -testcache 完成"

  info "清理 Go modcache (go clean -modcache)..."
  echo -ne "  ${YELLOW}是否同时清理 Go module 缓存？这将删除所有已下载的依赖，下次构建需重新下载。[y/N]${RESET} "
  read -r yn
  if [[ "${yn,,}" == "y" ]]; then
    go clean -modcache
    ok "go clean -modcache 完成"
  else
    warn "跳过 go modcache 清理"
  fi
else
  warn "go 未安装，跳过"
fi


# =============================================================================
#  4. Java / Maven
# =============================================================================
section "4/7  Maven 缓存"
MAVEN_REPO="$HOME/.m2/repository"
MAVEN_TMP="$HOME/.m2/tmp"

if [[ -d "$MAVEN_REPO" ]]; then
  info "清理 Maven 本地仓库中的 _remote.repositories / *.lastUpdated 标记文件..."
  find "$MAVEN_REPO" -name "_remote.repositories" -delete 2>/dev/null && ok "_remote.repositories 已清理"
  find "$MAVEN_REPO" -name "*.lastUpdated"         -delete 2>/dev/null && ok "*.lastUpdated 已清理"
  find "$MAVEN_REPO" -name "*.part"                -delete 2>/dev/null && ok "*.part 不完整下载文件已清理"

  echo -ne "  ${YELLOW}是否清理整个 Maven 本地仓库 (~/.m2/repository)？下次构建将重新下载所有依赖。[y/N]${RESET} "
  read -r yn
  if [[ "${yn,,}" == "y" ]]; then
    clean_path "$MAVEN_REPO"
  else
    warn "跳过 Maven 仓库整体清理"
  fi
else
  warn "~/.m2/repository 不存在，跳过"
fi

clean_path "$MAVEN_TMP"

# =============================================================================
#  5. npm
# =============================================================================
section "5/7  npm 缓存"
if command -v npm &>/dev/null; then
  NPM_CACHE="${NPM_CONFIG_CACHE:-$HOME/.npm}"
  NPM_MB=$(dir_size_mb "$NPM_CACHE")
  FREED=$((FREED + NPM_MB))
  info "执行 npm cache clean --force..."
  npm cache clean --force
  ok "npm cache clean 完成"
else
  NPM_CACHE="${NPM_CONFIG_CACHE:-$HOME/.npm}"
  warn "npm 未安装，直接清理 $NPM_CACHE"
  clean_dir "$NPM_CACHE"
fi

# 额外清理 npx 缓存
NPX_CACHE="$HOME/.npm/_npx"
clean_path "$NPX_CACHE"

# =============================================================================
#  6. pnpm
# =============================================================================
section "6/7  pnpm 缓存"
if command -v pnpm &>/dev/null; then
  # 先统计 store 大小，再修剪
  PNPM_STORE=$(pnpm store path 2>/dev/null || echo "")
  if [[ -n "$PNPM_STORE" ]]; then
    BEFORE=$(dir_size_mb "$PNPM_STORE")
  else
    BEFORE=0
  fi

  info "执行 pnpm store prune..."
  pnpm store prune
  ok "pnpm store prune 完成"

  if [[ -n "$PNPM_STORE" ]]; then
    AFTER=$(dir_size_mb "$PNPM_STORE")
    FREED=$((FREED + BEFORE - AFTER))
  fi
else
  PNPM_CACHE="${PNPM_STORE:-$HOME/.local/share/pnpm/store}"
  warn "pnpm 未安装，直接清理 $PNPM_CACHE"
  clean_dir "$PNPM_CACHE"
fi

# =============================================================================
#  7. Cargo (Rust)
# =============================================================================
section "7/7  Cargo 缓存"
CARGO_REGISTRY="$HOME/.cargo/registry"
CARGO_GIT="$HOME/.cargo/git"

if command -v cargo &>/dev/null; then
  # 清理 registry 解压源码（可从 .crate 重新解压，最占空间）
  if [[ -d "$CARGO_REGISTRY/src" ]]; then
    MB=$(dir_size_mb "$CARGO_REGISTRY/src")
    rm -rf "$CARGO_REGISTRY/src" 2>/dev/null || true
    FREED=$((FREED + MB))
    ok "已清理 cargo registry/src  (~${MB} MB)"
  else
    warn "$CARGO_REGISTRY/src 不存在，跳过"
  fi

  # 清理 .crate 下载包缓存
  if [[ -d "$CARGO_REGISTRY/cache" ]]; then
    MB=$(dir_size_mb "$CARGO_REGISTRY/cache")
    rm -rf "$CARGO_REGISTRY/cache" 2>/dev/null || true
    FREED=$((FREED + MB))
    ok "已清理 cargo registry/cache  (~${MB} MB)"
  else
    warn "$CARGO_REGISTRY/cache 不存在，跳过"
  fi

  # 清理 git 依赖的 checkouts（可重新拉取）
  if [[ -d "$CARGO_GIT/checkouts" ]]; then
    MB=$(dir_size_mb "$CARGO_GIT/checkouts")
    rm -rf "$CARGO_GIT/checkouts" 2>/dev/null || true
    FREED=$((FREED + MB))
    ok "已清理 cargo git checkouts  (~${MB} MB)"
  else
    warn "$CARGO_GIT/checkouts 不存在，跳过"
  fi

  # 提示 target/ 目录需手动清理
  echo -e "  ${YELLOW}[提示]${RESET}  各项目的 target/ 目录未自动清理。"
  echo -e "         如需释放空间，请在对应项目目录下手动执行: ${BOLD}cargo clean${RESET}"
else
  warn "cargo 未安装，直接清理缓存目录"
  clean_dir "$CARGO_REGISTRY"
  clean_dir "$CARGO_GIT"
fi

# =============================================================================
#  额外：系统级通用清理
# =============================================================================
section "额外  系统通用清理"

# Thumbnails
clean_dir "$HOME/.cache/thumbnails"

# Trash
info "清空回收站..."
if command -v gio &>/dev/null; then
  gio trash --empty 2>/dev/null && ok "回收站已清空"
else
  clean_dir "$HOME/.local/share/Trash/files"
  clean_dir "$HOME/.local/share/Trash/info"
fi

# journalctl 日志（保留最近 3 天）
info "压缩 systemd journal 日志（保留 3 天）..."
sudo journalctl --vacuum-time=3d
ok "journal 日志清理完成"

# =============================================================================
#  汇总报告
# =============================================================================
echo -e "\n${BOLD}${GREEN}══════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  清理完成！${RESET}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════${RESET}"
echo -e "  🗑️  预计释放空间: ${BOLD}~${FREED} MB${RESET}"
echo -e "  📅  完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e ""
echo -e "  提示: 部分空间回收需要重启后才会完全体现。"
echo ""