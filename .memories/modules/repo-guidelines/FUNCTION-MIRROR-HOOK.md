# FUNCTION-MIRROR-HOOK

## 背景
- 为保持 `AGENTS.md`、`CLAUDE.md` 及未来可能新增的镜像文档内容一致，建立预提交阶段的自动同步机制。
- 需求侧重点在于：任意成员被编辑后，其所在镜像组的其他成员应在提交前自动获得相同内容；若全组删除则全部删除，避免部分缺失。

## 实现要点
- 镜像关系集中配置在 `config/mirror_sync.conf`，每行一个镜像组，使用空格分隔仓库相对路径，允许以 `#` 开头的注释与空行：

```
# 文档镜像
AGENTS.md CLAUDE.md
```

- `scripts/mirror_sync.sh` 使用 `git status --porcelain` 捕获工作区与暂存区的变更路径，并以组内最新修改（按文件 mtime 判定）的文件作为数据源：

```sh
mtime="$(get_mtime "$file")"
if [ "$mtime" -ge "$source_mtime" ]; then
  source_file="$file"
  source_mtime="$mtime"
fi
```

- 当镜像组被触发时，脚本会覆盖其余成员并 `git add -- <path>`，因此只需维护配置即可自动保持一致；若检测到未解决的冲突（`git diff --diff-filter=U`），脚本会提前退出，避免在冲突处理中产生额外噪音。
- 对应钩子存放于 `.githooks/pre-commit`，启用一次 `git config core.hooksPath .githooks` 即可在本地激活。
- 快速安装脚本提供 `scripts/install_hooks.sh`（POSIX）与 `scripts/install-hooks.ps1`（PowerShell），便于一键设置 `core.hooksPath`，后续新增钩子直接放入 `.githooks/` 即可。

## 迭代与注意事项
- 如需新增镜像文件，只需在配置中另起一行列出镜像组，无需改动脚本，但请同步在 `.gitattributes` 中为组内的非主文件添加 `merge=ours` 以降低合并冲突。
- 对镜像组中的文件执行部分删除操作会被自动还原；若需要彻底删除，请一次性移除组内全部文件。
- 钩子依赖 POSIX `sh`、`stat`、`cmp`、`git` 等常驻工具，Windows 环境下建议通过 Git Bash 运行。
- `.gitattributes` 会让诸如 `CLAUDE.md` 这样的镜像副本在合并时默认采用当前分支版本，解决主文件冲突后重新执行提交即可自动同步副本。
