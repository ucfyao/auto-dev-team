# auto-dev-team v3.0 优化设计文档

**日期**: 2026-02-19
**状态**: 提案
**参与者**: architect, reliability-engineer, ux-specialist (AI Agent Team Review)

---

## 1. 背景

auto-dev-team v3.0 已完成核心功能实现，可作为独立工具编排 Claude Code Agent 团队自主开发功能。经三位专家（架构、可靠性、用户体验）深度分析，发现 **26 项优化点**，涵盖正确性 Bug、可靠性缺陷、扩展性限制和用户体验不足。

本文档定义优化方案与实施路线图。

---

## 2. 问题总览

### 2.1 按严重程度分布

| 严重程度 | 数量 | 说明 |
|---------|------|------|
| Critical | 5 | 功能性 Bug，影响正确性与数据安全 |
| High | 11 | 严重影响使用体验和生产可靠性 |
| Medium | 10 | 改善开发体验和可维护性 |

### 2.2 按类别分布

| 类别 | 数量 |
|------|------|
| 正确性 Bug | 3 |
| 可靠性 / 错误处理 | 7 |
| 架构 / 可扩展性 | 6 |
| 用户体验 | 6 |
| 性能 / 并行能力 | 4 |

---

## 3. Critical 问题详细设计

### 3.1 循环依赖检测失效

**问题**: `check-env.sh:70-79` 的 jq 表达式只检测自引用（A→A），无法发现链式循环（A→B→A 或更长链）。且结果变量 `CYCLE_CHECK` 未被使用。

**根因**: jq 内部变量作用域问题——`select(. == .id)` 中的 `.id` 指向了错误的上下文。

**方案**: 使用 Python DFS 检测循环依赖（jq 实现 Kahn 算法存在作用域和边遍历的局限性，Python 更可靠）。

```bash
# check-env.sh — 替换 lines 70-79
validate_dependency_graph() {
    local features_file="$1"

    # 1. 检查所有 depends_on 引用的 ID 是否存在
    local invalid_deps
    invalid_deps=$(jq -r '
        [.features[].id] as $all_ids |
        [.features[].depends_on[] | select(. as $d | $all_ids | index($d) | not)] |
        unique | .[]
    ' "$features_file")
    if [ -n "$invalid_deps" ]; then
        echo "ERROR: Unknown dependency IDs: $invalid_deps"
        return 1
    fi

    # 2. 检查自引用（使用 as 绑定避免 jq 作用域问题）
    local self_deps
    self_deps=$(jq -r '
        .features[] | . as $f | select(.depends_on | index($f.id)) | .id
    ' "$features_file")
    if [ -n "$self_deps" ]; then
        echo "ERROR: Self-referencing features: $self_deps"
        return 1
    fi

    # 3. DFS 循环检测（Python，正确处理任意长度链式循环）
    python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
graph = {f['id']: f.get('depends_on', []) for f in data['features']}
visited, stack = set(), set()
def has_cycle(node):
    if node in stack: return True
    if node in visited: return False
    visited.add(node); stack.add(node)
    for dep in graph.get(node, []):
        if has_cycle(dep): return True
    stack.discard(node); return False
if any(has_cycle(n) for n in graph):
    print('ERROR: Circular dependency detected'); sys.exit(1)
" "$features_file" || return 1
}
```

> **设计决策说明**: 最初考虑使用 jq 实现 Kahn 算法（拓扑排序），但 jq 的 `until` 循环无法正确遍历邻居并更新入度（缺少边列表数据结构），且 `input_line_number` 等函数与图算法无关。Python DFS 方案经验证正确，可处理任意长度的循环链，且 `python3` 在所有目标平台均可用。

**优先级**: Critical
**影响范围**: `check-env.sh`

---

### 3.2 自定义 Agent 动态加载

**问题**: `run.sh:47-51` 和 `run.sh:106-112` 硬编码了 4 个 Agent 的 prompt 加载。`team.json` 的 `custom_agents` 数组被完全忽略，文档与实现不一致。

**方案**: 动态从 `team.json` 加载所有 Agent prompt（排除 Lead Agent 避免重复）。

```bash
# run.sh — 替换 hardcoded agent prompt loading

# Lead Agent prompt 单独加载（已在 mega-prompt 头部注入）
LEAD_PROMPT=$(cat "$TOOL_DIR/agents/lead.md")

# 动态加载所有 sub-agent prompts（排除 lead，避免重复注入）
AGENT_PROMPTS=""
for PROMPT_FILE in $(jq -r '
    [.agents[] | select(.name != "lead") | .prompt_file,
     .custom_agents[]?.prompt_file] | .[]
' "$TOOL_DIR/team.json"); do
    AGENT_NAME=$(basename "$PROMPT_FILE" .md)
    if [ -z "$AGENT_NAME" ]; then continue; fi
    AGENT_CONTENT=$(cat "$TOOL_DIR/$PROMPT_FILE" 2>/dev/null) || {
        echo "ERROR: Agent prompt file not found: $TOOL_DIR/$PROMPT_FILE"
        exit 1
    }
    AGENT_PROMPTS+="
### ${AGENT_NAME} Agent Prompt
${AGENT_CONTENT}
"
done
```

