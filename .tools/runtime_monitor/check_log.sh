#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$TOOLS_ROOT/.." && pwd)"
LOGS_ROOT="${RAPID_LOGS_ROOT:-"$SCRIPT_DIR/logs"}"

COLOR_YELLOW=$'\033[33;1m'
COLOR_RESET=$'\033[0m'

SERVICE=""
DATE_SELECTOR="today"
TAIL_LINES=20
START_LINE=""
END_LINE=""
KEYWORDS=()
REGEX=""
PLAIN_OUTPUT=0
OUTPUT_PATH=""
FORCE_WRITE=0

error() {
  echo "错误：$*" >&2
  exit 1
}

warn() {
  echo "提示：$*" >&2
}

show_usage() {
  cat <<'EOF'
用法：check_log.sh --service <name> [选项]

必选：
  --service, -s <name>    服务名，映射到 logs/<service>/ 目录

可选：
  --date, -d <selector>   日期（YYYY-MM-DD / today / yesterday / d<N> / d-<N>），默认 today
  --tail, -t <n>          最末行窗口（10-500），与 --start/--end 同时指定时忽略，默认 20
  --start <line>          起始行（正整数），可与 --end 配合
  --end <line>            结束行（正整数），可与 --start 配合
  --keyword, -k <text>    关键词过滤，可多次传入，AND 逻辑
  --regex, -r <pattern>   正则过滤，与 --keyword 互斥（正则优先）
  --plain                 关闭彩色高亮
  --output <path>         将结果写入文件路径（自动创建目录）
  --force                 允许覆盖已存在的 --output 文件
  --help, -h              显示帮助
EOF
}

DATE_BIN="$(command -v gdate 2>/dev/null || command -v date)"

current_date() {
  "$DATE_BIN" +%Y-%m-%d
}

date_offset() {
  local delta="$1"
  local sign
  if [[ "$delta" =~ ^-?[0-9]+$ ]]; then
    if (( delta >= 0 )); then
      sign="+${delta}"
    else
      sign="${delta}"
    fi
  else
    return 1
  fi

  if "$DATE_BIN" -d "${sign} day" +%Y-%m-%d >/dev/null 2>&1; then
    "$DATE_BIN" -d "${sign} day" +%Y-%m-%d
    return 0
  fi

  local vflag
  if (( delta >= 0 )); then
    vflag="+${delta}d"
  else
    vflag="${delta}d"
  fi
  if "$DATE_BIN" -v"${vflag}" +%Y-%m-%d >/dev/null 2>&1; then
    "$DATE_BIN" -v"${vflag}" +%Y-%m-%d
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$delta" <<'PY' || return 1
import sys
from datetime import date, timedelta

try:
    delta = int(sys.argv[1])
except (IndexError, ValueError):
    sys.exit(1)
print((date.today() + timedelta(days=delta)).isoformat())
PY
    return 0
  fi

  return 1
}

