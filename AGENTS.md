# AGENTS PROMPT OF WORKSPACE

## 项目主 git 库

- `bike-hub-dev-space`：管理开发文档和资源，工作目录
- `bike-hub`：主开发仓库

## 工作空间文件目录结构

```md
dev-space   // repo: `bike-hub-dev-space`
|-docs/ // 区分与 `bike-hub` 库的文档。具有阶段性
| |-tickets/    // 未来接入敏捷开发体系后卡片本地空间
| |-tmp/    // 临时文件空间
|   |- messages.md  // 开发者消息筹备区（AI 不可直接读取）
|-repos/
| |-bh/
|   |-bike-hub/ // 本地主 git 库，主要用于预览代码，不在此进行开发
|   |-bike-hub-side-1/  // 独立 worktree，承担开发任务（一个 worktree 同时只能有一个 AGENT 负责操作）
|   |-bike-hub-side-2/  // 同上
|   |-bike-hub-side-3/  // 同上
|   |-bike-hub-side-4/  // 同上
|   |-bike-hub-side-5/  // 同上
|-AGENTS.md // 工作空间提示词（当前文件）
```