在 mega-prompt heredoc 中替换硬编码的 agent 部分为 `${AGENT_PROMPTS}`。

> **注意**: 如果实施了 5.5（项目级配置覆盖），动态加载需先合并 `team.json` 和 `config.json` 中的 `team_overrides.custom_agents`，以项目级配置优先。合并策略为追加（不覆盖同名 agent）。

**优先级**: Critical
**影响范围**: `run.sh`, `team.json`

---

### 3.3 Claude CLI 崩溃处理

**问题**: `run.sh:131` 的 `cat "$PROMPT_FILE" | claude ...` 是脚本最后一行。CLI 崩溃后无日志、无状态恢复提示。

**方案**:

```bash
# run.sh — 替换最后的 claude 调用

# 记录 session 开始
jq -n --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    '{ts: $ts, event: "session_started"}' >> "$PROGRESS_LOG"

set +e
claude --dangerously-skip-permissions -p - < "$PROMPT_FILE"
EXIT_CODE=$?
set -e

# 记录 session 结束
jq -n --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --argjson code "$EXIT_CODE" \
    '{ts: $ts, event: "session_ended", exit_code: $code}' >> "$PROGRESS_LOG"

if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "========================================="
    echo "ERROR: Claude CLI exited with code $EXIT_CODE"
    echo "Run './scripts/resume.sh $PROJECT_NAME' to recover."
    echo "========================================="
    exit $EXIT_CODE
fi
```

**优先级**: Critical
**影响范围**: `run.sh`

---

### 3.4 feature_list.json 原子写 + 备份

**问题**: 协议依赖 LLM 正确实现原子写入，崩溃可导致 JSON 损坏且无法恢复。

**方案 A — 启动前备份**:

```bash
# run.sh — 在 claude 调用前添加
BACKUP_DIR="$PROJECT_DIR/backups"
mkdir -p "$BACKUP_DIR"
cp "$FEATURE_LIST" "$BACKUP_DIR/feature_list.$(date +%s).json"
# 保留最近 10 个备份
ls -1t "$BACKUP_DIR"/feature_list.*.json 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null
```

**方案 B — 协议强化**:

在 `protocol.md` 的状态文件操作部分增加：

```markdown
## 状态文件写入规范（必须严格遵守）

写入 feature_list.json 时必须使用以下模式：
1. 读取当前文件内容
2. 在内存中修改
3. 写入临时文件 `feature_list.json.tmp`
4. 使用 `mv feature_list.json.tmp feature_list.json` 原子替换

绝对不要直接截断写入 feature_list.json。
```

**方案 C — 启动时完整性校验**:

```bash
# check-env.sh — 添加 JSON 完整性校验
if ! jq empty "$FEATURES" 2>/dev/null; then
    echo "ERROR: feature_list.json is corrupted (invalid JSON)."
    LATEST_BACKUP=$(ls -1t "$PROJECT_DIR/backups"/feature_list.*.json 2>/dev/null | head -1)
    if [ -n "$LATEST_BACKUP" ]; then
        echo "  Latest backup available: $LATEST_BACKUP"
        echo "  Restore with: cp '$LATEST_BACKUP' '$FEATURES'"
    fi
    exit 1
fi
```

**建议**: 三个方案同时实施（互补，非互斥）。

**额外建议**（基于评审反馈）:
- 方案 C 的 `jq empty` 仅验证 JSON 语法有效性，不能检测数据丢失（如 features 数组被截断但 JSON 仍合法）。建议在完整性校验中增加 feature 计数比对：若当前 feature 数量比最近备份少 50% 以上，发出警告。
- 方案 B 的协议指令为"最佳努力"——LLM 仍可能不遵守。方案 A 和 C 提供了硬保障。

**优先级**: Critical
**影响范围**: `run.sh`, `check-env.sh`, `protocol.md`

---

### 3.5 resume.sh git 状态恢复

**问题**: 崩溃后 `resume.sh` 只重置 `in_progress` 和 `testing` 状态的任务，不检查目标项目的 git 状态（残留分支、未提交更改、detached HEAD、非 main 分支、中断的 merge/rebase）。且未处理 `merging` 状态的任务。

**方案**:

