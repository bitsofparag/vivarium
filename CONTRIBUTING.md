# Contributing

There are lots of guides on how to effectively contribute to open-source projects (OSPs), but I would recommend reading [Opensource.guide](https://opensource.guide/how-to-contribute/).

If you need a tl;dr version, see the workflow below.

## Workflow

1. Create a branch from `main`. Please name the branch as `feat-<short-title>`, `fix-<short-title>`, or `chore-<short-title>`.
2. Make focused code changes that a human can review.
3. Run `just lint`.
4. Run `just security-contract` when changing between rootless or rootful modes.
5. Run `just identity-contract` when Dockerfile user validation changes.
5. Run `just build && just smoke` when the Dockerfile, rootfs files, or Compose runtime configuration changes.
6. On rootful Docker, run `just build-rootful && just smoke-rootful` when rootful UID/GID handling, home paths, entrypoint behavior, or mounts change. Otherwise, rely on CI.

## Coding Standards

- Use `Justfile` as the project command runner.
- Keep shell scripts POSIX `sh` unless a feature requires another shell.
- Keep logs quiet on success and useful on failure.
- Do not commit secrets, local env files, generated workspaces, or agent credentials.
- Update `README.md` when behavior, build args, or user-facing commands change.
