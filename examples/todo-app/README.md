# Example: Todo App

This example demonstrates auto-dev-team building a simple Express.js + vanilla JS todo application from scratch.

## What Gets Built

A todo app with:

- **F-001**: Express.js server with health endpoint
- **F-002**: CRUD REST API for todos (in-memory storage)
- **F-003**: HTML/JS frontend to add and list todos
- **F-004**: Toggle completion and delete functionality

Features are built sequentially due to dependencies: F-001 → F-002 → F-003 → F-004. QA validation runs after each feature, and each feature is merged to main before the next one starts.

## How to Run

1. Create a target project directory:

   ```bash
   mkdir -p /tmp/todo-demo && cd /tmp/todo-demo && git init
   ```

2. Navigate to the auto-dev-team directory:

   ```bash
   cd /path/to/auto-dev-team
   ```

3. Initialize the project:

   ```bash
   ./scripts/init-project.sh todo-demo /tmp/todo-demo
   ```

4. Copy the example feature list:

   ```bash
   cp examples/todo-app/feature_list.json projects/todo-demo/feature_list.json
   ```

5. Run:

   ```bash
   ./scripts/run.sh todo-demo
   ```

## What to Expect

The Lead Agent will:

1. Read the feature list and dispatch F-001 to the Backend Agent
2. After F-001 is built, QA validates it, then it gets merged to main
3. F-002 is dispatched (depends on F-001 being completed)
4. Process continues through F-003 and F-004
5. Session ends when all 4 features are completed

## Resuming After a Crash

If the session crashes mid-way, orphaned tasks will be stuck in `in_progress` or `testing`. Run:

```bash
./scripts/resume.sh todo-demo
```

This resets orphaned tasks to `pending` and re-launches the session.