```bash
# resume.sh — 在重置任务状态后、调用 run.sh 前添加

TARGET=$(jq -r '.target' "$PROJECT_DIR/config.json")

# 0. 同时重置 merging 状态的任务（原代码遗漏）
# 修改现有 jq 表达式，增加 "merging" 状态:
# .features[] | select(.status == "in_progress" or .status == "testing" or .status == "merging")

# 1. 检测并中止残留的 merge/rebase 操作
if [ -f "$TARGET/.git/MERGE_HEAD" ]; then
    echo "WARNING: Interrupted merge detected, aborting..."
    git -C "$TARGET" merge --abort
fi
if [ -d "$TARGET/.git/rebase-merge" ] || [ -d "$TARGET/.git/rebase-apply" ]; then
    echo "WARNING: Interrupted rebase detected, aborting..."
    git -C "$TARGET" rebase --abort
fi

# 2. 检测 detached HEAD
if ! git -C "$TARGET" symbolic-ref HEAD &>/dev/null; then
    echo "WARNING: Target project is in detached HEAD state."
    echo "  Recovering: checking out default branch..."
    DEFAULT_BRANCH=$(git -C "$TARGET" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@') || DEFAULT_BRANCH="main"
    git -C "$TARGET" checkout "$DEFAULT_BRANCH"
fi

# 3. 确保在默认分支（动态检测，不硬编码 main/master）
DEFAULT_BRANCH=$(git -C "$TARGET" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@') || DEFAULT_BRANCH="main"
CURRENT_BRANCH=$(git -C "$TARGET" branch --show-current)
if [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]; then
    echo "WARNING: Target on branch '$CURRENT_BRANCH', switching to $DEFAULT_BRANCH..."
    git -C "$TARGET" stash 2>/dev/null || true  # 避免无变更时 stash 报错导致脚本崩溃
    git -C "$TARGET" checkout "$DEFAULT_BRANCH"
fi

# 4. 报告被重置任务的残留分支
RESET_IDS=$(jq -r '.features[] | select(.status == "pending" and .attempts > 0) | .id' "$FEATURE_LIST")
for FID in $RESET_IDS; do
    BRANCH="feature/$FID"
    if git -C "$TARGET" branch --list "$BRANCH" | grep -q "$BRANCH"; then
        echo "WARNING: Orphaned branch '$BRANCH' found for reset task $FID"
        echo "  Consider: git -C '$TARGET' branch -D '$BRANCH'"
    fi
done

# 5. 清理孤立的 git worktree（配合 4.1 并行隔离方案）
for WT in /tmp/auto-dev-*; do
    if [ -d "$WT" ]; then
        echo "WARNING: Orphaned worktree found: $WT"
        git -C "$TARGET" worktree remove "$WT" 2>/dev/null || true
    fi
done
```

**优先级**: Critical
**影响范围**: `resume.sh`

---

## 4. High 问题设计

### 4.1 并行 Agent 的 git 隔离 (git worktree)

**问题**: 多个 Agent 并行操作同一 git 工作目录，checkout/commit 存在竞态条件。

**方案**: 使用 `git worktree` 为每个并行 Agent 创建独立工作目录。

在 `protocol.md` 中增加：

```markdown
## 并行执行的 Git 隔离

当并行分派多个 feature 时，为每个 feature 创建独立的 git worktree：

1. `git -C <target> worktree add /tmp/auto-dev-<project>-<feature-id> -b feature/<feature-id>`
2. 将 worktree 路径传递给 sub-agent 作为工作目录
3. Sub-agent 在 worktree 中完成实现和提交
4. 合并时：`git -C <target> merge feature/<feature-id> --no-edit`
5. 清理：`git -C <target> worktree remove /tmp/auto-dev-<project>-<feature-id>`

**注意**：合并必须在主工作目录中执行，不能在 sub-worktree 内部执行。
```

**崩溃恢复**: `resume.sh` 需要清理 `/tmp/auto-dev-*` 下的孤立 worktree（已纳入 3.5 方案）。

**优先级**: High
**影响范围**: `protocol.md`, agent prompts

---

### 4.2 合并冲突处理策略

在 `protocol.md` 的合并步骤后增加：

```markdown
## 合并冲突处理

如果 `git merge feature/<id> --no-edit` 产生冲突：

1. 运行 `git merge --abort` 取消当前合并
2. 将 feature 状态设为 `failed`，error_log 记录冲突文件列表
3. 在下次重试时，指示实现 Agent 先 rebase 到最新 main：
   - `git checkout feature/<id>`
   - `git rebase main`（解决冲突）
   - `git checkout main && git merge feature/<id> --ff-only`
4. 如果 rebase 后仍有冲突，由实现 Agent 手动解决后再合并
5. **如果冲突过于复杂（超过 3 个文件冲突），将 feature 标记为 `blocked` 而非继续重试**，避免 LLM 在复杂冲突解决上的不可靠性导致无限循环
```

**优先级**: High
**影响范围**: `protocol.md`

---

### 4.3 sed 占位符替换安全化

