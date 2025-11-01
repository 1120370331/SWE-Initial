#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$TOOLS_ROOT/.." && pwd)"
LOGS_ROOT="${RAPID_LOGS_ROOT:-"$SCRIPT_DIR/logs"}"

DATE_BIN="$(command -v gdate 2>/dev/null || command -v date)"

SERVICES=()
CLEAR_MODE=0
ARCHIVE_TARGET=""
BEFORE_SELECTOR=""
INCLUDE_LATEST=0
MAX_SIZE_THRESHOLD=""
KEEP_LATEST=1
RANGE_FROM=""
RANGE_TO=""
APPEND_MODE=0
DRY_RUN=0

error() {
  echo "错误：$*" >&2
  exit 1
}

warn() {
  echo "提示：$*" >&2
}

show_usage() {
  cat <<'EOF'
用法：manage_log.sh --service <name> [选项]

必选：
  --service, -s <name>    目标服务名，可多次传入

操作模式：
  --clear                 启用清理模式
  --zip <archive>         启用归档模式（zip 文件路径）

常用选项：
  --before, -b <selector> 清理早于指定日期的日志（YYYY-MM-DD / today / dN / d-<N>）
  --using, -u             清理时包含当前最新日志
  --max-size, -m <size>   仅处理大于指定体积的文件（示例：30KB、100MB）
  --keep-latest, -k <n>   每个服务至少保留的最新日志数量（默认 1）
  --from <date>           归档起始日期（默认 d7）
  --to <date>             归档结束日期（默认 today）
  --append                归档时追加写入已存在 zip
  --dry-run               仅输出计划操作，不执行删除/写入
  --help, -h              显示帮助
EOF
}

current_date() {
  "$DATE_BIN" +%Y-%m-%d
}

date_offset() {
  local delta="$1"
  local sign
  if (( delta >= 0 )); then
    sign="+${delta}"
  else
    sign="${delta}"
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
    date_offset "-$offset"
    return 0
  fi
  if [[ "$selector" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "$selector"
    return 0
  fi
  error "无法解析日期参数：$selector"
}

human_size() {
  local bytes="$1"
  local units=(B KB MB GB TB)
  local value="$bytes"
  local i=0
  while (( value >= 1024 && i < ${#units[@]} - 1 )); do
    value=$(( (value * 10) / 1024 ))
    value=$(( value ))
    i=$(( i + 1 ))
  done
  if (( i == 0 )); then
    printf "%d%s" "$bytes" "${units[i]}"
  else
    printf "%d.%01d%s" $(( value / 10 )) $(( value % 10 )) "${units[i]}"
  fi
}

parse_size_threshold() {
  local input="$1"
  if [[ "$input" =~ ^([0-9]+)([KkMmGgTt]?)[Bb]$ ]]; then
    local number="${BASH_REMATCH[1]}"
    local unit="${BASH_REMATCH[2]}"
    local multiplier=1
    case "${unit^^}" in
      "") multiplier=1 ;;
      "K") multiplier=1024 ;;
      "M") multiplier=$((1024**2)) ;;
      "G") multiplier=$((1024**3)) ;;
      "T") multiplier=$((1024**4)) ;;
      *) error "未知体积单位：$unit" ;;
    esac
    echo $(( number * multiplier ))
  else
    error "体积阈值无法解析：$input（示例：30KB、100MB）"
  fi
}

