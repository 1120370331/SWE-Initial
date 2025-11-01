# 模板使用指引

`templates/`目录提供标准化的记忆模块结构，复制后按需调整即可。建议步骤：

1. `Copy-Item -Recurse templates/module modules/<module-name>`。
2. 将`FUNCTION.template.md`复制并重命名为具体功能文件，删除未使用的占位内容。
3. 补全`README.md`与`PRD.md`中的`<< >>`占位符。
4. 在`modules/INDEX.md`登记模块，保持目录可检索。

> 如需新增模板（例如数据字典、架构图说明），在`templates/`内创建对应文件，并在本指引中补充使用说明。
