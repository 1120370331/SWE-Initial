# FUNCTION —— manage_log（Bash / PowerShell）

## 目的
在本地或 CI 环境中统一执行日志清理与归档操作，避免人工逐个目录处理。Bash 版本和 PowerShell 版本保持参数一致，均支持 `--dry-run` 以便审核计划操作。

## 入口文件
- `.tools/runtime_monitor/manage_log.sh`
- `.tools/runtime_monitor/manage_log.cmd` → `scripts/manage_log.ps1`

默认日志根目录为 `.tools/runtime_monitor/logs/`，可通过 `RAPID_LOGS_ROOT` 环境变量覆盖。

## 核心流程
1. 解析命令行，至少要求一个 `--service`，并强制在 `--clear`、`--zip` 中选择至少一项。
2. 解析日期与体积阈值：日期语法与 `check_log` 共通（`today` / `d7` / `d-7` / 绝对日期），优先 `gdate`，回退到系统 `date` 或一次性 `python3`；尺寸解析支持 `30KB`/`3GB` 等写法并转换为字节。
3. 构造服务目录列表并校验存在性，失败时回显当前可用服务清单，避免误删。
4. **归档 (`--zip`)**
   - `collect_zip_targets` 以 `file_date_token`（文件名或修改时间）过滤日期窗口，若 `--from` / `--to` 颠倒会自动交换并提示。
   - 归档前校验 `zip` 命令可用；相对路径会解析到仓库根目录或默认的 `logs/archive/`，`--append` 时使用 `zip -qru` 保留旧内容。
   - 干跑模式只打印 `[zip]` 提示；实际执行时会在 `logs_root` 下就地 `cd`，确保打包时目录层级为 `service/file.log`。
5. **清理 (`--clear`)**
   - `select_clear_set` 会先保留 `--keep-latest` 指定数量；未传 `--using` 时进一步保护最近一份。
   - `should_delete_file` 综合 `--before`（基于 `file_date_token`）与 `--max-size` 条件，对符合条件的文件打印 `[clear] <service> -> <file> (size)`。
   - 非干跑模式下实际删除文件并累计释放空间，最后输出汇总。

## 关键代码片段（Bash）
```bash
parse_size_threshold() {
  if [[ "$1" =~ ^([0-9]+)([KkMmGgTt]?)[Bb]$ ]]; then
    local number="${BASH_REMATCH[1]}" unit="${BASH_REMATCH[2]}"
    case "${unit^^}" in
      "")  echo "$number" ;;
      "K") echo $(( number * 1024 )) ;;
      "M") echo $(( number * 1024 * 1024 )) ;;
      "G") echo $(( number * 1024 ** 3 )) ;;
      "T") echo $(( number * 1024 ** 4 )) ;;
      *)   error "未知体积单位：$unit" ;;
    esac
  else
    error "体积阈值无法解析：$1（示例：30KB、100MB）"
  fi
}

parse_archive_path() {
  local raw="$1"
  [[ "$raw" != *.* ]] && raw="${raw}.zip"
  if [[ "$raw" == /* ]]; then
    echo "$raw"
  elif [[ "$raw" == *"/"* ]]; then
    echo "$PROJECT_ROOT/$raw"
  else
    echo "$LOGS_ROOT/archive/$raw"
  fi
}

select_clear_set() {
  local service="$1"
  local -n ref="$2"
  local -n selection="$3"
  local dir="${SERVICE_DIRS[$service]}"
  local protect="$KEEP_LATEST"
  if (( INCLUDE_LATEST == 0 && protect > 0 )); then
    protect=$(( protect + 1 ))
  fi
  local idx=0
  for path in "${ref[@]}"; do
    (( idx < protect )) && { idx=$(( idx + 1 )); continue; }
    local token
    token="$(file_date_token "$path")"
    should_delete_file "$path" "$token" && selection+=("$path")
    idx=$(( idx + 1 ))
  done
}

collect_zip_targets() {
  local service="$1"
  local -n ref="$2"
  local -n out="$3"
  local start="$4" end="$5"
  local start_key="${start//-/}" end_key="${end//-/}"
  for path in "${ref[@]}"; do
    local token key
    token="$(file_date_token "$path")"
    key="${token//-/}"
    [[ "$key" < "$start_key" || "$key" > "$end_key" ]] && continue
    out+=("$path")
  done
}
```
PowerShell 版使用 `System.IO.Compression.ZipFile` 处理压缩，删除操作通过 `Remove-Item` 完成；两端均保证 `--dry-run` 只打印结果，不会触碰文件。

## 示例命令
```powershell
.\.tools\runtime_monitor\manage_log.cmd --service service-b --clear --before d10 --keep-latest 1 --dry-run
.\.tools\runtime_monitor\manage_log.cmd --service service-a --zip weekly-bundle --from 2025-11-01 --to 2025-11-02
```
```bash
./.tools/runtime_monitor/manage_log.sh --service api --service batch --clear --before 2025-10-01 --max-size 50MB
```

## 注意事项
- 未显式传入 `--dry-run` 时脚本会执行真实删除/压缩，使用前可先干跑确认。
- `--using` 仅在极端情况下允许删除最新日志；默认仍保留最近 1 份，可通过 `--keep-latest` 调整为 0。
- `--max-size` 需带单位后缀（如 `30KB`、`200MB`），否则解析会直接报错。
- `--zip` 在未提供路径分隔符时会自动落到 `logs/archive/<name>.zip`，并在追加模式下调用 `zip -qru`；
  缺少 `zip` 命令时提前失败提示安装。
- PowerShell 版本通过 `System.IO.Compression.ZipFile` 完成归档与追加，清理依赖 `Remove-Item`，行为与 Bash 版保持一致。
