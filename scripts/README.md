# scripts

工作空间管理脚本。作用是把「主库 + N 个并行 worktree」这套结构变成可重复、可重建的操作，避免每次靠记忆敲命令。

## worktree.sh

管理 `repos/bh/` 下的主库与 worktree。

```bash
./scripts/worktree.sh init            # 克隆主库并建立 5 个 worktree
./scripts/worktree.sh status          # 查看各 worktree 的分支、领先/落后、改动数
./scripts/worktree.sh add 6           # 追加第 6 个 worktree
./scripts/worktree.sh remove 6        # 移除第 6 个 worktree（保留分支）
```

### 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `BH_REMOTE` | `https://github.com/CoCoCoDeDeDe/bike-hub.git` | 主库地址 |
| `BH_BASE` | `main` | 新建 side 分支时的基线 |
| `SIDES` | `5` | init 时创建的数量 |

### 常见场景

**换一台机器，重建整个工作区：**

```bash
git clone https://github.com/CoCoCoDeDeDe/bike-hub-dev-space.git
cd bike-hub-dev-space
./scripts/worktree.sh init
```

**临时多开一个工作区：**

```bash
./scripts/worktree.sh add 6
```

**收工，看看谁还有未提交的改动：**

```bash
./scripts/worktree.sh status
```

## 设计约束

- **幂等**：重复执行 `init` 只补缺失的 worktree，不动已有的。
- **不碰子仓库的 `.git`**：脚本只通过 `git worktree` 操作，不手工删目录；`remove` 会先检查路径存在。
- **分支不自动删**：`remove` 只移除工作区，分支保留，避免误删未合并的提交。
- **工作区归属**：一个 worktree 同一时间只由一个 AGENT 操作（见 `../AGENTS.md`）。

## 扩展脚本的建议位置

- 环境自检（gh 登录、platformio、串口设备）→ `scripts/doctor.sh`
- 一次编译并上传 → `scripts/flash.sh`
- 采集数据分析 → 放 `repos/bh/*/tools/`，不放这里（属于产品代码）
