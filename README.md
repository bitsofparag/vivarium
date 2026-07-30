# vivarium

(Yet another) Docker image for running AI coding agents.

Vivarium is a containerized development environment for agent runs. It includes **the essentials**, viz. common build, test, lint, shell, Git, container, and supply-chain tools for Go, Python, Node, and general Unix work.

Build the image, publish it if needed, then run an agent with a repo mounted at `/workspace`. The mount is the boundary: files outside the mounted paths are not part of the agent's working area.


## Quick-Start

Build the image:

```sh
just build
```

Use this when publishing to a registry or configuring a runner such as Hermes.

The published image includes the essentials above, as well as Zig, docs tooling, Claude Code/opencode, rtk, CodeGraph, and caveman; but excludes Rust and Semgrep. Image builds do not need workspace mount config.

For local checks, Compose mounts the repository's `./workspace` directory at `/workspace`:

```sh
just doctor   # verify the toolchain
just shell    # interactive shell in /workspace
```


## What's Inside the Toolchain

A Wolfi (glibc) base carrying toolchains for Go, Python and Node, as well as the usual shell, version control, language linting and formatting tooling, container and supply-chain utilities, and secrets tooling. In other words, everything an agent needs to build, test and lint a polyglot repo without reaching outside the container.

You can find the correct inventory at `/etc/vivarium.manifest`, or via `keeper manifest`.

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

**Match a Python/Node pair**
`docker build --build-arg PYTHON_VERSION=3.11 --build-arg NODE_MAJOR=20 -t vivarium .`

**Shrink the image**
`--build-arg INCLUDE_DOCS=0 --build-arg INCLUDE_ZIG=0 --build-arg INCLUDE_AGENTS=0`

**Fix "permission denied" on /workspace**
`keeper doctor` prints the mount's owner uid:gid. Rebuild with those as `USER_UID`/`USER_GID`.

**Run under rootless Docker**
The container uid 0 maps to your host user (uid 1000). Therefore, build with `USER_UID=0 USER_GID=0`, or start as root and let the entrypoint remap: `docker run --user 0:0 -e HOST_UID=0 ...`

**Run a single agent task**
`docker compose run --rm vivarium keeper run claude -p "fix the lint errors"`

**Run Docker commands inside Vivarium**
Vivarium includes Docker client tools, not a daemon. Mount a host socket only when the agent should control that daemon:

```sh
export VIVARIUM_DOCKER_SOCKET=/run/user/$(id -u)/docker.sock
just docker-shell
```

Use `/var/run/docker.sock` instead for a rootful daemon, better for security.

**Mount more than one folder**
Add them under `volumes:` in `compose.yaml` (or `compose.override.yaml`). Keep the writable set small and mark the rest `read_only: true`.
Writable mounts should share one owner on the host, because the container runs as a single user and can only match one uid.


## FAQ

**Why Wolfi?** It is glibc-based, so binaries built inside the container behave the same as on a mainstream Linux host; musl (Alpine) would diverge. It also ships a rolling package set rather than a frozen release.

**Does this sandbox the agent?** An agent working inside a vivarium can only touch the folders you handed it. If it deletes a file not in the mounted folder, installs a broken package, or fills the disk with build junk, the mess stays inside the container and your machine is unchanged. Delete the container and it is all gone.

**But LLMs could break out of the sandbox?** Yes, and I get asked this a lot. This project is built to stop accidents, and may not stop an agent from deliberately trying to break out. Top frontier models have been shown not to respect isolated environments. However, if this concerns you greatly, launch the vivarium container on a stronger runtime, e.g `docker run --runtime=runsc` for gVisor, or Kata Containers for a lightweight VM. Always remember that anything you mount as writable really can be changed or deleted, so mount only what the task needs. And the agent still has full internet access unless you turn networking off.

**Can I bring my own agent?** Yes, and that is rather the point. The two agent CLIs that ship by default sit behind a build arg, so `INCLUDE_AGENTS=0` gives you a bare environment with no opinion about what runs in it. Install whatever you prefer with npm, uv, or `go install`, or drop a static binary into `/usr/local/bin`. Nothing in the image is tied to a particular agent; `keeper run <name>` simply hands off to whatever it finds on your PATH. The toolchain is the part worth keeping, so changing your mind about the agent should not mean rebuilding your setup. The one thing that will not fit is an agent that needs a desktop session or direct access to your host.

**Is the image reproducible everywhere?** Two different things get called reproducible here, and only one of them is true today. A given image runs the same anywhere. Pull it by digest and you get identical bits on any amd64 or arm64 machine, which is what most people actually mean by the question. Rebuilding it from this Dockerfile is a different matter: the base is `:latest`, the Go tools install from `@latest`, and the npm packages are unpinned, so a build today and a build next month will not match. Wolfi also keeps only the current version of each package, so pinning something like `python-3.11` works right up until it is retired. If byte-for-byte rebuilds matter to you, pin the base by digest, pin the Go tools to release tags, and add a lockfile for the npm globals. Until then, pull by digest and hold on to `/etc/vivarium.manifest`, which records exactly what a given image contained.
