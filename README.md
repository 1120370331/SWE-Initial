# SWE-Initial
SWE 开发项目模板，内置记忆协作规范与常用诊断脚本，方便多代理在同一仓库中快速对齐。

## Knowledge Base `.memories/`
- **目的**：集中沉淀业务背景、产品决策与脚本实现细节，确保接手任务前后都能查阅与补充共享记忆。
- **核心结构**：
  - `modules/` 存放按 `业务-主题` 命名的记忆模块；每个模块必须维护 `README.md`（导航）、`PRD.md`（场景目标）以及一个或多个 `FUNCTION-*.md`（流程与关键代码片段）。
  - `modules/INDEX.md` 记录模块清单、负责人和更新时间，便于全局检索。
  - `templates/` 提供模块初始化模板，复制后按需填写。
  - `scripts/` 包含速查脚本，支持在命令行检索模块内容。
- **推荐流程**：
  1. 开工前执行 `.memories/scripts/memories-lookup.sh <模块目录名> [关键字...]`（或 Windows 版本 `.memories\scripts\memories-lookup.cmd ...`）快速定位资料。
  2. 先读模块 `README.md`，再查看 `PRD.md` 与相关 `FUNCTION-*.md` 核对实现约束。
  3. 收工后在对应文档补充新的决策、数据位置或遗留问题，并更新 `modules/INDEX.md`。

## Utility Scripts `.tools/`
- **目的**：收纳项目共享的辅助脚本与诊断工具，目前重点维护 `runtime_monitor/` 用于日志排查。
- **快速使用**：
  - 检索日志：`./.tools/runtime_monitor/check_log.sh --service <name> [--date today|d7|2025-11-02] [--tail 50|--start 10 --end 200] [--keyword ERROR] [--regex 'WARN|ERROR']`。Windows 可使用同目录下的 `.cmd` 版本。
  - 清理或归档：`./.tools/runtime_monitor/manage_log.sh --service <name> [--clear --before d30 --keep-latest 1 --max-size 50MB] [--zip weekly-bundle --from d7 --to today --append] [--dry-run]`，实际执行前建议加 `--dry-run` 验证计划操作。
- **环境变量**：如日志不位于仓库示例目录，设置 `RAPID_LOGS_ROOT`（Bash：`export RAPID_LOGS_ROOT=/var/log/custom`，Windows：`set RAPID_LOGS_ROOT=D:\logs`）让脚本指向真实路径。
- **使用教程**：详尽步骤与注意事项已收录在 `.tools/runtime_monitor/README.md` 的“使用教程”章节，首次接入时请完整阅读。
- 更多背景与迭代记录可在 `.memories/modules/rapid-monitoring-tool/` 中查阅。
