# cleanupsh

Ubuntu / Debian 开发环境一键缓存清理脚本。一条命令释放各语言工具链积累的缓存与临时文件，告别手动逐个清理。

## 支持的清理项

| # | 工具 | 清理内容 |
|---|------|----------|
| 1 | **APT** | 下载包缓存、孤立依赖、过期列表 |
| 2 | **uv** (Python) | uv 全局缓存目录 |
| 3 | **Go** | build cache、test cache、module cache（交互确认） |
| 4 | **Maven** (Java) | 标记文件、不完整下载；可选清理整个本地仓库（交互确认） |
| 5 | **npm** | npm cache、npx 缓存 |
| 6 | **pnpm** | content-addressable store 修剪 |
| 7 | **Cargo** (Rust) | registry 源码与 .crate 包、git checkouts |
| - | **系统** | 缩略图缓存、回收站、systemd journal 日志（保留 3 天） |

> 未安装的工具会自动跳过，不会报错。

## 快速开始

```bash
git clone https://github.com/LumiDesk/cleanupsh.git
cd cleanupsh
chmod +x cleanup.sh
./cleanup.sh
```

也可以直接下载单文件运行：

```bash
curl -fsSL https://raw.githubusercontent.com/LumiDesk/cleanupsh/main/cleanup.sh -o cleanup.sh
chmod +x cleanup.sh
./cleanup.sh
```

## 使用说明

- 以**普通用户**身份运行，脚本会在需要时自动请求 `sudo`（仅用于 APT 和 journalctl）。
- 直接以 `root` 运行会被拒绝，避免误操作。
- 对于**不可逆的高影响操作**（Go module cache、Maven 本地仓库），脚本会交互式询问确认，默认不清理。
- 执行结束后会输出本次预计释放的磁盘空间总量。

## 清理路径一览

| 工具 | 默认路径 |
|------|----------|
| APT | `/var/cache/apt/archives/` |
| uv | `$UV_CACHE_DIR` 或 `~/.cache/uv/` |
| Go build | `$(go env GOCACHE)` 或 `~/.cache/go/build/` |
| Go module | `$(go env GOMODCACHE)` 或 `~/go/pkg/mod/` |
| Maven | `~/.m2/repository/`、`~/.m2/tmp/` |
| npm | `$NPM_CONFIG_CACHE` 或 `~/.npm/` |
| pnpm | `$(pnpm store path)` 或 `~/.local/share/pnpm/store/` |
| Cargo | `~/.cargo/registry/`、`~/.cargo/git/` |
| 缩略图 | `~/.cache/thumbnails/` |
| 回收站 | `~/.local/share/Trash/` |
| Journal | systemd journal（`journalctl --vacuum-time=3d`） |

## 系统要求

- Ubuntu / Debian 系 Linux（依赖 `apt-get`）
- Bash 4.0+
- 各语言工具链按需安装，未安装则自动跳过

## 许可证

[MIT](LICENSE)