**问题**: `run.sh:74-77` 使用 `sed -i.bak` 替换 `{{...}}` 占位符，`|` 分隔符与路径中 `&`（sed 特殊字符，表示"匹配文本"）冲突风险。

**方案**: 对替换值进行转义后使用 sed（不引入 `envsubst` 新依赖，macOS 默认不带 `envsubst`）。

```bash
# run.sh — 替换 sed 占位符替换

# 转义 sed 替换值中的特殊字符（&, /, \）
escape_sed() {
    printf '%s\n' "$1" | sed 's/[&/\]/\\&/g'
}

ESCAPED_FEATURES=$(escape_sed "$FEATURE_LIST")
ESCAPED_PROGRESS=$(escape_sed "$PROGRESS_LOG")
ESCAPED_TARGET=$(escape_sed "$TARGET")

sed -i.bak \
    -e "s|{{FEATURE_LIST_PATH}}|${ESCAPED_FEATURES}|g" \
    -e "s|{{PROGRESS_LOG_PATH}}|${ESCAPED_PROGRESS}|g" \
    -e "s|{{TARGET_PROJECT_PATH}}|${ESCAPED_TARGET}|g" \
    "$PROMPT_FILE"
rm -f "${PROMPT_FILE}.bak"

# 验证替换完成
if grep -q '{{.*}}' "$PROMPT_FILE"; then
    echo "ERROR: Prompt template has unresolved placeholders."
    grep '{{.*}}' "$PROMPT_FILE"
    exit 1
fi
```

> **设计决策说明**: 最初考虑使用 `envsubst`（GNU gettext），但该工具在 macOS 上默认不安装（需 `brew install gettext`），引入新依赖与项目"纯 bash + jq"的设计原则不符。sed 转义方案无新依赖，同时解决了 `&` 和 `|` 特殊字符问题。

**优先级**: High
**影响范围**: `run.sh`

---

### 4.4 JSON Schema 验证

在 `check-env.sh` 中添加基于 jq 的轻量验证（不引入新依赖）：

```bash
validate_feature_schema() {
    local features_file="$1"

    # 必填字段检查
    local missing
    missing=$(jq '[.features[] | select(
        .id == null or .category == null or .title == null or
        .status == null or .priority == null or
        .attempts == null or .max_attempts == null or
        .depends_on == null
    ) | .id // "unknown"] | .[]' "$features_file")
    if [ -n "$missing" ]; then
        echo "ERROR: Features with missing required fields: $missing"
        return 1
    fi

    # status 枚举验证
    local invalid_status
    invalid_status=$(jq '[.features[] | select(
        .status | IN("pending","in_progress","testing","merging",
                      "completed","failed","blocked","cancelled") | not
    ) | .id] | .[]' "$features_file")
    if [ -n "$invalid_status" ]; then
        echo "ERROR: Features with invalid status: $invalid_status"
        return 1
    fi

    # 字段类型验证
    local type_errors
    type_errors=$(jq '[.features[] | select(
        (.attempts | type) != "number" or
        (.max_attempts | type) != "number" or
        (.depends_on | type) != "array"
    ) | .id] | .[]' "$features_file")
    if [ -n "$type_errors" ]; then
        echo "ERROR: Features with wrong field types: $type_errors"
        return 1
    fi

    # category 合法性验证（与 team.json agent 匹配）
    local team_file="${2:-}"
    if [ -n "$team_file" ] && [ -f "$team_file" ]; then
        local invalid_cats
        invalid_cats=$(jq --slurpfile team "$team_file" '
            [($team[0].agents[].name // empty), ($team[0].custom_agents[]?.name // empty)] as $valid_cats |
            [.features[] | select(.category as $c | $valid_cats | index($c) | not) | .id] | .[]
        ' "$features_file")
        if [ -n "$invalid_cats" ]; then
            echo "ERROR: Features with unknown category (no matching agent): $invalid_cats"
            return 1
        fi
    fi
}
```

> **注意**: `IN()` 函数需要 jq 1.6+。建议在 `check-env.sh` 的依赖检查中添加 jq 版本验证：
> ```bash
> JQ_VERSION=$(jq --version 2>&1 | grep -oE '[0-9]+\.[0-9]+')
> if [ "$(printf '%s\n' "1.6" "$JQ_VERSION" | sort -V | head -1)" != "1.6" ]; then
>     echo "ERROR: jq 1.6+ required (found $JQ_VERSION)"
>     exit 1
> fi
> ```

**优先级**: High
**影响范围**: `check-env.sh`

---

### 4.5 status.sh 进度查看命令

新增 `scripts/status.sh`：

