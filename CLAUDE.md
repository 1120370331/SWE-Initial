# Repository Guidelines
(本文件与CLAUDE.md永久同步)
## Memories 文件管理
`./.memories/`（下文简称 `./memories/`）存放团队共享的“记忆”资料，用于速记业务背景与开发决策。开工前先读相关模块，收工后同步更新，保持资料实时。

- **目录结构**：每个模块位于 `./memories/modules/<业务-主题>/`，命名采用小写加连字符。
- **必备文件**：
  - `README.md` — 模块导航，列出 FUNCTION 文档及其他资料。
  - `PRD.md` — 产品/业务目标、用户场景与边界假设。
  - `FUNCTION-*.md` — 单个函数、脚本或流程的说明文档，可按需创建多个。在这里，需要你结合实际的代码情况，介绍业务的实现逻辑，并嵌入关键代码片段便于速查。
- **操作流程**：
  1. 开始任务前，先阅读模块 `README.md`，再按需查看 `PRD.md` 与相关 `FUNCTION-*.md`。
  2. 任务完成后，补充新的决策、假设、数据位置或遗留问题。
  3. 新增模块时，复制 `.memories/templates/module/` 模板并填写，再在 `modules/INDEX.md` 登记。
  4. 需要速查记忆内容时，执行 `sh .memories/scripts/memories-lookup.sh <模块目录名> [关键字...]`；Windows 环境使用 `.memories\scripts\memories-lookup.cmd <模块目录名> [关键字...]`。缺少 module 参数脚本会拒绝执行，可用 `--list-modules` 查看支持的模块列表。

## Tools 开发工具
`./.tools/` 存放辅助脚本与诊断工具。例如 `runtime_monitor/` 目录下的说明可帮助排查运行时异常，使用前先阅读对应 README。

### Rapid Monitoring Tool 快速上手
- 定位日志：`.\.tools\runtime_monitor\check_log.cmd --service <name> [--date today|d7|2025-11-02] [--tail 50|--start 10 --end 200] [--keyword ERROR] [--regex 'WARN|ERROR']`；Bash 版本位于 `./.tools/runtime_monitor/check_log.sh`。
- 清理或归档：`.\.tools\runtime_monitor\manage_log.cmd --service <name> [--clear --before d30 --keep-latest 1 --max-size 50MB] [--zip weekly-bundle --from d7 --to today --append] [--dry-run]`。
- 如日志不在仓库示例目录，可先设置 `RAPID_LOGS_ROOT`（Windows：`set RAPID_LOGS_ROOT=D:\logs`，Bash：`export RAPID_LOGS_ROOT=/var/log/custom`）。
- 实际删除或打包前建议先加 `--dry-run` 核对计划操作。
## Project Structure & Module Organization
Keep reusable Python code in `src/` and expose entry points through `src/__init__.py` for clean imports. Exploratory notebooks live in `notebooks/` with numbered prefixes (for example `01-demand-baseline.ipynb`) so progress reads chronologically. Store input spreadsheets under `data/raw/` and model-ready tables in `data/processed/`; never commit personally identifiable information. Generated figures and reports belong in `reports/` to keep outputs reproducible. Place automated checks in `tests/`, mirroring the package structure to simplify discovery.

## Build, Test, and Development Commands
- `py -3 -m venv .venv` then `.\.venv\Scripts\Activate.ps1` — create and activate the local virtual environment.
- `pip install -r requirements.txt` — install pinned dependencies before running analyses.
- `python -m src.pipeline.sample_run` — example pattern for executing a scenario module.
- `pytest` — run the full test suite; add `-k keyword` to focus on a subset when iterating quickly.

## Coding Style & Naming Conventions
Format Python files with `black` (line length 100) and lint with `ruff`; run both before every push. Prefer type hints and `mypy`-clean signatures for core modules. Use snake_case for functions and variables, PascalCase for classes, and uppercase constants grouped at module tops. Name notebooks with a numeric prefix and short kebab-case slug. Document public functions with NumPy-style docstrings that call out units and assumptions.

## Testing Guidelines
Write `pytest` tests alongside the code they cover: `tests/src/feature/test_feature.py` should mirror `src/feature/module.py`. Use fixtures to load sample data from `tests/fixtures/`, keeping them small and anonymized. Target a minimum of 85% branch coverage (`pytest --cov=src --cov-branch`). Flag long-running simulations with `@pytest.mark.slow` so CI can gate them separately.

## Commit & Pull Request Guidelines
Use Conventional Commit prefixes (`feat:`, `fix:`, `docs:`, `refactor:`) followed by a concise summary, e.g., `feat: add peak-demand forecaster`. Reference related issue IDs in the body and note data sources or assumptions that drove the change. Pull requests should include a purpose-driven checklist, screenshots for UI/plot updates, and links to any notebook outputs stored in `reports/`. Request review from at least one maintainer and confirm tests and linters passed before requesting merge.

## Data & Configuration Notes
Track configuration defaults in `config/settings.yaml`; commit sanitized templates only. Push large raw datasets through the shared object store and reference them via `.dvc` or README pointers instead of committing binaries. When exporting results, include metadata (timestamp, scenario tags) in filenames such as `reports/2025-01-forecast-scenario-a.xlsx` to keep comparisons traceable.
