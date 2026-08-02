# vivarium

Docker environment for running AI coding agents.

> [!IMPORTANT]
> Vivarium defaults to **rootless Docker**, limiting the impact of the agent escaping the container. Rootful compatibility requires an explicit `*-rootful` recipe.

- **Purpose:**
  - Provides common build, test, lint, shell, Git, container, and supply-chain tools.
  - Supports Go, Python, Node, and general Unix work.
  - Mounts the working repository at `/workspace`.


## Quick Start

- **Requirements:**
  - Configure [rootless Docker](https://docs.docker.com/engine/security/rootless/).
  - Install [`just`](https://github.com/casey/just).

- **Build and Test:**

  ```sh
  just build
  just smoke
  ```

- **Check or Open the Environment:**

  ```sh
  just doctor
  just shell
  ```

- **Run an Agent Task:**

  ```sh
  docker compose run --rm vivarium keeper run claude -p "fix the lint errors"
  ```


## Toolchain

- **Base:**
  - Wolfi Linux with glibc.

- **Languages:**
  - Go, Python, Node, and Zig.

- **Development Tools:**
  - Shell, Git, linters, formatters, container tools, supply-chain tools, media conversion, documentation, and secrets tooling.

- **Agent Tools:**
  - Claude Code, opencode, rtk, CodeGraph, and caveman.

- **Exact Inventory:**
  - Run `keeper manifest` or read `/etc/vivarium.manifest`.

- **Optional Build Features:**
  - Set the build argument directly or the matching `VIVARIUM_INCLUDE_*` value in `.env.local` when using Compose.

| Build arg           | Adds                  | Size    | Default |
|---------------------|-----------------------|---------|---------|
| `INCLUDE_ZIG`       | zig                   | ~180 MB | on      |
| `INCLUDE_DOCS`      | pandoc, typst, d2     | ~250 MB | on      |
| `INCLUDE_AGENTS`    | claude-code, opencode | ~150 MB | on      |
| `INCLUDE_RTK`       | rtk                   | small   | on      |
| `INCLUDE_CODEGRAPH` | codegraph CLI         | small   | on      |
| `INCLUDE_CAVEMAN`   | caveman command       | small   | on      |
| `INCLUDE_RUST`      | rustup, rust-analyzer | ~1.2 GB | off     |
| `INCLUDE_SEMGREP`   | semgrep               | ~400 MB | off     |

- **Version Pins:**
  - `RTK_VERSION` pins the rtk release.
  - `CODEGRAPH_VERSION` pins the npm package version or tag.
  - `CAVEMAN_REF` pins the GitHub ref for the installed `caveman` command.


## How-to

- **Docker Security Mode Options:**

  **Rootless (Default, Safer):**
  - Use `just build` and `just smoke`. These commands check that Docker runs in rootless mode.
  - If using Docker or Compose directly, run `just rootless-check` first.
  - A regular `docker build` creates the same image but won’t verify how it runs later.

  **Rootful (For Compatibility):**
  - Use `just build-rootful` and `just smoke-rootful`.
  - Automatically uses your host user’s permissions.
  - If using Compose directly, set `VIVARIUM_ROOTFUL_UID` and `VIVARIUM_ROOTFUL_GID`.
  - Runs as user `agent` with home directory `/home/agent`, preventing files from being owned by root.

  **For Hermes:**
  - In default rootless mode, set `docker_run_as_host_user: false` so Hermes uses `/root` for persistent files.

- **Change Python or Node Versions:**

  ```sh
  docker build --build-arg PYTHON_VERSION=3.11 --build-arg NODE_MAJOR=20 -t vivarium .
  ```

- **Reduce Image Size:**

  ```sh
  docker build \
    --build-arg INCLUDE_DOCS=0 \
    --build-arg INCLUDE_ZIG=0 \
    --build-arg INCLUDE_AGENTS=0 \
    -t vivarium .
  ```

- **Fix `/workspace` Permissions:**
  - Run `keeper doctor` to see the mount owner.
  - Rootless: ensure the path belongs to the user running Docker.
  - Rootful: use `just` recipes or set `VIVARIUM_ROOTFUL_UID` and `VIVARIUM_ROOTFUL_GID`.

- **Fix Mounted Folder Permissions:**
  - Grant the host user read, write, and directory traversal permissions before starting Hermes.

  ```sh
  stat -c '%U:%G %a %n' "/path/to/mounted/folder"
  sudo chown -R "$(id -u):$(id -g)" "/path/to/mounted/folder"
  find "/path/to/mounted/folder" -type d -exec chmod u+rwx {} +
  find "/path/to/mounted/folder" -type f -exec chmod u+rw {} +
  ```

  - Use a group ACL instead of `chown` for shared folders.
  - `keeper doctor` reports inaccessible directories under `/workspace` and `/output`.

- **Use Agent Helper Commands:**
  - Vivarium includes `rtk`, `codegraph`, and `caveman`.
  - Their initialization commands are not run during the image build because they write user or project configuration.
  - Initialize them only in persisted paths, such as a mounted repository or agent configuration directory.

- **Transcribe Audio:**
  - Vivarium includes `ffmpeg` and `transcribe-audio`, but no Whisper models.

  ```sh
  transcribe-audio meeting.m4a > meeting.txt
  ```

  - Backend order: `TRANSCRIBE_URL`, OpenAI when `OPENAI_API_KEY` is set, then local `whisper-cli` when `WHISPER_MODEL` points to a mounted model.
  - Keep large models and Whisper servers outside the base image.

- **Run Docker Commands Inside Vivarium:**
  - Vivarium includes Docker client tools, not a Docker daemon.
  - Mount a host Docker socket only for trusted agents. It grants control of that Docker host.


## FAQ

- **Why Wolfi?**
  - Uses glibc, matching mainstream Linux environments more closely than musl-based Alpine.
  - Provides a rolling package set.

- **Does Vivarium Sandbox the Agent?**
  - Rootless Docker limits host privilege.
  - Writable mounts remain writable. An agent can change or delete their contents.
  - Unmounted host paths remain outside the container's normal filesystem view.
  - Network access remains enabled unless explicitly disabled.

- **Can an Agent Escape the Container?**
  - Vivarium reduces accidental damage but does not guarantee containment against a deliberate escape attempt.
  - Use gVisor with `docker run --runtime=runsc` or Kata Containers for stronger isolation.
  - Mount only the files required for the task.

- **Can I Use Another Agent?**
  - Yes. Nothing in the image requires Claude Code or opencode.
  - Set `INCLUDE_AGENTS=0` for an image without the bundled agent CLIs.
  - Install another agent with npm, uv, `go install`, or a static binary.
  - `keeper run <name>` runs any matching command found on `PATH`.
  - Desktop agents and agents requiring direct host access are not supported.

- **Is the Image Reproducible?**
  - Pulling the same digest returns identical image contents for that platform.
  - Rebuilding later may differ because the base image, Go tools, and npm packages are not fully pinned.
  - For stricter rebuilds, pin the base digest and tool versions, then lock npm packages.
  - Keep `/etc/vivarium.manifest` as the installed package record.