```bash
#!/usr/bin/env bash
set -e
TOOL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="$1"
if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: status.sh <project-name>"
    exit 1
fi
PROJECT_DIR="$TOOL_DIR/projects/$PROJECT_NAME"
FEATURES="$PROJECT_DIR/feature_list.json"
if [ ! -f "$FEATURES" ]; then
    echo "ERROR: Project '$PROJECT_NAME' not found. Run init-project.sh first."
    exit 1
fi

# 统计
echo "Project: $PROJECT_NAME"
echo ""
jq -r '.features[] |
    (if .status == "completed" then "[x]"
     elif .status == "in_progress" then "[>]"
     elif .status == "failed" then "[!]"
     elif .status == "blocked" then "[-]"
     else "[ ]" end) + " " + .id + "  " + .title +
    "  (" + .status +
    (if .assigned_to != "" and .assigned_to != null then " / " + .assigned_to else "" end) +
    ")"
' "$FEATURES"

echo ""
echo "Summary:"
jq -r '[.features[].status] | group_by(.) | map({(.[0]): length}) | add | to_entries[] | "  \(.key): \(.value)"' "$FEATURES"
```

**优先级**: High
**影响范围**: 新文件 `scripts/status.sh`

---

### 4.6 add-feature 命令简化特性定义

新增 `scripts/add-feature.sh`：

```bash
#!/usr/bin/env bash
set -e
TOOL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 参数解析
PROJECT_NAME="$1"; shift || { echo "Usage: add-feature.sh <project> --id ID --category CAT --title TITLE [options]"; exit 1; }

ID="" CATEGORY="" TITLE="" DESCRIPTION="" DEPENDS_ON="" PRIORITY=5
while [ $# -gt 0 ]; do
    case "$1" in
        --id)          ID="$2"; shift 2 ;;
        --category)    CATEGORY="$2"; shift 2 ;;
        --title)       TITLE="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --depends-on)  DEPENDS_ON="$2"; shift 2 ;;
        --priority)    PRIORITY="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# 必填字段校验
if [ -z "$ID" ] || [ -z "$CATEGORY" ] || [ -z "$TITLE" ]; then
    echo "ERROR: --id, --category, and --title are required."
    exit 1
fi

PROJECT_DIR="$TOOL_DIR/projects/$PROJECT_NAME"
FEATURES="$PROJECT_DIR/feature_list.json"
if [ ! -f "$FEATURES" ]; then
    echo "ERROR: Project '$PROJECT_NAME' not found."
    exit 1
fi

# 检查 ID 唯一性
if jq -e --arg id "$ID" '.features[] | select(.id == $id)' "$FEATURES" >/dev/null 2>&1; then
    echo "ERROR: Feature ID '$ID' already exists."
    exit 1
fi

# 将逗号分隔的 depends_on 转为 JSON 数组
DEPS_JSON="[]"
if [ -n "$DEPENDS_ON" ]; then
    DEPS_JSON=$(echo "$DEPENDS_ON" | tr ',' '\n' | jq -R . | jq -s .)
    # 校验依赖引用的 ID 存在
    INVALID=$(echo "$DEPS_JSON" | jq --slurpfile f "$FEATURES" -r '
        [.[] | select(. as $d | [$f[0].features[].id] | index($d) | not)] | .[]
    ')
    if [ -n "$INVALID" ]; then
        echo "ERROR: Unknown dependency IDs: $INVALID"
        exit 1
    fi
fi

# 原子追加：读取 → 修改 → 写临时文件 → mv
jq --arg id "$ID" --arg cat "$CATEGORY" --arg title "$TITLE" \
   --arg desc "$DESCRIPTION" --argjson deps "$DEPS_JSON" \
   --argjson pri "$PRIORITY" \
   '.features += [{
        id: $id, category: $cat, title: $title, description: $desc,
        status: "pending", priority: $pri, depends_on: $deps,
        attempts: 0, max_attempts: 3,
        assigned_to: "", branch: "", error_log: [], notes: "",
        created_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
        started_at: null, completed_at: null
    }]' "$FEATURES" > "${FEATURES}.tmp" && mv "${FEATURES}.tmp" "$FEATURES"

echo "Added feature $ID: $TITLE"
```

**优先级**: Medium（降级——属于便利功能，非可靠性问题）
**影响范围**: 新文件 `scripts/add-feature.sh`

---

### 4.7 并行调度指令强化

在 `protocol.md` Section 4 中增加明确指令：

```markdown
## 并行任务分派（必须遵守）

在每次调度循环中：
1. 筛选所有 eligible features（status=pending，所有 depends_on 均为 completed）
2. 按 priority 升序排列
3. **如果有多个 eligible features，必须在同一个响应中发起多个 Task 调用来并行分派**
4. 不要等一个 feature 完成再分派下一个
5. 每个并行 feature 使用独立的 git worktree（见 Git 隔离章节）

6. 并行数量上限受 `config.json` 中 `"max_parallel": 3` 控制（默认 3），避免同时分派过多任务
7. 每个并行 feature 必须使用独立的 git worktree（参见「并行执行的 Git 隔离」章节）

示例：如果 F-003 和 F-004 都是 eligible，在同一消息中发起两个 Task 调用。
```

