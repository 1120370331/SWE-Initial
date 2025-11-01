# rapid-monitoring-tool 记忆目录

## 模块使命
沉淀“急速监控工具”的设计逻辑与运维约定，帮助前后端及其他业务开发人员在共享仓库中迅速检索、清理与归档日志，降低排障耗时与 token 成本。

## 快速导航
- [产品逻辑（PRD）](PRD.md)
- 功能文档：
  - [FUNCTION-check-log](FUNCTION-check-log.md) — 检索脚本流程与关键实现
  - [FUNCTION-manage-log](FUNCTION-manage-log.md) — 清理/归档脚本流程与关键实现

## 目录结构
```
rapid-monitoring-tool/
|-- README.md                # 工具使用说明与示例命令
|-- PRD.md                   # 业务背景、需求边界
|-- FUNCTION-check-log.md
|-- FUNCTION-manage-log.md
`-- （工具实现）../.tools/runtime_monitor/
```

## 维护约定
- **负责人**：@rog
- **使用频率**：高
- **依赖模块**：repo-guidelines

## 最近更新
- 2025-11-01：初始化模块与 PRD 草案 — @codex
- 2025-11-01：落地 Bash/CMD 脚本，补充 FUNCTION 文档与示例日志 — @codex
- 2025-11-01：完善 FUNCTION 记忆，收录日期解析、覆盖写入与归档追加等实现细节 — @codex

## 待办与风险
- [ ] 补充日志采集规范（统一外部服务落盘策略）
- ⚠️ 若新增服务未维护 `.tools/runtime_monitor/logs/<service>/index.json`，日期映射将依赖命名约定
