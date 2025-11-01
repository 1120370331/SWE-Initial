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

## Git Hooks & Mirror Sync
- **启用方式**：运行 `pwsh scripts/install-hooks.ps1`（Windows）或 `sh scripts/install_hooks.sh`（macOS/Linux）即可将 `core.hooksPath` 指向 `.githooks`；若需手动操作，可执行 `git config core.hooksPath .githooks`。
- **自动同步**：`pre-commit` 钩子会调用 `scripts/mirror_sync.sh`，对 `config/mirror_sync.conf` 中声明的镜像文件组逐一检查；任意成员更新后，钩子会以最近修改的文件为源覆盖其余成员并重新 `git add`，确保在提交前保持一致。
- **配置格式**：`config/mirror_sync.conf` 每行表示一个镜像组，使用空格分隔仓库相对路径；支持加入注释（以 `#` 开头）与空行跳过。
- **删除语义**：若组内所有文件都被删除，钩子会统一 `git add` 以记录删除；如只删除部分文件，脚本会自动还原缺失文件，避免半同步状态。
- **部署脚本**：首次克隆后执行上述脚本，后续新增的钩子拷贝至 `.githooks/` 会自动生效。

## 人类工程师使用指南
- **先读规则再派活**：本仓库的 `AGENTS.md`、`CLAUDE.md` 以及各模块记忆文件是给 AI 代理的工作约束。人类在分配任务前需快速浏览对应模块的 `README.md`、`PRD.md` 与 `FUNCTION-*.md`，确认已有约定与边界是否覆盖当前需求。
- **准备高质量指令**：向 AI 下达任务时，明确业务上下文、输入输出路径、禁止触碰的文件以及可复用脚本。引用仓库中的现有流程（如 `.memories/scripts/` 或 `scripts/` 下的工具），通过链接或路径让 AI 精确定位资料。
- **要求计划与校验**：指导 AI 在动手前产出执行计划，并在关键步骤（例如改动核心逻辑或批量文件）前停下来等待人类确认。执行后要求说明变更位置、影响范围以及验证方式。
- **同步决策与知识**：完成协作后，人工负责更新对应模块的记忆文档，记录新的假设、接口变更或遗留风险，确保下次 AI 能直接继承背景信息。
- **审阅与回归**：对 AI 提交的修改进行人工审查，必要时运行 `pytest`、专用脚本或手工验收。长周期任务应建立检查清单，确保模型升级或知识库扩写时不会出现规约偏差。