**优先级**: High
**影响范围**: `protocol.md`, `config.json`

---

### 4.8 jq 错误友好提示

为所有 jq 调用添加上下文错误信息：

```bash
# 通用模式 — 替换裸 jq 调用
read_json_field() {
    local file="$1" field="$2"
    local value jq_err
    jq_err=$(mktemp)
    value=$(jq -r "$field" "$file" 2>"$jq_err") || {
        local err_detail
        err_detail=$(cat "$jq_err")
        rm -f "$jq_err"
        echo "ERROR: Failed to parse $file (field: $field). Detail: $err_detail" >&2
        return 1
    }
    rm -f "$jq_err"
    echo "$value"
}

# 使用
TARGET=$(read_json_field "$CONFIG" '.target')
```

**优先级**: High
**影响范围**: 所有脚本

---

### 4.9 sub-agent 超时机制

在 `protocol.md` 中添加：

```markdown
## 任务超时

- 每个 Task 调用必须设置 timeout 参数（默认 600000ms = 10 分钟）
- **最大值 600000ms（10 分钟）**——Claude Code Task 工具的硬限制，不可超越
- 如果 Task 超时，将 feature 标记为 failed，error_log 记录 "timeout"
- 在 config.json 中可配置：`"task_timeout_ms": 600000`（上限 600000）
- 对于预估超过 10 分钟的复杂 feature，应拆分为多个子 feature 而非延长超时
```

**优先级**: High
**影响范围**: `protocol.md`, `config.json`

---

### 4.10 Agent 全栈框架适配

在 agent prompt 系统中增加 `fullstack` category：

```markdown
# agents/fullstack.md

You are a Full-Stack Developer agent. You handle features that span both
server-side and client-side code, particularly for frameworks where the
boundary is blurred (Next.js, Nuxt, SvelteKit, Remix, etc.).

You have permission to modify ANY file in the project — both server and
client code. Follow the same workflow as backend/frontend agents but
without scope restrictions.
```

在 `team.json` 中添加该 Agent 定义。Fullstack agent prompt 应包含与 backend/frontend 相同的工作流指令（分支策略、commit 格式、测试要求等），而非仅一段概述。

> **前置依赖**: 此项依赖 3.2（自定义 Agent 动态加载）先行实施。在 3.2 完成前，即使将 fullstack 添加到 `team.json`，`run.sh` 仍只加载硬编码的 4 个 agent，新 agent 不会生效。

**优先级**: High
**影响范围**: 新文件 `agents/fullstack.md`, `team.json`

---

## 5. Medium 问题设计

### 5.1 统一 CLI 入口

创建 `bin/auto-dev-team` 作为统一入口：

```bash
#!/usr/bin/env bash
TOOL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:-help}" in
    init)    shift; exec "$TOOL_DIR/scripts/init-project.sh" "$@" ;;
    run)     shift; exec "$TOOL_DIR/scripts/run.sh" "$@" ;;
    resume)  shift; exec "$TOOL_DIR/scripts/resume.sh" "$@" ;;
    status)  shift; exec "$TOOL_DIR/scripts/status.sh" "$@" ;;
    add)     shift; exec "$TOOL_DIR/scripts/add-feature.sh" "$@" ;;
    help|*)  echo "Usage: auto-dev-team <command> [args]"
             echo "  init <name> <path>   Register a new project"
             echo "  run <name>           Start autonomous development"
             echo "  resume <name>        Recover from crash"
             echo "  status <name>        Show project progress"
             echo "  add <name> [opts]    Add a feature" ;;
esac
```

> **前置依赖**: `status` 和 `add` 子命令依赖 4.5（status.sh）和 4.6（add-feature.sh）先行实施。可分阶段交付——先支持 `init/run/resume`，待 4.5/4.6 完成后再添加 `status/add`。

**优先级**: Medium

### 5.2 提取 _lib.sh 公共库

> **前置依赖**: `load_project()` 调用了 4.8 的 `read_json_field()`，需 4.8 先行实施。

**已确认的重复代码**（跨脚本出现 2-4 次）：
- `TOOL_DIR="$(cd "$(dirname "$0")/.." && pwd)"` — 4 处
- `PROJECT_DIR` / `CONFIG` / `FEATURE_LIST` 路径拼接 — 3 处
- `TARGET=$(jq -r '.target' "$CONFIG")` — 2 处
- progress log JSON 写入模式 — 3 处

将重复逻辑提取到 `scripts/_lib.sh`：