parse_date_selector() {
  local selector="$1"
  if [[ -z "$selector" || "$selector" == "today" ]]; then
    current_date
    return 0
  fi
  if [[ "$selector" == "yesterday" ]]; then
    date_offset -1
    return 0
  fi
  if [[ "$selector" =~ ^d-?([0-9]+)$ ]]; then
    local offset="${BASH_REMATCH[1]}"
    if [[ -z "$offset" ]]; then
      current_date
    else
      date_offset "-$offset"
    fi
    return 0
  fi
  if [[ "$selector" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "$selector"
    return 0
  fi
  error "无法解析日期参数：$selector"
}

list_services() {
  if [[ ! -d "$LOGS_ROOT" ]]; then
    return
  fi
  ls -1 "$LOGS_ROOT" 2>/dev/null | while read -r entry; do
    [[ -d "$LOGS_ROOT/$entry" ]] && [[ "$entry" != .* ]] && echo "$entry"
  done
}

lookup_index_file() {
  local service_dir="$1"
  local target_date="$2"
  local index_file="$service_dir/index.json"
  [[ -f "$index_file" ]] || return 1
  while IFS= read -r line; do
    if [[ "$line" =~ \"([0-9]{4}-[0-9]{2}-[0-9]{2})\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"
      if [[ "$key" == "$target_date" ]]; then
        printf '%s\n' "$service_dir/$value"
        return 0
      fi
    fi
  done <"$index_file"
  return 1
}

collect_known_dates() {
  local service_dir="$1"
  local tmp
  tmp="$(mktemp)"
  if [[ -f "$service_dir/index.json" ]]; then
    while IFS= read -r line; do
      if [[ "$line" =~ \"([0-9]{4}-[0-9]{2}-[0-9]{2})\" ]]; then
        echo "${BASH_REMATCH[1]}"
      fi
    done <"$service_dir/index.json" >>"$tmp"
  fi
  ls -1 "$service_dir" 2>/dev/null | while read -r entry; do
    [[ "$entry" == "index.json" ]] && continue
    if [[ "$entry" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
      echo "${BASH_REMATCH[1]}"
    fi
  done >>"$tmp"
  sort -u "$tmp"
  rm -f "$tmp"
}

resolve_log_path() {
  local service="$1"
  local date_token="$2"
  local service_dir="$LOGS_ROOT/$service"
  local expected="$service_dir/${date_token}.log"
  if [[ -f "$expected" ]]; then
    printf '%s\n' "$expected"
    return 0
  fi
  local mapped
  if mapped="$(lookup_index_file "$service_dir" "$date_token")"; then
    if [[ -f "$mapped" ]]; then
      printf '%s\n' "$mapped"
      return 0
    fi
  fi
  while IFS= read -r entry; do
    [[ "$entry" == "index.json" ]] && continue
    local path="$service_dir/$entry"
    [[ -f "$path" ]] || continue
    if [[ "$entry" == *"$date_token"* ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done < <(ls -1t "$service_dir" 2>/dev/null)
  return 1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --service|-s)
        [[ $# -ge 2 ]] || error "--service 需要参数"
        SERVICE="$2"
        shift 2
        ;;
      --date|-d)
        [[ $# -ge 2 ]] || error "--date 需要参数"
        DATE_SELECTOR="$2"
        shift 2
        ;;
      --tail|-t)
        [[ $# -ge 2 ]] || error "--tail 需要参数"
        TAIL_LINES="$2"
        shift 2
        ;;
      --start)
        [[ $# -ge 2 ]] || error "--start 需要参数"
        START_LINE="$2"
        shift 2
        ;;
      --end)
        [[ $# -ge 2 ]] || error "--end 需要参数"
        END_LINE="$2"
        shift 2
        ;;
      --keyword|-k)
        [[ $# -ge 2 ]] || error "--keyword 需要参数"
        KEYWORDS+=("$2")
        shift 2
        ;;
      --regex|-r)
        [[ $# -ge 2 ]] || error "--regex 需要参数"
        REGEX="$2"
        shift 2
        ;;
      --plain)
        PLAIN_OUTPUT=1
        shift
        ;;
      --output)
        [[ $# -ge 2 ]] || error "--output 需要参数"
        OUTPUT_PATH="$2"
        shift 2
        ;;
      --force)
        FORCE_WRITE=1
        shift
        ;;
      --help|-h)
        show_usage
        exit 0
        ;;
      --version)
        echo "check_log.sh 0.1.0"
        exit 0
        ;;
      --*)
        error "未知参数：$1"
        ;;
      *)
        error "未知位置参数：$1"
        ;;
    esac
  done
}

validate_args() {
  [[ -n "$SERVICE" ]] || { show_usage >&2; error "必须提供 --service"; }
  if ! [[ "$TAIL_LINES" =~ ^[0-9]+$ ]]; then
    error "--tail 需为整数"
  fi
  if (( TAIL_LINES < 10 || TAIL_LINES > 500 )); then
    error "--tail 范围需在 10-500 之间"
  fi
  if [[ -n "$START_LINE" && ! "$START_LINE" =~ ^[0-9]+$ ]]; then
    error "--start 需为正整数"
  fi
  if [[ -n "$END_LINE" && ! "$END_LINE" =~ ^[0-9]+$ ]]; then
    error "--end 需为正整数"
  fi
  if [[ -n "$OUTPUT_PATH" && -e "$OUTPUT_PATH" && "$FORCE_WRITE" -ne 1 ]]; then
    error "输出文件已存在：$OUTPUT_PATH（使用 --force 覆盖）"
  fi
}

parse_args "$@"
validate_args

if [[ -n "$REGEX" && "${#KEYWORDS[@]}" -gt 0 ]]; then
  warn "同时传入关键词与正则，将优先使用正则。"
  KEYWORDS=()
fi

SERVICE_DIR="$LOGS_ROOT/$SERVICE"
if [[ ! -d "$SERVICE_DIR" ]]; then
  available="$(list_services | tr '\n' ',' | sed 's/,$//')"
  [[ -n "$available" ]] || available="无"
  error "服务 \`$SERVICE\` 缺少日志目录：$SERVICE_DIR。当前可用服务：$available"
fi

TARGET_DATE="$(parse_date_selector "$DATE_SELECTOR")" || error "无法解析日期参数：$DATE_SELECTOR"

LOG_FILE="$(resolve_log_path "$SERVICE" "$TARGET_DATE")" || {
  known="$(collect_known_dates "$SERVICE_DIR" | tail -n 7 | tr '\n' ',' | sed 's/,$//')"
  [[ -n "$known" ]] || known="无可用日期"
  error "未找到 $SERVICE 在 $TARGET_DATE 的日志文件。可用日期：$known"
}

if [[ ! -f "$LOG_FILE" ]]; then
  error "日志文件不存在：$LOG_FILE"
fi

TOTAL_LINES=$(wc -l <"$LOG_FILE")
TOTAL_LINES=${TOTAL_LINES//[[:space:]]/}
if [[ -z "$TOTAL_LINES" ]]; then
  TOTAL_LINES=0
fi

if (( TOTAL_LINES == 0 )); then
  warn "目标日志为空：$LOG_FILE"
fi

calc_lines() {
  local start="$1"
  local end="$2"
  local tail="$3"
  local total="$4"
  local s="$start"
  local e="$end"

  if [[ -z "$s" && -z "$e" ]]; then
    s=$(( total - tail + 1 ))
    if (( s < 1 )); then
      s=1
    fi
    e=$total
  else
    if [[ -n "$s" && "$s" -lt 1 ]]; then
      s=1
    fi
    if [[ -n "$e" && "$e" -lt 1 ]]; then
      e=1
    fi
    if [[ -z "$s" ]]; then
      s=$(( e - tail + 1 ))
      if (( s < 1 )); then
        s=1
      fi
    fi
    if [[ -z "$e" ]]; then
      e=$(( s + tail - 1 ))
      if (( e > total )); then
        e=$total
      fi
    fi
  fi

  if (( e < s )); then
    warn "结束行小于起始行，已自动调整。"
    local tmp="$s"
    s="$e"
    e="$tmp"
  fi

  if (( s < 1 )); then
    s=1
  fi
  if (( e > total )); then
    e=$total
  fi

  echo "$s:$e"
}

RANGE="$(calc_lines "$START_LINE" "$END_LINE" "$TAIL_LINES" "$TOTAL_LINES")"
START_ACTUAL="${RANGE%%:*}"
END_ACTUAL="${RANGE##*:}"

KW_JOIN=""
if [[ "${#KEYWORDS[@]}" -gt 0 ]]; then
  for kw in "${KEYWORDS[@]}"; do
    if [[ -n "$KW_JOIN" ]]; then
      KW_JOIN+=$'\034'
    fi
    KW_JOIN+="$kw"
  done
fi

HIGHLIGHT=1
if (( PLAIN_OUTPUT == 1 )) || [[ -n "$OUTPUT_PATH" ]] || [[ "${#KEYWORDS[@]}" -eq 0 ]] || [[ -n "$REGEX" ]]; then
  HIGHLIGHT=0
fi

AWK_SCRIPT='
function escape_regex(text,   result, i, c) {
  result = ""
  for (i = 1; i <= length(text); i++) {
    c = substr(text, i, 1)
    if (c ~ /[][(){}.*+?^$|\\]/) {
      result = result "\\" c
    } else {
      result = result c
    }
  }
  return result
}
BEGIN {
  raw_len = split(kwlist, raw, "\034")
  kwcount = 0
  for (i = 1; i <= raw_len; i++) {
    if (raw[i] != "") {
      kw[++kwcount] = raw[i]
    }
  }
}
NR >= start && NR <= finish {
  keep = 1
  if (regex != "") {
    if ($0 !~ regex) {
      keep = 0
    }
  } else if (kwcount > 0) {
    for (i = 1; i <= kwcount; i++) {
      if (index($0, kw[i]) == 0) {
        keep = 0
        break
      }
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

mapfile -t OUTPUT_LINES < <(awk \
  -v start="$START_ACTUAL" \
  -v finish="$END_ACTUAL" \
  -v kwlist="$KW_JOIN" \
  -v regex="$REGEX" \
  -v highlight="$HIGHLIGHT" \
  -v color="$COLOR_YELLOW" \
  -v reset="$COLOR_RESET" \
  "$AWK_SCRIPT" "$LOG_FILE")

if [[ -n "$OUTPUT_PATH" ]]; then
  mkdir -p "$(dirname "$OUTPUT_PATH")"
  {
    for line in "${OUTPUT_LINES[@]}"; do
      clean="${line//$COLOR_YELLOW/}"
      clean="${clean//$COLOR_RESET/}"
      printf '%s\n' "$clean"
    done
  } >"$OUTPUT_PATH"
fi

if [[ "${#OUTPUT_LINES[@]}" -eq 0 ]]; then
  warn "当前筛选条件未匹配任何内容。"
else
  for line in "${OUTPUT_LINES[@]}"; do
    printf '%s\n' "$line"
  done
fi

exit 0
