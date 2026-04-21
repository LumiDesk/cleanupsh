#!/usr/bin/env bash
# =============================================================================
#  cleanup.sh — Ubuntu 开发环境一键缓存清理脚本 (加强版)
#  适用工具: apt / uv / Go / Java+Maven / npm / pnpm / Cargo / Docker / Flatpak
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

# 释放的空间统计 (MB)
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
    rm -rf "${path:?}"/* 2>/dev/null || true
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

# ---------- 检查是否以普通用户运行 ----------
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
echo -e "  Ubuntu 开发环境缓存清理脚本 (加强版) |  $(date '+%Y-%m-%d %H:%M:%S')\n"

# =============================================================================
#  1. APT
# =============================================================================
section "1/9  APT 缓存"
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
section "2/9  uv 缓存"
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
section "3/9  Go 缓存"
if command -v go &>/dev/null; then
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
section "4/9  Maven 缓存"
MAVEN_REPO="$HOME/.m2/repository"
MAVEN_TMP="$HOME/.m2/tmp"

if [[ -d "$MAVEN_REPO" ]]; then
  info "清理 Maven 本地仓库中的临时标记文件..."
  find "$MAVEN_REPO" -name "_remote.repositories" -delete 2>/dev/null && ok "_remote.repositories 已清理"
  find "$MAVEN_REPO" -name "*.lastUpdated"         -delete 2>/dev/null && ok "*.lastUpdated 已清理"
  find "$MAVEN_REPO" -name "*.part"                -delete 2>/dev/null && ok "*.part 已清理"

  echo -ne "  ${YELLOW}是否清理整个 Maven 本地仓库？下次构建将重新下载所有依赖。[y/N]${RESET} "
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
section "5/9  npm 缓存"
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
clean_path "$HOME/.npm/_npx"

# =============================================================================
#  6. pnpm
# =============================================================================
section "6/9  pnpm 缓存"
if command -v pnpm &>/dev/null; then
  PNPM_STORE=$(timeout 5 pnpm store path 2>/dev/null || echo "")
  BEFORE=${PNPM_STORE:+$(dir_size_mb "$PNPM_STORE")}
  info "执行 pnpm store prune..."
  timeout 120 pnpm store prune
  ok "pnpm store prune 完成"
  AFTER=${PNPM_STORE:+$(dir_size_mb "$PNPM_STORE")}
  FREED=$((FREED + ${BEFORE:-0} - ${AFTER:-0}))
else
  warn "pnpm 未安装，跳过"
fi

# =============================================================================
#  7. Cargo (Rust)
# =============================================================================
section "7/9  Cargo 缓存"
CARGO_REGISTRY="$HOME/.cargo/registry"
CARGO_GIT="$HOME/.cargo/git"

if command -v cargo &>/dev/null; then
  clean_path "$CARGO_REGISTRY/src"
  clean_path "$CARGO_REGISTRY/cache"
  clean_path "$CARGO_GIT/checkouts"
  echo -e "  ${YELLOW}[提示]${RESET} 各项目 target/ 目录请手动在项目内执行 cargo clean"
else
  warn "cargo 未安装，跳过"
fi

# =============================================================================
#  8. Docker (容器镜像与构建缓存)
# =============================================================================
section "8/9  Docker 清理"
if command -v docker &>/dev/null; then
  info "当前 Docker 占用情况:"
  docker system df | grep -E "Images|Containers|Volumes" || true

  echo -ne "  ${YELLOW}是否执行 docker system prune？这将删除所有停止的容器及未使用的镜像和卷。[y/N]${RESET} "
  read -r yn
  if [[ "${yn,,}" == "y" ]]; then
    info "正在清理 Docker 资源..."
    output=$(docker system prune -f --volumes | grep "Total reclaimed space:" || echo "Total reclaimed space: 0B")
    
    # 提取数值并换算为 MB
    reclaimed=$(echo "$output" | awk '{print $NF}')
    val=$(echo "$reclaimed" | grep -oP '[\d.]+' || echo "0")
    unit=$(echo "$reclaimed" | grep -oP '[a-zA-Z]+' || echo "B")
    
    case "${unit^^}" in
      GB) mb_val=$(echo "$val" | awk '{print int($1 * 1024)}') ;;
      MB) mb_val=$(echo "$val" | awk '{print int($1)}') ;;
      KB) mb_val=1 ;;
      *)  mb_val=0 ;;
    esac
    
    FREED=$((FREED + mb_val))
    ok "Docker 清理完成 ($output)"
  else
    warn "跳过 Docker 清理"
  fi
else
  warn "docker 未安装，跳过"
fi

# =============================================================================
#  9. Flatpak (残留运行时)
# =============================================================================
section "9/9  Flatpak 清理"
if command -v flatpak &>/dev/null; then
  info "卸载不再需要的 Flatpak 运行时..."
  BEFORE_FP=$(dir_size_mb /var/lib/flatpak)
  flatpak uninstall --unused -y
  AFTER_FP=$(dir_size_mb /var/lib/flatpak)
  FP_FREED=$((BEFORE_FP - AFTER_FP))
  FREED=$((FREED + (FP_FREED > 0 ? FP_FREED : 0)))
  ok "Flatpak 清理完成"
else
  warn "flatpak 未安装，跳过"
fi

# =============================================================================
#  额外：系统级通用清理
# =============================================================================
section "额外  系统通用清理"

# Thumbnails & Trash
clean_dir "$HOME/.cache/thumbnails"
info "清空回收站..."
if command -v gio &>/dev/null; then
  gio trash --empty 2>/dev/null && ok "回收站已清空"
else
  clean_dir "$HOME/.local/share/Trash/files"
fi

# journalctl 日志
info "压缩 systemd journal 日志 (保留 3 天)..."
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
echo ""