```bash
#!/usr/bin/env bash
# 通用工具函数

resolve_tool_dir() {
    cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd
}

load_project() {
    local project_name="$1"
    local tool_dir="$2"
    PROJECT_DIR="$tool_dir/projects/$project_name"
    CONFIG="$PROJECT_DIR/config.json"
    FEATURE_LIST="$PROJECT_DIR/feature_list.json"
    PROGRESS_LOG="$PROJECT_DIR/progress.log"
    TARGET=$(read_json_field "$CONFIG" '.target')
}

read_json_field() { ... }  # 见 4.8

log_event() {
    local log_file="$1" event="$2"
    shift 2
    jq -n --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg event "$event" "$@" \
        '{ts: $ts, event: $event}' >> "$log_file"
}
```

**优先级**: Medium

### 5.3 --dry-run 模式

在 `run.sh` 中添加 `--dry-run` 标志：

```bash
if [ "$2" = "--dry-run" ]; then
    echo "=== DRY RUN ==="
    echo "Project: $PROJECT_NAME"
    echo "Target: $TARGET"
    echo ""
    echo "Execution plan:"
    # 按依赖拓扑序输出 features
    jq -r '.features | sort_by(.priority) | .[] |
        .id + " [" + .category + "] " + .title +
        (if (.depends_on | length) > 0 then " (after: " + (.depends_on | join(", ")) + ")" else "" end)
    ' "$FEATURE_LIST"
    echo ""
    echo "Prompt size: $(wc -c < "$PROMPT_FILE") bytes"
    echo "Agent types needed: $(jq -r '[.features[].category] | unique | join(", ")' "$FEATURE_LIST")"
    exit 0
fi
```

**优先级**: Medium

### 5.4 可定制工作流

在 `config.json` 中添加可选的工作流配置：

```json
{
    "workflows": {
        "default": ["implement", "qa", "merge"],
        "trivial": ["implement", "merge"],
        "strict": ["implement", "lint", "qa", "review", "merge"]
    }
}
```

Feature 可声明 `"workflow": "trivial"` 来跳过 QA。Protocol 中根据 workflow 配置动态调整状态转换。

> **实施风险**: 此项需要修改 protocol.md 的状态机逻辑，让 Lead Agent（LLM）动态解释 workflow 配置并调整状态转换，复杂度较高。当前固定工作流已覆盖 90% 使用场景。**建议延后到 Phase 4 之后，或在需求明确后再实施**。
>
> 同时注意 `config.json` 扩展需与 4.9（timeout 配置）和 5.5（项目级覆盖）统一设计，避免三处独立扩展同一文件。

**优先级**: Low（从 Medium 降级——接近 YAGNI 边界）

### 5.5 项目级配置覆盖

扩展 `config.json` 支持：

```json
{
    "target": "/path/to/project",
    "name": "my-app",
    "defaults": {
        "max_attempts": 5,
        "task_timeout_ms": 900000
    },
    "team_overrides": {
        "custom_agents": [
            {"name": "devops", "prompt_file": "agents/devops.md"}
        ]
    }
}
```

`run.sh` 在加载全局 `team.json` 后合并项目级覆盖。

**合并策略**:
- `defaults`: 深合并，项目级值覆盖全局默认值
- `team_overrides.custom_agents`: 追加到全局 `team.json` 的 `custom_agents` 数组，不覆盖同名 agent
- `task_timeout_ms`: 上限校验，不得超过 600000ms

> **注意**: 扩展后的 `config.json` schema 需与 4.4（JSON Schema 验证）统一——`check-env.sh` 的验证逻辑需同时校验新字段的类型和取值范围。

**优先级**: Medium

### 5.6 其他 Medium 项

| 项目 | 方案概要 |
|------|---------|
| resume.sh 检查目标分支 | 见 3.5 方案已包含 |
| cancelled 状态转换 | 在 protocol 中定义 cancel 路径，add `cancel-feature.sh` |
| Priority vs dependency 交互 | 在 protocol 中明确 "先过滤 eligible，再按 priority 排序" |
| 并行依赖示例 | 添加 `examples/blog-app/` 包含钻石依赖图 |
| Detached HEAD 检测 | 在 `check-env.sh` 中添加 `git symbolic-ref HEAD` 检查 |
| Agent 歧义处理指引 | 在 agent prompt 中添加 "choose simplest implementation" fallback |

---

## 6. 实施路线图

### Phase 1 — 安全性与正确性（消除 Critical Bug）

| 任务 | 文件 | 工作量 |
|------|------|--------|
| 修复循环依赖检测（Python DFS） | `check-env.sh` | ~30 行 |
| 实现自定义 Agent 动态加载（排除 lead） | `run.sh` | ~20 行 |
| 添加 CLI 崩溃处理 | `run.sh` | ~15 行 |
| 备份 + 原子写 + 完整性校验（含计数比对） | `run.sh`, `check-env.sh`, `protocol.md` | ~35 行 |
| resume.sh git 恢复（含 merge/rebase 中断检测） | `resume.sh` | ~40 行 |

**预计产出**: 修复 5 个 Critical bug，~140 行代码变更。

