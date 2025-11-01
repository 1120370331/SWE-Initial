# repo-guidelines 记忆目录

该模块沉淀仓库操作规范，确保协作代理能够快速对齐工作方式与交接要求。

## 模块使命
集中记录仓库级别的作业约定，包含记忆文件维护流程、开发规范与日常例行动作，降低新人导入与交接成本。

## 快速导航
- [产品逻辑（PRD）](PRD.md)
- 功能文档：
  - [FUNCTION-MEMORIES-GOVERNANCE.md](FUNCTION-MEMORIES-GOVERNANCE.md) — 记忆文件维护与更新流程
  - [FUNCTION-MIRROR-HOOK.md](FUNCTION-MIRROR-HOOK.md) — 镜像文件自动同步钩子说明

## 常用脚本
- 记忆速查（Unix）：`sh .memories/scripts/memories-lookup.sh <模块目录名> [关键字...]`（`--list-modules` 可列出模块，缺少 module 参数将报错）
- 记忆速查（Windows）：`.memories\scripts\memories-lookup.cmd <模块目录名> [关键字...]`（同样要求显式传入模块名）

## 目录结构
```
memories/modules/repo-guidelines/
|-- README.md
|-- PRD.md
`-- FUNCTION-MEMORIES-GOVERNANCE.md
```

## 维护约定
- **负责人**：@rog
- **使用频率**：高
- **依赖模块**：无

## 最近更新
- 2025-11-01：初始化模块并更新 AGENTS.md 记忆说明 — @codex

## 待办与风险
- [ ] 持续补充其余仓库规范的 FUNCTION 文档
- ⚠️ 若 AGENTS.md 或流程调整未同步此处，将造成信息漂移
