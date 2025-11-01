# FUNCTION-MEMORIES-GOVERNANCE 说明

记忆文件治理流程，确保代理在任务前后按约定读取与更新 `.memories/` 信息。

## 1. 功能概述
- **业务目标**：保持仓库的协作背景、关键决策与遗留问题在记忆目录中实时同步，降低交接成本。
- **核心入口**：`AGENTS.md` → `Memories 文件管理`
- **主要调用链**：`领取任务` → `记忆检索` → `阅读模块` → `执行开发` → `记录更新` → `维护索引`

## 2. 代码与业务流程
| 步骤 | 代码位置 | 业务说明 |
| --- | --- | --- |
| 1 | `AGENTS.md` | 代理在领取任务前阅读“Memories 文件管理”章节，确认必须执行的治理动作。 |
| 2 | `.memories/scripts/memories-lookup.sh` / `.memories/scripts/memories-lookup.cmd` | 通过 `--list-modules` 浏览目录或以关键词检索相关 FUNCTION 文档，加速定位信息。 |
| 3 | `.memories/modules/<module>/README.md` | 从模块导航获取本任务需要的 FUNCTION 文档与补充资料清单。 |
| 4 | `.memories/modules/<module>/PRD.md` | 理解业务目标、用户场景与边界条件，核对是否有新假设。 |
| 5 | `.memories/modules/<module>/FUNCTION-*.md` | 核对具体函数/脚本的实现逻辑与约束，确认与代码保持一致。 |
| 6 | `.memories/templates/module/` | 若业务扩展触发新模块，复制模板初始化 `README/PRD/FUNCTION`，再行补充内容。 |
| 7 | `.memories/modules/INDEX.md` | 任务完成后更新模块摘要与时间戳，确保团队能够快速检索最新信息。 |

### 关键代码片段
```bash
# 来自 .memories/scripts/memories-lookup.sh#L28-L58，用于列出模块并按关键字检索
list_modules() {
  if [ ! -d "$modules_dir" ]; then
    echo "Memories modules directory not found: $modules_dir" >&2
    exit 2
  fi
  find "$modules_dir" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort
}

search_memories() {
  if [ $# -eq 0 ]; then
    echo "Provide at least one keyword or use --list-modules." >&2
    usage
    exit 2
  fi

  if command -v rg >/dev/null 2>&1; then
    args=()
    for keyword in "$@"; do
      args+=("-e" "$keyword")
    done
    rg --color=always --line-number --ignore-case --fixed-strings "${args[@]}" "$modules_dir" || {
      echo "No matches." >&2
      exit 1
    }
    return
  fi

  if command -v grep >/dev/null 2>&1; then
    args=()
    for keyword in "$@"; do
      args+=("-e" "$keyword")
    done
    grep -RIn --color=always -F "${args[@]}" "$modules_dir" || {
      echo "No matches." >&2
      exit 1
    }
    return
  fi

  echo "Neither rg nor grep is available. Install one of them to use this script." >&2
  exit 2
}
```

## 3. 输入、输出与副作用
| 项目 | 描述 |
| --- | --- |
| 输入 | 已存在的记忆文档（`README.md`、`PRD.md`、`FUNCTION-*.md`）及本次任务的新增结论、数据位置。 |
| 输出 | 更新后的记忆文件，记录新的决策、假设、风险与待办事项。 |
| 副作用 | 可能新增模块或 FUNCTION 文件，并触发索引更新与后续任务引用。 |

## 4. 配置与依赖
- **配置项**：无专用配置；遵循仓库默认目录结构。
- **依赖模块/服务**：依赖 `.memories/scripts/memories-lookup.*` 用于检索，及 `.memories/templates/module/` 用于初始化。
- **性能注意**：文档操作为主，注意保持内容简明并及时提交，防止信息漂移。

## 5. 测试与验证
- **关联用例**：无自动化测试；通过自检或代码审查确认“阅读+更新”动作已完成。
- **覆盖重点**：是否在任务开始前完成阅读；是否在结束后补充关键信息或明确说明“此次无更新”。
- **手动验证**：执行 `git status` 查看 `.memories/` 目录是否存在预期的增量文件，必要时附加截图或在 PR 描述中引用差异。

## 6. 数据与风险
- **敏感信息处理**：记忆文档中禁止落地未脱敏数据；若需引用敏感信息，指向外部受控系统并说明访问方式。
- **失败路径**：若遗漏更新，需在下一次任务前补写，并在文档中标注延迟原因以提醒团队。
- **已知限制**：流程依赖人工执行，缺乏自动提醒；若多任务并行，需主动协调文档冲突。

## 7. 迭代记录
- **最近更新**：2025-11-01 — 重构模板结构并细化记忆治理步骤。
- **后续规划**：
  - [ ] 将“记忆更新”项纳入 PR 检查清单并自动提醒。
  - ❓ 是否需要为记忆模块维护额外的变更日志或审计机制？