### Phase 2 — 可靠性与验证

| 任务 | 文件 | 工作量 |
|------|------|--------|
| JSON Schema 验证（含类型校验 + jq 版本检查） | `check-env.sh` | ~50 行 |
| jq 错误友好提示（保留原始错误信息） | 所有脚本 | ~30 行 |
| sed 占位符替换安全化（转义方案） | `run.sh` | ~15 行 |
| 添加 status.sh（含输入校验） | 新文件 | ~35 行 |
| Prompt 大小警告 | `run.sh` | ~10 行 |
| BATS 测试框架 + 核心测试 | `tests/` 目录 | ~350 行 |

> **注意**: BATS 测试需覆盖循环依赖检测、Schema 验证、lockfile、备份恢复、resume 逻辑等，原估计 ~200 行偏低。

**预计产出**: 消除 High 可靠性问题，引入测试框架。

### Phase 3 — 并行能力

| 任务 | 文件 | 工作量 |
|------|------|--------|
| git worktree 支持（含 resume.sh 清理） | `protocol.md`, agent prompts | ~50 行文档 |
| 合并冲突处理策略（含复杂冲突 blocked 阈值） | `protocol.md` | ~25 行文档 |
| 并行调度指令强化（含 max_parallel 配置） | `protocol.md`, `config.json` | ~20 行文档 |
| sub-agent 超时机制（上限 600000ms） | `protocol.md`, `config.json` | ~10 行文档 |

**预计产出**: 安全的并行执行能力。

### Phase 4 — 用户体验

| 任务 | 文件 | 工作量 |
|------|------|--------|
| 提取 _lib.sh（依赖 Phase 2 的 read_json_field） | `scripts/_lib.sh` | ~50 行 |
| 重构现有脚本使用 _lib.sh | `run.sh`, `check-env.sh`, `resume.sh`, `init-project.sh` | ~-40 行（净减少） |
| 统一 CLI 入口（先支持 init/run/resume） | `bin/auto-dev-team` | ~20 行 |
| add-feature 命令 | `scripts/add-feature.sh` | ~80 行 |
| --dry-run 模式（含依赖图展示） | `run.sh` | ~25 行 |
| fullstack agent（依赖 Phase 1 的 3.2 动态加载） | `agents/fullstack.md`, `team.json` | ~30 行 |
| 并行依赖示例 | `examples/blog-app/` | ~40 行 |

**预计产出**: 完善的 CLI 体验和可扩展性。

---

## 7. 不做的事情（YAGNI）

| 提议 | 理由 |
|------|------|
| 重写为 Python/Node | Bash 脚本足够简洁，引入运行时依赖得不偿失 |
| 外部数据库存储状态 | JSON 文件对当前规模完全够用 |
| Web dashboard | 超出工具定位，`status.sh` 足够 |
| Webhook/Slack 通知 | 低优先级，可后续按需添加 |
| 删除 `merging` 状态 | 对审计日志有价值，保留 |
| Token 预算硬限制 | 无需硬限制，但添加 prompt 大小警告（已纳入 Phase 2 路线图） |

---

## 8. 成功标准

**正确性与安全性**:
- [ ] 所有 Critical bug 修复，无已知正确性问题
- [ ] `check-env.sh` 能检测循环依赖（任意长度链）、无效引用、缺失字段、错误类型
- [ ] 自定义 Agent 能正确加载和分派（不重复加载 lead）
- [ ] Claude CLI 崩溃后可通过 `resume.sh` 完整恢复，具体包括：
  - (a) 重置所有非终态任务（含 `merging` 状态）
  - (b) 检测并恢复 git 异常状态（detached HEAD、中断的 merge/rebase）
  - (c) 提示备份恢复选项
  - (d) 保持 progress.log 连续性（session_started/session_ended 配对）
- [ ] `feature_list.json` 有备份、完整性校验和计数比对

**可靠性与测试**:
- [ ] 核心脚本有 BATS 单元测试覆盖（循环依赖、Schema 验证、lockfile、备份恢复、resume 逻辑）
- [ ] Protocol 文档无内部矛盾，覆盖所有状态转换路径
- [ ] Prompt 大小超过阈值时发出警告

**并行能力**:
- [ ] 两个并行 feature 可通过 git worktree 安全同时执行
- [ ] 合并冲突可自动处理（简单情况）或标记为 blocked（复杂情况）

**用户体验**:
- [ ] 用户可通过 `auto-dev-team status` 查看进度
- [ ] 用户可通过 `auto-dev-team add` 添加 feature 而非手写 JSON
- [ ] `--dry-run` 可预览执行计划和依赖图
- [ ] 脚本间无重复工具代码（统一使用 `_lib.sh`）

**规模验证**:
- [ ] 系统在 10+ features 含钻石依赖图的场景下正确运行
