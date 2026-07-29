# syntax=docker/dockerfile:1.9
# vivarium - self-contained environment for running coding agents against
# mounted host folders.

ARG WOLFI_BASE=cgr.dev/chainguard/wolfi-base:latest

ARG PYTHON_VERSION=3.13
ARG NODE_MAJOR=22

# Must match the effective owner of the mounted volume. See README.
ARG USERNAME=agent
ARG USER_UID=1000
ARG USER_GID=1000

ARG INCLUDE_RUST=0        # rustup toolchain
ARG INCLUDE_ZIG=1         # zig compiler
ARG INCLUDE_DOCS=1        # pandoc + typst + d2
ARG INCLUDE_SEMGREP=0     # semgrep static analysis
ARG INCLUDE_AGENTS=1      # claude-code + opencode CLI


# ----- stage 1: go tools with no wolfi package -----
FROM ${WOLFI_BASE} AS gotools

RUN apk add --no-cache go git build-base

ENV GOBIN=/out \
    GOFLAGS=-trimpath \
    CGO_ENABLED=0 \
    GOTOOLCHAIN=local

RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/root/go/pkg/mod \
    go install golang.org/x/tools/gopls@latest && \
    go install mvdan.cc/gofumpt@latest && \
    go install github.com/fatih/gomodifytags@latest && \
    go install github.com/cweill/gotests/gotests@latest && \
    go install github.com/editorconfig-checker/editorconfig-checker/v3/cmd/editorconfig-checker@latest && \
    go install github.com/evilmartians/lefthook@latest && \
    go install github.com/johnkerl/miller/cmd/mlr@latest && \
    go install github.com/trufflesecurity/trufflehog/v3@latest

ARG INCLUDE_DOCS
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/root/go/pkg/mod \
    if [ "${INCLUDE_DOCS}" = "1" ]; then go install oss.terrastruct.com/d2@latest; fi


# ----- stage 2: upstream static binaries with no wolfi package -----
FROM ${WOLFI_BASE} AS binaries

ARG TARGETARCH
ARG INCLUDE_DOCS
ARG PANDOC_VERSION=3.10.1
ARG TYPST_VERSION=0.15.1

RUN apk add --no-cache curl tar xz

WORKDIR /out

# The "stable" tag always points at the current shellcheck release.
RUN set -eu; \
    case "${TARGETARCH}" in \
      amd64) SC_ARCH=x86_64 ;; \
      arm64) SC_ARCH=aarch64 ;; \
      *) echo "unsupported arch: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/koalaman/shellcheck/releases/download/stable/shellcheck-stable.linux.${SC_ARCH}.tar.xz" \
      | tar -xJ --strip-components=1 -C /out "shellcheck-stable/shellcheck"

RUN set -eu; \
    if [ "${INCLUDE_DOCS}" != "1" ]; then exit 0; fi; \
    case "${TARGETARCH}" in \
      amd64) P_ARCH=amd64; T_ARCH=x86_64 ;; \
      arm64) P_ARCH=arm64; T_ARCH=aarch64 ;; \
    esac; \
    curl -fsSL "https://github.com/jgm/pandoc/releases/download/${PANDOC_VERSION}/pandoc-${PANDOC_VERSION}-linux-${P_ARCH}.tar.gz" \
      | tar -xz --strip-components=2 -C /out "pandoc-${PANDOC_VERSION}/bin/pandoc"; \
    curl -fsSL "https://github.com/typst/typst/releases/download/v${TYPST_VERSION}/typst-${T_ARCH}-unknown-linux-musl.tar.xz" \
      | tar -xJ --strip-components=1 -C /out "typst-${T_ARCH}-unknown-linux-musl/typst"

