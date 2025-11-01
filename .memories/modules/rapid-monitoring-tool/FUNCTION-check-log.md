# FUNCTION —— check_log（Bash / PowerShell）

## 目的
为前后端及运维工程师提供快速、跨平台的日志检索能力。Bash 版本面向类 Unix 环境，CMD 入口通过 PowerShell 实现同等逻辑，参数保持一致。

## 入口文件
- `.tools/runtime_monitor/check_log.sh`
- `.tools/runtime_monitor/check_log.cmd` → `scripts/check_log.ps1`

默认日志根目录位于 `.tools/runtime_monitor/logs/<service>/`；如需变更，可在调用前设置 `RAPID_LOGS_ROOT` 环境变量。

## 核心流程
1. 解析命令行参数，强制校验 `--service`、`--tail`（10–500）并阻止未加 `--force` 的重复写文件。
2. 根据日期选择器生成目标日期（支持 `today` / `yesterday` / `d7` / `d-7` / 绝对日期）；依次尝试 `gdate`、系统 `date` 与临时 `python3` 脚本，确保跨平台解析。
3. 依次尝试定位日志文件：
   - `<logs_root>/<service>/<date>.log`
   - `index.json` 中的日期映射
   - 名称包含日期片段的轮转文件（取最近修改时间）。
4. `calc_lines` 会在 `--start/--end` 与 `--tail` 之间计算最终行窗口，自动纠正越界或反转的区间并给出提示。
5. 依次应用关键词或正则过滤，`--regex` 与 `--keyword` 同时传入时以正则为准并输出提示。
6. 控制台输出带行号的结果，必要时对关键词高亮；若提供 `--output`，同时落盘一个纯文本副本（会剥离 ANSI 颜色）。
7. 支持 `--version` 快速确认脚本版本号；PowerShell 版本保持一致行为。

## 关键代码片段
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_ROOT="${RAPID_LOGS_ROOT:-"$SCRIPT_DIR/logs"}"

resolve_log_path() {
  local service="$1" date_token="$2" service_dir="$LOGS_ROOT/$service"
  local expected="$service_dir/${date_token}.log"
  [[ -f "$expected" ]] && { printf '%s\n' "$expected"; return 0; }
  local mapped
  if mapped="$(lookup_index_file "$service_dir" "$date_token")"; then
    [[ -f "$mapped" ]] && { printf '%s\n' "$mapped"; return 0; }
  fi
  while IFS= read -r entry; do
    [[ "$entry" == "index.json" ]] && continue
    [[ -f "$service_dir/$entry" && "$entry" == *"$date_token"* ]] && {
      printf '%s\n' "$service_dir/$entry"; return 0; }
  done < <(ls -1t "$service_dir")
  return 1
}
```
PowerShell 版本的解析逻辑一致，只是使用 `Resolve-Path` 与 `.NET Regex` 实现关键词高亮。若未来需要扩展参数，优先同时改动两个入口以保持行为一致。

```bash
AWK_SCRIPT='
NR >= start && NR <= finish {
  keep = 1
  if (regex != "") {
    keep = ($0 ~ regex)
  } else if (kwcount > 0) {
    for (i = 1; i <= kwcount; i++) {
      if (index($0, kw[i]) == 0) { keep = 0; break }
    }
  }
  if (keep) {
    display = $0
    if (highlight && regex == "" && kwcount > 0) {
      for (i = 1; i <= kwcount; i++) {
        esc = escape_regex(kw[i])
        gsub(esc, color kw[i] reset, display)
      }
    }
    printf("%6d | %s\n", NR, display)
  }
}
'
```
> 核心过滤逻辑在 AWK 中完成：同一命令既不需要多次遍历文件，又能在复制输出前剥离颜色转义。

## 典型调用
```powershell
.\.tools\runtime_monitor\check_log.cmd --service service-a --date 2025-11-02 --tail 40 --regex "WARN|ERROR"
```
```bash
./.tools/runtime_monitor/check_log.sh --service service-a --keyword payment --keyword ERROR --plain
```

## 注意事项
- 同一命令若既有 `--regex` 又有 `--keyword`，会在标准错误输出提示正则优先并清空关键词数组，避免混淆。
- 当 `--start` / `--end` 颠倒或超出范围时 `calc_lines` 会自动裁剪并发出提醒，避免出现空窗口。
- 目标文件存在时必须显式传入 `--force` 才会覆盖，防止误写。
- 输出文件默认覆盖 ANSI 颜色码，如需保留可移除 `clean` 逻辑后再导出；若指定 `--plain` 或 `--output`，终端高亮也会相应关闭。
- `--version` 选项仅打印版本并退出，可用于脚本差异排查。