list_services() {
  if [[ ! -d "$LOGS_ROOT" ]]; then
    return
  fi
  ls -1 "$LOGS_ROOT" 2>/dev/null | while read -r entry; do
    [[ -d "$LOGS_ROOT/$entry" ]] && [[ "$entry" != .* ]] && echo "$entry"
  done
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --service|-s)
        [[ $# -ge 2 ]] || error "--service 需要参数"
        SERVICES+=("$2")
        shift 2
        ;;
      --clear)
        CLEAR_MODE=1
        shift
        ;;
      --zip)
        [[ $# -ge 2 ]] || error "--zip 需要参数"
        ARCHIVE_TARGET="$2"
        shift 2
        ;;
      --before|-b)
        [[ $# -ge 2 ]] || error "--before 需要参数"
        BEFORE_SELECTOR="$2"
        shift 2
        ;;
      --using|-u)
        INCLUDE_LATEST=1
        shift
        ;;
      --max-size|-m)
        [[ $# -ge 2 ]] || error "--max-size 需要参数"
        MAX_SIZE_THRESHOLD="$2"
        shift 2
        ;;
      --keep-latest|-k)
        [[ $# -ge 2 ]] || error "--keep-latest 需要参数"
        KEEP_LATEST="$2"
        shift 2
        ;;
      --from)
        [[ $# -ge 2 ]] || error "--from 需要参数"
        RANGE_FROM="$2"
        shift 2
        ;;
      --to)
        [[ $# -ge 2 ]] || error "--to 需要参数"
        RANGE_TO="$2"
        shift 2
        ;;
      --append)
        APPEND_MODE=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --help|-h)
        show_usage
        exit 0
        ;;
      --version)
        echo "manage_log.sh 0.1.0"
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

parse_args "$@"

if [[ "${#SERVICES[@]}" -eq 0 ]]; then
  show_usage >&2
  error "必须至少指定一个 --service"
fi

if (( CLEAR_MODE == 0 && "${ARCHIVE_TARGET:-}" == "" )); then
  error "请至少指定 --clear 或 --zip 之一"
fi

if ! [[ "$KEEP_LATEST" =~ ^[0-9]+$ ]]; then
  error "--keep-latest 需为非负整数"
fi

SIZE_THRESHOLD=""
if [[ -n "$MAX_SIZE_THRESHOLD" ]]; then
  SIZE_THRESHOLD="$(parse_size_threshold "$MAX_SIZE_THRESHOLD")"
fi

BEFORE_DATE=""
if [[ -n "$BEFORE_SELECTOR" ]]; then
  BEFORE_DATE="$(parse_date_selector "$BEFORE_SELECTOR")" || exit 1
fi

if (( KEEP_LATEST < 0 )); then
  error "--keep-latest 需为非负整数"
fi

declare -A SERVICE_DIRS
for svc in "${SERVICES[@]}"; do
  SERVICE_DIRS["$svc"]="$LOGS_ROOT/$svc"
  if [[ ! -d "${SERVICE_DIRS[$svc]}" ]]; then
    available="$(list_services | tr '\n' ',' | sed 's/,$//')"
    [[ -n "$available" ]] || available="无"
    error "服务 \`$svc\` 缺少日志目录：${SERVICE_DIRS[$svc]}。当前可用服务：$available"
  fi
done

file_size_bytes() {
  local path="$1"
  if stat -f %z "$path" >/dev/null 2>&1; then
    stat -f %z "$path"
  else
    stat -c %s "$path"
  fi
}

file_mtime_epoch() {
  local path="$1"
  if stat -f %m "$path" >/dev/null 2>&1; then
    stat -f %m "$path"
  else
    stat -c %Y "$path"
  fi
}

file_mtime_iso() {
  local path="$1"
  if stat -f '%Sm' -t '%Y-%m-%d' "$path" >/dev/null 2>&1; then
    stat -f '%Sm' -t '%Y-%m-%d' "$path"
    return
  fi
  if stat -c %y "$path" >/dev/null 2>&1; then
    stat -c %y "$path" | cut -d' ' -f1
    return
  fi
  local epoch
  epoch="$(file_mtime_epoch "$path")"
  if "$DATE_BIN" -d "@$epoch" +%Y-%m-%d >/dev/null 2>&1; then
    "$DATE_BIN" -d "@$epoch" +%Y-%m-%d
    return
  fi
  if "$DATE_BIN" -r "$epoch" +%Y-%m-%d >/dev/null 2>&1; then
    "$DATE_BIN" -r "$epoch" +%Y-%m-%d
    return
  fi
  echo "$(current_date)"
}

file_date_token() {
  local path="$1"
  local name="${path##*/}"
  if [[ "$name" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    file_mtime_iso "$path"
  fi
}

gather_candidates() {
  local service="$1"
  local -n ref="$2"
  ref=()
  local dir="${SERVICE_DIRS[$service]}"
  while IFS= read -r entry; do
    local path="$dir/$entry"
    [[ -f "$path" ]] || continue
    [[ "$entry" == "index.json" ]] && continue
    ref+=("$path")
  done < <(ls -1t "$dir" 2>/dev/null)
}

parse_archive_path() {
  local raw="$1"
  local value="$raw"
  if [[ "$value" != *.* ]]; then
    value="${value}.zip"
  fi
  if [[ "$value" == /* ]]; then
    echo "$value"
  elif [[ "$value" == *"/"* ]]; then
    echo "$PROJECT_ROOT/$value"
  else
    echo "$LOGS_ROOT/archive/$value"
  fi
}

ensure_zip_available() {
  if ! command -v zip >/dev/null 2>&1; then
    error "系统缺少 zip 命令，请安装 zip 或手动归档。"
  fi
}

should_delete_file() {
  local path="$1"
  local file_date="$2"
  if [[ -n "$BEFORE_DATE" ]]; then
    if [[ "${file_date//-/}" -ge "${BEFORE_DATE//-/}" ]]; then
      return 1
    fi
  fi
  if [[ -n "$SIZE_THRESHOLD" ]]; then
    local size
    size="$(file_size_bytes "$path")"
    if (( size < SIZE_THRESHOLD )); then
      return 1
    fi
  fi
  return 0
}

select_clear_set() {
  local service="$1"
  local -n ref="$2"
  local -n selection="$3"
  selection=()
  local protect="$KEEP_LATEST"
  if (( INCLUDE_LATEST == 0 )); then
    if (( protect < 1 )); then
      protect=1
    fi
  fi
  local idx=0
  for path in "${ref[@]}"; do
    if (( idx < protect )); then
      idx=$(( idx + 1 ))
      continue
    fi
    local token
    token="$(file_date_token "$path")"
    if should_delete_file "$path" "$token"; then
      selection+=("$path")
    fi
    idx=$(( idx + 1 ))
  done
}

collect_zip_targets() {
  local service="$1"
  local -n ref="$2"
  local -n out="$3"
  local start="$4"
  local end="$5"
  out=()
  local start_key="${start//-/}"
  local end_key="${end//-/}"
  for path in "${ref[@]}"; do
    local token
    token="$(file_date_token "$path")"
    local key="${token//-/}"
    if [[ "$key" < "$start_key" || "$key" > "$end_key" ]]; then
      continue
    fi
    out+=("$path")
  done
}

RANGE_FROM="${RANGE_FROM:-d7}"
RANGE_TO="${RANGE_TO:-today}"

ARCHIVE_PATH=""
START_DATE=""
END_DATE=""
if [[ -n "$ARCHIVE_TARGET" ]]; then
  if (( DRY_RUN == 0 )); then
    ensure_zip_available
  fi
  START_DATE="$(parse_date_selector "$RANGE_FROM")" || exit 1
  END_DATE="$(parse_date_selector "$RANGE_TO")" || exit 1
  if [[ "${START_DATE//-/}" -gt "${END_DATE//-/}" ]]; then
    warn "归档日期区间已自动对调。"
    local tmp="$START_DATE"
    START_DATE="$END_DATE"
    END_DATE="$tmp"
  fi
  ARCHIVE_PATH="$(parse_archive_path "$ARCHIVE_TARGET")"
fi

TOTAL_REMOVED=0
TOTAL_BYTES=0

declare -a ZIP_ENTRIES=()

if [[ -n "$ARCHIVE_PATH" ]]; then
  for svc in "${SERVICES[@]}"; do
    declare -a FILES=()
    gather_candidates "$svc" FILES
    declare -a SELECTED=()
    collect_zip_targets "$svc" FILES SELECTED "$START_DATE" "$END_DATE"
    for path in "${SELECTED[@]}"; do
      local name="${path##*/}"
      ZIP_ENTRIES+=("$svc|$name|$path")
    done
  done

  if [[ "${#ZIP_ENTRIES[@]}" -eq 0 ]]; then
    warn "归档条件未匹配任何文件。"
  else
    for entry in "${ZIP_ENTRIES[@]}"; do
      IFS='|' read -r svc name path <<<"$entry"
      echo "[zip] $(basename "$ARCHIVE_PATH") <= $svc/$name"
    done
    if (( DRY_RUN == 0 )); then
      mkdir -p "$(dirname "$ARCHIVE_PATH")"
      if (( APPEND_MODE == 0 )); then
        rm -f "$ARCHIVE_PATH"
      fi
      (
        cd "$LOGS_ROOT" || exit 1
        declare -a REL_PATHS=()
        for entry in "${ZIP_ENTRIES[@]}"; do
          IFS='|' read -r svc name path <<<"$entry"
          REL_PATHS+=("$svc/$name")
        done
        if (( APPEND_MODE == 1 )); then
          zip -qru "$ARCHIVE_PATH" "${REL_PATHS[@]}"
        else
          zip -qr "$ARCHIVE_PATH" "${REL_PATHS[@]}"
        fi
      )
    fi
  fi
fi

if (( CLEAR_MODE == 1 )); then
  for svc in "${SERVICES[@]}"; do
    declare -a FILES=()
    gather_candidates "$svc" FILES
    declare -a TO_DELETE=()
    select_clear_set "$svc" FILES TO_DELETE
    for path in "${TO_DELETE[@]}"; do
      size="$(file_size_bytes "$path")"
      echo "[clear] $svc -> ${path##*/} ($(human_size "$size"))"
      if (( DRY_RUN == 0 )); then
        rm -f "$path"
      fi
      TOTAL_REMOVED=$(( TOTAL_REMOVED + 1 ))
      TOTAL_BYTES=$(( TOTAL_BYTES + size ))
    done
  done
  if (( TOTAL_REMOVED == 0 )); then
    warn "没有文件符合清理条件。"
  else
    echo "清理完成，共删除 $TOTAL_REMOVED 个文件，释放 $(human_size "$TOTAL_BYTES")。"
  fi
fi

exit 0
