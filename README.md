# vivarium

(Yet another) Docker image for running AI coding agents.

Vivarium is a containerized development environment for agent runs. It includes **the essentials**, viz. common build, test, lint, shell, Git, container, and supply-chain tools for Go, Python, Node, and general Unix work.

Build the image, publish it if needed, then run an agent with a repo mounted at `/workspace`. The mount is the boundary: files outside the mounted paths are not part of the agent's working area.


## Quick-Start

Build the image:

```sh
just build
```

Use this when publishing to a registry or configuring a runner such as Hermes. The published image includes the essentials above, as well as Zig, docs tooling, Claude Code/opencode, rtk, CodeGraph, and caveman; but excludes Rust and Semgrep.

For local checks, Compose mounts the repository's `./workspace` directory at `/workspace`:

```sh
just doctor   # verify the toolchain
just shell    # interactive shell in /workspace
```


## What's Inside the Toolchain

A Wolfi (glibc) base carrying toolchains for Go, Python and Node, as well as the usual shell, version control, language linting and formatting tooling, container and supply-chain utilities, media conversion, and secrets tooling. In other words, everything an agent needs to build, test and lint a polyglot repo without reaching outside the container.

You can find the exact inventory at `/etc/vivarium.manifest`, or via `keeper manifest`.

### Optional Tools

Each is a build arg. If using Compose, set the matching `VIVARIUM_INCLUDE_*` value in `.env.local`.

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

`RTK_VERSION` pins the rtk release. `CODEGRAPH_VERSION` pins the npm package version or tag. `CAVEMAN_REF` pins the GitHub ref used for the installed `caveman` command.


## How-to

**Match a Python/Node pair:**

`docker build --build-arg PYTHON_VERSION=3.11 --build-arg NODE_MAJOR=20 -t vivarium .`

**Shrink the image:**

`--build-arg INCLUDE_DOCS=0 --build-arg INCLUDE_ZIG=0 --build-arg INCLUDE_AGENTS=0`

**Fix "permission denied" on /workspace:**

`keeper doctor` prints the mount's owner uid:gid.

- With Compose or `just build`, set `VIVARIUM_UID`/`VIVARIUM_GID`.
- With plain `docker build`, pass `USER_UID`/`USER_GID` as build args.

**Fix "permission denied" inside a mounted folder:**

`docker_run_as_host_user: true` preserves host Unix permissions. A mounted directory owned by `root` with mode `744` cannot be entered by `agent`, because directory traversal needs execute permission. Fix ownership or ACLs on the host path before starting Hermes:

```sh
stat -c '%U:%G %a %n' "/path/to/mounted/folder"
sudo chown -R "$(id -u):$(id -g)" "/path/to/mounted/folder"
find "/path/to/mounted/folder" -type d -exec chmod u+rwx {} +
find "/path/to/mounted/folder" -type f -exec chmod u+rw {} +
```

Use a group ACL instead of `chown` when that folder is shared with other host users. `keeper doctor` reports inaccessible mounted directories under `/workspace` and `/output`.

**Run under rootless Docker:**

The container uid 0 maps to your host user (uid 1000). Therefore, build the Compose image with `VIVARIUM_UID=0 VIVARIUM_GID=0 just build`, or pass `--build-arg USER_UID=0 --build-arg USER_GID=0` to `docker build`. In Hermes, use `docker_run_as_host_user: false` for this shape.

**Run a single agent task:** `docker compose run --rm vivarium keeper run claude -p "fix the lint errors"`

**Agent helper CLIs:**

Vivarium includes `rtk`, `codegraph`, and `caveman` as commands. Their init/install commands are intentionally not run during image build, because they write user, agent, or project config. Run those commands only in a persisted location, such as a mounted repo for `.codegraph/` or a mounted agent config directory.

**Transcribe audio:**

Vivarium includes `ffmpeg` and a `transcribe-audio` helper, but no Whisper model files. Configure transcription at the runner level:

```sh
transcribe-audio meeting.m4a > meeting.txt
```

`transcribe-audio` uses `TRANSCRIBE_URL` first, then OpenAI's transcription API when `OPENAI_API_KEY` is set, then a local `whisper-cli` only when `WHISPER_MODEL` points at a mounted model. Keep large models or Whisper servers outside the base image.

**Run Docker commands inside Vivarium:**

Vivarium includes Docker client tools, not a daemon. If an agent should control a host Docker daemon, configure that socket mount in the runner and treat it as trusted access to the host.


## FAQ

**Why Wolfi?** It is glibc-based, so binaries built inside the container behave the same as on a mainstream Linux host; musl (Alpine) would diverge. It also ships a rolling package set rather than a frozen release.

**Does this sandbox the agent?** An agent working inside a vivarium can only touch the folders you handed it. If it deletes a file not in the mounted folder, installs a broken package, or fills the disk with build junk, the mess stays inside the container and your machine is unchanged. Delete the container and it is all gone.

**But LLMs could break out of the sandbox?** Yes, and I get asked this a lot. This project is built to stop accidents, and may not stop an agent from deliberately trying to break out. Top frontier models have been shown not to respect isolated environments. However, if this concerns you greatly, launch the vivarium container on a stronger runtime, e.g `docker run --runtime=runsc` for gVisor, or Kata Containers for a lightweight VM. Always remember that anything you mount as writable really can be changed or deleted, so mount only what the task needs. And the agent still has full internet access unless you turn networking off.

**Can I bring my own agent?** Yes, and that is rather the point. The two agent CLIs that ship by default sit behind a build arg, so `INCLUDE_AGENTS=0` gives you a bare environment with no opinion about what runs in it. Install whatever you prefer with npm, uv, or `go install`, or drop a static binary into `/usr/local/bin`. Nothing in the image is tied to a particular agent; `keeper run <name>` simply hands off to whatever it finds on your PATH. The toolchain is the part worth keeping, so changing your mind about the agent should not mean rebuilding your setup. The one thing that will not fit is an agent that needs a desktop session or direct access to your host.

**Is the image reproducible everywhere?** Two different things get called reproducible here, and only one of them is true today. A given image runs the same anywhere. Pull it by digest and you get identical bits on any amd64 or arm64 machine, which is what most people actually mean by the question. Rebuilding it from this Dockerfile is a different matter: the base is `:latest`, the Go tools install from `@latest`, and the npm packages are unpinned, so a build today and a build next month will not match. Wolfi also keeps only the current version of each package, so pinning something like `python-3.11` works right up until it is retired. If byte-for-byte rebuilds matter to you, pin the base by digest, pin the Go tools to release tags, and add a lockfile for the npm globals. Until then, pull by digest and hold on to `/etc/vivarium.manifest`, which records exactly what a given image contained.