RUN chmod 0755 /out/*


# ----- stage 3: runtime -----
FROM ${WOLFI_BASE} AS runtime

ARG PYTHON_VERSION
ARG NODE_MAJOR
ARG USERNAME
ARG USER_UID
ARG USER_GID
ARG INCLUDE_RUST
ARG INCLUDE_ZIG
ARG INCLUDE_DOCS
ARG INCLUDE_SEMGREP
ARG INCLUDE_AGENTS

LABEL org.opencontainers.image.title="vivarium" \
      org.opencontainers.image.description="Self-contained environment for running coding agents against mounted folders" \
      org.opencontainers.image.base.name="cgr.dev/chainguard/wolfi-base"

SHELL ["/bin/sh", "-eux", "-c"]

# ----- core cli -----
RUN apk add --no-cache \
      bash zsh coreutils findutils grep sed gawk diffutils procps util-linux \
      shadow sudo gosu tini busybox \
      ca-certificates curl wget openssh-client rsync \
      xz zstd pigz unzip zip 7zip libarchive \
      ripgrep fd fzf bat eza tree file less \
      jq yq xh jo \
      htop btop tmux stow direnv zoxide starship \
      git git-lfs gh glab delta difftastic lazygit \
      just sqlite yamllint \
      mtr iputils

# ----- secrets -----
RUN apk add --no-cache gnupg age sops

# ----- build toolchain -----
RUN apk add --no-cache build-base gcc glibc-dev make cmake ninja-build samurai pkgconf

# ----- languages -----
RUN apk add --no-cache \
      go delve golangci-lint shfmt \
      "python-${PYTHON_VERSION}" "py${PYTHON_VERSION}-pip" uv ruff \
      "nodejs-${NODE_MAJOR}" npm yarn bun

RUN if [ "${INCLUDE_ZIG}" = "1" ]; then apk add --no-cache zig; fi
RUN if [ "${INCLUDE_RUST}" = "1" ]; then apk add --no-cache rustup rust-analyzer; fi

# ----- containers, api, supply chain -----
RUN apk add --no-cache \
      docker-cli docker-cli-buildx docker-compose dive \
      protobuf protoc-gen-go buf grpcurl mkcert \
      gitleaks grype syft crane

# Wolfi retires packages; these are nice-to-have and must not fail the build.
RUN for p in tree-sitter actionlint lazydocker fastfetch neovim helm-4; do \
      apk add --no-cache "$p" >/dev/null 2>&1 && echo "ok   $p" || echo "skip $p"; \
    done

COPY --from=gotools  /out/ /usr/local/bin/
COPY --from=binaries /out/ /usr/local/bin/

# ----- python tooling -----
ENV UV_TOOL_DIR=/opt/uv/tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=manual

RUN uv tool install black && \
    uv tool install isort && \
    uv tool install pylint && \
    uv tool install pytest && \
    uv tool install basedpyright && \
    uv tool install pre-commit && \
    uv tool install httpie

RUN if [ "${INCLUDE_SEMGREP}" = "1" ]; then uv tool install semgrep; fi

# ----- node tooling -----
ENV npm_config_prefix=/usr/local \
    npm_config_fund=false \
    npm_config_audit=false \
    npm_config_update_notifier=false

RUN npm install -g --no-progress \
      typescript \
      typescript-language-server \
      eslint \
      prettier \
      js-beautify \
      stylelint \
      stylelint-config-standard \
      yaml-language-server \
      bash-language-server \
    && npm cache clean --force

RUN if [ "${INCLUDE_AGENTS}" = "1" ]; then \
      npm install -g --no-progress @anthropic-ai/claude-code opencode-ai && npm cache clean --force; \
    fi

# ----- user -----
RUN if ! getent group "${USER_GID}" >/dev/null; then groupadd --gid "${USER_GID}" "${USERNAME}"; fi && \
    useradd -o --uid "${USER_UID}" --gid "${USER_GID}" --shell /bin/zsh --create-home "${USERNAME}" && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${USERNAME}" && \
    chmod 0440 "/etc/sudoers.d/${USERNAME}"

# Mounted trees are owned by a foreign uid; without safe.directory every git
# command in the workspace fails with "detected dubious ownership".
RUN git config --system --add safe.directory '*' && \
    git config --system init.defaultBranch main && \
    git config --system core.pager delta && \
    git config --system delta.navigate true && \
    git config --system delta.line-numbers true

# ----- environment -----
ENV HOME=/home/${USERNAME} \
    USER=${USERNAME} \
    SHELL=/bin/zsh \
    LANG=C.UTF-8 \
    XDG_CONFIG_HOME=/home/${USERNAME}/.config \
    XDG_DATA_HOME=/home/${USERNAME}/.local/share \
    XDG_CACHE_HOME=/home/${USERNAME}/.cache \
    XDG_STATE_HOME=/home/${USERNAME}/.local/state \
    GOPATH=/home/${USERNAME}/go \
    GOTOOLCHAIN=local \
    BUN_INSTALL=/home/${USERNAME}/.bun \
    CARGO_HOME=/home/${USERNAME}/.cargo \
    RUSTUP_HOME=/home/${USERNAME}/.rustup \
    VIVARIUM_USER=${USERNAME} \
    PATH=/home/${USERNAME}/.local/bin:/home/${USERNAME}/go/bin:/home/${USERNAME}/.bun/bin:/home/${USERNAME}/.cargo/bin:/usr/local/bin:/usr/bin:/bin

RUN install -d -o "${USER_UID}" -g "${USER_GID}" \
      "/home/${USERNAME}/.local/bin" \
      "/home/${USERNAME}/.config" \
      "/home/${USERNAME}/.cache" \
      "/home/${USERNAME}/.local/state" \
      "/home/${USERNAME}/go/bin" \
      "/home/${USERNAME}/.bun/bin" \
      /workspace

COPY --chmod=0755 rootfs/usr/local/bin/vivarium-entrypoint /usr/local/bin/vivarium-entrypoint
COPY --chmod=0755 rootfs/usr/local/bin/keeper /usr/local/bin/keeper

RUN apk info -v | sort > /etc/vivarium.manifest

WORKDIR /workspace
USER ${USERNAME}

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/vivarium-entrypoint"]
CMD ["/bin/zsh", "-l"]
