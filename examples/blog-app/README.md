# Blog App Demo — Parallel Dispatch Example

This example demonstrates **parallel dispatch** with a diamond dependency graph.

## Dependency Graph

        F-001 (backend: Init Express server)
        /                                  \
  F-002 (backend: Blog post API)    F-003 (backend: User auth API)
       |                                   |
  F-005 (frontend: Post list page)  F-004 (frontend: Login page)
       \                                  /
        F-006 (frontend: Comment system)
              depends on F-002 + F-003

## Parallel Execution Points

1. **After F-001 completes**: F-002 and F-003 dispatch in parallel
2. **After F-002 and F-003 complete**: F-004 and F-005 dispatch in parallel
3. **After all complete**: F-006 dispatches (diamond merge point)

## Quick Start

    # 1. Create a target project directory
    mkdir /tmp/blog-demo && cd /tmp/blog-demo && git init

    # 2. Register with auto-dev-team
    cd /path/to/auto-dev-team
    ./scripts/init-project.sh blog-demo /tmp/blog-demo

    # 3. Copy the example feature list
    cp examples/blog-app/feature_list.json projects/blog-demo/

    # 4. Run
    ./scripts/run.sh blog-demo

## Using Auto-Generate Instead

    # Preview generated features:
    ./scripts/generate-features.sh blog-demo --file examples/blog-app/requirements.txt

    # Apply to project:
    ./scripts/generate-features.sh blog-demo --file examples/blog-app/requirements.txt --apply
