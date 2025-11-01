# Rapid Monitoring Tool

轻量级日志检索与维护工具，帮助研发、测试与运维在本地或 CI 环境中统一查看、归档及清理服务日志。脚本同时提供 Bash 与 PowerShell 版本，默认读取仓库内的示例日志，也可通过环境变量指向自定义目录。

## 使用教程
1. **准备环境**：确保 Bash 环境具备 `awk`、`zip` 命令；在 Windows 上通过 `.cmd` 入口自动调用 PowerShell。若日志存放在其他路径，可先设置 `RAPID_LOGS_ROOT`（Bash：`export RAPID_LOGS_ROOT=/var/log/custom`，Windows：`set RAPID_LOGS_ROOT=D:\logs`）。
2. **快速检索日志**：执行 `./.tools/runtime_monitor/check_log.sh --service <name> --date today --tail 20` 查看尾部片段；可叠加 `--keyword` / `--regex` 过滤、或用 `--start` / `--end` 指定行区间。Windows 使用 `.\.tools\runtime_monitor\check_log.cmd` 参数保持一致。
3. **归档或清理**：使用 `./.tools/runtime_monitor/manage_log.sh --service <name> --zip weekly-bundle --from d7 --to today --dry-run` 先预览打包内容，再去掉 `--dry-run` 实际写入；若需清理则改用 `--clear --before d30 --keep-latest 1 --max-size 50MB`。建议每次真实执行前先干跑确认。
4. **查看输出**：脚本会在终端显示命中行（带行号）或计划操作列表，同时可通过 `--output`（check_log）与 `--append`（manage_log）定制落盘行为。

## 目录结构
```
.tools/runtime_monitor/
├── check_log.sh / check_log.cmd        # 日志检索脚本（Bash / Cmd）
├── manage_log.sh / manage_log.cmd      # 日志清理 + 归档脚本
├── scripts/                            # PowerShell 实现，供 CMD 入口调用
└── logs/                               # 默认日志根目录（示例：service-a、service-b）
```

所有脚本默认在仓库内的 `.tools/runtime_monitor/logs/<service>/` 查找日志，支持通过环境变量 `RAPID_LOGS_ROOT` 覆盖。例如：
```powershell
set RAPID_LOGS_ROOT=D:\shared\logs
.\.tools\runtime_monitor\check_log.cmd --service api-gateway
```
或在 Bash 中：
```bash
RAPID_LOGS_ROOT=/var/logs ./tools/runtime_monitor/check_log.sh --service api-gateway
```

## check_log 使用指南
读取单个服务日志片段，默认输出尾部 20 行。

常用参数：
| 参数 | 说明 |
| --- | --- |
| `--service/-s <name>` | **必填**，服务目录名（例如 `service-a`）。 |
| `--date/-d <selector>` | 日志日期，支持 `YYYY-MM-DD`、`today`、`yesterday`、`d7`（表示 7 天前）。默认为 `today`。 |
| `--tail/-t <n>` | 尾部窗口大小（10–500），默认 20。 |
| `--start` / `--end` | 明确行区间，缺失一端时按 20 行窗口补齐。 |
| `--keyword/-k <text>` | 关键词过滤，可多次传入（AND 逻辑）。 |
| `--regex/-r <pattern>` | 正则过滤，若同时指定关键词则正则优先。 |
| `--plain` | 关闭命令行高亮（复制更友好）。 |
| `--output <path>` | 将输出写入文件，配合 `--force` 允许覆盖。 |

示例：
```powershell
.\check_log.cmd --service service-a --date 2025-11-01 --keyword ERROR --plain
```
```bash
./check_log.sh --service service-a --date 2025-11-02 --tail 50 --regex 'WARN|ERROR'
```

脚本会首先寻找 `<date>.log`，其次读取同目录的 `index.json`（键为日期、值为真实文件名），最后回退到匹配日期片段的轮转文件（`*.log.1` 等）。若服务不存在或没有对应日期，会提示可用服务 / 日期列表。

## manage_log 使用指南
负责批量清理或归档日志。两个子功能可以叠加使用：`--zip` 会在 `--clear` 之前执行，默认都是干跑之外的真实操作。

### 核心参数
| 参数 | 说明 |
| --- | --- |
| `--service/-s <name>` | **必填，可多次**，指定要处理的服务目录。 |
| `--clear` | 启用清理模式。 |
| `--zip <archive>` | 启用归档模式，支持相对/绝对路径。无扩展名时自动补 `.zip` 并写入 `logs/archive/`。 |
| `--before/-b <selector>` | 清理早于指定日期的日志（语法与 `--date` 相同）。 |
| `--using/-u` | 默认保留最近写入的文件；加上该参数则允许清理最新文件。 |
| `--keep-latest/-k <n>` | 每个服务至少保留 n 个最新日志（默认 1）。 |
| `--max-size/-m <size>` | 仅删除大于阈值的日志，支持 `KB/MB/GB` 单位。 |
| `--from` / `--to` | 归档起止日期，默认为 `d7` 与 `today`。区间顺序错误时会自动交换。 |
| `--append` | 归档时追加到已有 zip；默认重新创建。 |
| `--dry-run` | 输出拟执行的操作但不实际删除/压缩。 |

示例：
```powershell
.\manage_log.cmd --service service-b --clear --before 2025-10-25 --keep-latest 0 --using --dry-run
```
```bash
./manage_log.sh --service service-a --zip weekly-bundle --from 2025-11-01 --to 2025-11-02
```

归档会在 zip 中按 `service/file.log` 存放，默认写入 `.tools/runtime_monitor/logs/archive/weekly-bundle.zip`。传入带路径的归档名（例如 `reports/logs-2025w44.zip`）时，路径会相对仓库根目录解析；绝对路径保持原样。

## 内置示例数据
为便于快速验证，仓库内附带两个服务示例：
- `service-a`：包含 `2025-11-01.log` 与通过 `index.json` 映射的 `custom-2025-11-02.log`，适合测试关键词与日期解析。
- `service-b`：包含 3 天的批处理日志，可用于清理与归档演练。

可以直接运行：
```powershell
.\.tools\runtime_monitor\check_log.cmd --service service-a --date 2025-11-02 --tail 10 --plain
.\.tools\runtime_monitor\manage_log.cmd --service service-a --zip weekly-bundle --from 2025-11-01 --to 2025-11-02 --dry-run
```

## 日常维护建议
- **接入新服务**：在 `logs/<service>/` 下创建日志文件或软链接，并视需要更新 `index.json`（日期 → 文件名映射）。
- **批量清理前先 dry-run**：使用 `--dry-run` 核对计划删除的文件列表与体积，避免误删。
- **跨平台**：Bash 版本依赖 `awk`、`zip` 可用；Windows CMD 入口调用 PowerShell，不额外依赖第三方库。
- **自定义日志目录**：团队可以把日志挂载到共享路径，通过 `RAPID_LOGS_ROOT` 传入以复用同一套脚本。

如有新增参数或差异行为，请同步更新本 README 及 `.memories` 模块文档，方便团队成员快速上手。
