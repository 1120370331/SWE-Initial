# 记忆主目录

此处存放协作所需的“记忆”资料。每次开始任务前请阅读对应模块，完成后及时补充或更新，以保持团队共享上下文的实时性。

## 使用流程
- **工作前**：通过`modules/`目录快速定位相关模块，先读模块`README.md`，再按需查看`PRD.md`与对应的`FUNCTION*.md`。
- **工作后**：更新受影响的记忆文件，记录关键决策、假设、数据位置与遗留问题。
- **速查脚本**：使用 `sh .memories/scripts/memories-lookup.sh <模块目录名> [关键字...]` 或 `.memories\scripts\memories-lookup.cmd <模块目录名> [关键字...]` 进行检索；`--list-modules` 可列出全部模块，缺少 `service` 参数时脚本会报错提示。
- **新增模块**：复制`templates/module/`下的模板，按照命名规范创建新的模块文件夹并补全字段。

## 目录约定
- `modules/`：按业务或功能维度划分的记忆模块，供日常维护与查阅。
- `templates/`：模块模板与写作指引，保证不同项目之间的一致性与可扩展性。
- `modules/INDEX.md`：维护现有模块列表、责任人及更新时间，便于全局检索。

## 命名规范
1. 模块目录采用`业务-主题`形式（示例：`demand-forecast`），使用小写加连字符。
2. 模块下必须包含：
   - `README.md`：模块导引，列出功能文档清单与快速导航。
   - `PRD.md`：业务或功能的目标、用户、场景与边界。
   - `FUNCTION-*.md`：每个函数/脚本/流程一份，文件名使用大写字母与连字符（示例：`FUNCTION-LOAD-BASELINE.md`）。
3. 补充资料（数据字典、协议等）可建立子文件夹，但需在模块`README.md`中登记链接。

## 快速开始示例（PowerShell）
```powershell
Copy-Item -Recurse templates/module modules/demand-forecast
Rename-Item modules/demand-forecast/FUNCTION.template.md FUNCTION-CALC-PEAK.md
```

复制后请逐项填写模板字段，并在`modules/INDEX.md`登记模块信息。

## 更新记录
- 2025-11-01：新增项目级`.gitignore`（@assistant）
