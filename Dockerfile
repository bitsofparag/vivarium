# syntax=docker/dockerfile:1.9
# vivarium - self-contained environment for running coding agents against
# mounted host folders.

ARG WOLFI_BASE=cgr.dev/chainguard/wolfi-base:latest

ARG PYTHON_VERSION=3.13
ARG NODE_MAJOR=22

# Must match the effective owner of the mounted volume. See README.
ARG USERNAME=root
ARG USER_UID=0
ARG USER_GID=0
ARG USER_HOME=/root

ARG INCLUDE_RUST=0        # rustup toolchain
ARG INCLUDE_ZIG=1         # zig compiler
ARG INCLUDE_DOCS=1        # pandoc + typst + d2
ARG INCLUDE_SEMGREP=0     # semgrep static analysis
ARG INCLUDE_AGENTS=1      # claude-code + opencode CLI
ARG INCLUDE_RTK=1         # rtk command runner
ARG INCLUDE_CODEGRAPH=1   # codegraph repository indexer
ARG INCLUDE_CAVEMAN=1     # caveman agent instructions installer

ARG RTK_VERSION=
ARG CODEGRAPH_VERSION=
ARG CAVEMAN_REF=v1.9.1


# ---- stage 1: Validate build-time identity settings -------------------------
# If username is root, uid and gid = 0
# If username is not root, uid and gid > 0
FROM ${WOLFI_BASE} AS identity

ARG USERNAME
ARG USER_UID
ARG USER_GID
ARG USER_HOME

RUN set -eu; \
    case "${USER_HOME}" in /*) ;; *) echo "USER_HOME must be absolute" >&2; exit 1 ;; esac; \
    if [ "${USERNAME}" = "root" ]; then \
      if [ "${USER_UID}" != "0" ] || [ "${USER_GID}" != "0" ] || [ "${USER_HOME}" != "/root" ]; then \
        echo "root identity requires USER_UID=0, USER_GID=0, and USER_HOME=/root" >&2; \
        exit 1; \
      fi; \
    elif [ "${USER_UID}" = "0" ] || [ "${USER_GID}" = "0" ]; then \
      echo "non-root identity requires non-zero USER_UID and USER_GID" >&2; \
      exit 1; \
    fi; \
    touch /identity-valid


# ----- stage 2: go tools with no wolfi package -------------------------------
FROM --platform=$BUILDPLATFORM ${WOLFI_BASE} AS gotools

ARG TARGETOS
ARG TARGETARCH

RUN apk add --no-cache go git build-base

ENV GOPATH=/root/go \
    GOFLAGS=-trimpath \
    CGO_ENABLED=0 \
    GOTOOLCHAIN=local \
    GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH}

RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/root/go/pkg/mod \
    go install golang.org/x/tools/gopls@latest && \
    go install mvdan.cc/gofumpt@latest && \
    go install github.com/fatih/gomodifytags@latest && \
    go install github.com/cweill/gotests/gotests@latest && \
    go install github.com/editorconfig-checker/editorconfig-checker/v3/cmd/editorconfig-checker@latest && \
    go install github.com/evilmartians/lefthook@latest && \
    go install github.com/johnkerl/miller/v6/cmd/mlr@latest && \
    install -d /out && \
    go_bin="${GOPATH}/bin"; \
    if [ -d "${go_bin}/${GOOS}_${GOARCH}" ]; then go_bin="${go_bin}/${GOOS}_${GOARCH}"; fi; \
    cp "${go_bin}"/* /out/

ARG INCLUDE_DOCS
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/root/go/pkg/mod \
    if [ "${INCLUDE_DOCS}" = "1" ]; then \
      go install oss.terrastruct.com/d2@latest; \
      go_bin="${GOPATH}/bin"; \
      if [ -d "${go_bin}/${GOOS}_${GOARCH}" ]; then go_bin="${go_bin}/${GOOS}_${GOARCH}"; fi; \
      cp "${go_bin}/d2" /out/; \
    fi


# ----- stage 3: upstream static binaries with no wolfi package ---------------
FROM --platform=$BUILDPLATFORM ${WOLFI_BASE} AS binaries

ARG TARGETARCH
ARG INCLUDE_DOCS
ARG PANDOC_VERSION=3.10.1
ARG TYPST_VERSION=0.15.1

RUN apk add --no-cache curl xz

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


# ----- stage 4: runtime ------------------------------------------------------
FROM ${WOLFI_BASE} AS runtime-common

ARG PYTHON_VERSION
ARG NODE_MAJOR
ARG WOLFI_BASE
ARG INCLUDE_RUST
ARG INCLUDE_ZIG
ARG INCLUDE_DOCS
ARG INCLUDE_SEMGREP
ARG INCLUDE_AGENTS
ARG INCLUDE_RTK
ARG INCLUDE_CODEGRAPH
ARG INCLUDE_CAVEMAN
ARG RTK_VERSION
ARG CODEGRAPH_VERSION
ARG CAVEMAN_REF

LABEL org.opencontainers.image.title="vivarium" \
      org.opencontainers.image.description="Self-contained environment for running coding agents against mounted folders" \
      org.opencontainers.image.base.name="${WOLFI_BASE}" \
      org.opencontainers.image.licenses="Apache-2.0"

SHELL ["/bin/sh", "-eux", "-c"]

# ----- core cli -----
RUN apk add --no-cache \
      bash zsh coreutils findutils grep sed gawk diffutils procps util-linux \
      shadow sudo gosu tini busybox \
      ca-certificates tzdata curl wget openssh-client rsync \
      xz zstd pigz unzip zip 7zip libarchive \
      ffmpeg \
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
RUN for p in tree-sitter actionlint; do \
    apk add --no-cache "$p" >/dev/null 2>&1 || echo "skip $p"; \
    done

COPY --from=gotools  /out/ /usr/local/bin/
COPY --from=binaries /out/ /usr/local/bin/

# ----- uv-based python tooling -----
ENV UV_TOOL_DIR=/opt/uv/tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=manual

RUN --mount=type=cache,target=/root/.cache/uv \
    uv tool install black && \
    uv tool install isort && \
    uv tool install pylint && \
    uv tool install pytest && \
    uv tool install basedpyright && \
    uv tool install pre-commit && \
    uv tool install httpie

RUN --mount=type=cache,target=/root/.cache/uv \
    if [ "${INCLUDE_SEMGREP}" = "1" ]; then uv tool install semgrep; fi

# ----- node tooling -----
ENV npm_config_prefix=/usr/local \
    npm_config_fund=false \
    npm_config_audit=false \
    npm_config_update_notifier=false

RUN --mount=type=cache,target=/root/.npm \
    npm install -g --no-progress \
      typescript \
      typescript-language-server \
      eslint \
      prettier \
      js-beautify \
      stylelint \
      stylelint-config-standard \
      yaml-language-server \
      bash-language-server

RUN --mount=type=cache,target=/root/.npm \
    if [ "${INCLUDE_AGENTS}" = "1" ]; then \
      npm install -g --no-progress \
        --allow-scripts=@anthropic-ai/claude-code,opencode-ai \
        @anthropic-ai/claude-code opencode-ai; \
    fi

# ----- agent helpers -----
RUN set -eu; \
    if [ "${INCLUDE_RTK}" = "1" ]; then \
      tmp="$(mktemp)"; \
      trap 'rm -f "$tmp"' EXIT; \
      curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh -o "$tmp"; \
      RTK_INSTALL_DIR=/usr/local/bin RTK_VERSION="${RTK_VERSION}" sh "$tmp"; \
    fi

RUN --mount=type=cache,target=/root/.npm \
    if [ "${INCLUDE_CODEGRAPH}" = "1" ]; then \
      package="@colbymchenry/codegraph"; \
      if [ -n "${CODEGRAPH_VERSION}" ]; then package="${package}@${CODEGRAPH_VERSION}"; fi; \
      npm install -g --no-progress "$package"; \
    fi

RUN --mount=type=cache,target=/root/.npm \
    if [ "${INCLUDE_CAVEMAN}" = "1" ]; then \
      npm install -g --no-progress --allow-git=all "github:JuliusBrussee/caveman#${CAVEMAN_REF}"; \
    fi

# Mounted trees are owned by a foreign uid; without safe.directory every git
# command in the workspace fails with "detected dubious ownership".
RUN git config --system --add safe.directory '*' && \
    git config --system init.defaultBranch main && \
    git config --system core.pager delta && \
    git config --system delta.navigate true && \
    git config --system delta.line-numbers true

# ----- stage 5: final runtime assembly ---------------------------------------
FROM runtime-common AS runtime

ARG USERNAME
ARG USER_UID
ARG USER_GID
ARG USER_HOME
ARG CAVEMAN_REF

COPY --from=identity /identity-valid /etc/vivarium.identity

# ----- user -----
RUN if [ "${USERNAME}" != "root" ]; then \
      if ! awk -F: -v gid="${USER_GID}" '$3 == gid { found = 1 } END { exit !found }' /etc/group; then \
        groupadd --gid "${USER_GID}" "${USERNAME}"; \
      fi; \
      useradd --uid "${USER_UID}" --gid "${USER_GID}" --home-dir "${USER_HOME}" \
        --shell /bin/zsh --create-home "${USERNAME}"; \
      echo "${USERNAME} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${USERNAME}"; \
      chmod 0440 "/etc/sudoers.d/${USERNAME}"; \
    fi

# ----- environment -----
ENV HOME=${USER_HOME} \
    USER=${USERNAME} \
    SHELL=/bin/zsh \
    LANG=C.UTF-8 \
    XDG_CONFIG_HOME=${USER_HOME}/.config \
    XDG_DATA_HOME=${USER_HOME}/.local/share \
    XDG_CACHE_HOME=${USER_HOME}/.cache \
    XDG_STATE_HOME=${USER_HOME}/.local/state \
    GOPATH=${USER_HOME}/go \
    GOTOOLCHAIN=local \
    BUN_INSTALL=${USER_HOME}/.bun \
    CARGO_HOME=${USER_HOME}/.cargo \
    RUSTUP_HOME=${USER_HOME}/.rustup \
    CAVEMAN_REF=${CAVEMAN_REF} \
    VIVARIUM_USER=${USERNAME} \
    VIVARIUM_USER_HOME=${USER_HOME} \
    PATH=${USER_HOME}/.local/bin:${USER_HOME}/go/bin:${USER_HOME}/.bun/bin:${USER_HOME}/.cargo/bin:/usr/local/bin:/usr/bin:/bin

RUN install -d -o "${USER_UID}" -g "${USER_GID}" \
      "${USER_HOME}/.local" \
      "${USER_HOME}/.local/bin" \
      "${USER_HOME}/.local/share" \
      "${USER_HOME}/.config" \
      "${USER_HOME}/.cache" \
      "${USER_HOME}/.local/state" \
      "${USER_HOME}/go/bin" \
      "${USER_HOME}/.bun/bin" \
      /workspace

COPY --chmod=0755 rootfs/usr/local/bin/vivarium-entrypoint /usr/local/bin/vivarium-entrypoint
COPY --chmod=0755 rootfs/usr/local/bin/keeper /usr/local/bin/keeper
COPY --chmod=0755 rootfs/usr/local/bin/transcribe-audio /usr/local/bin/transcribe-audio
COPY rootfs/etc/zsh/zshrc.d/vivarium.zsh /etc/zsh/zshrc.d/vivarium.zsh

RUN apk info -v | sort > /etc/vivarium.manifest

WORKDIR /workspace
USER ${USERNAME}

ENTRYPOINT ["/sbin/tini", "-s", "--", "/usr/local/bin/vivarium-entrypoint"]
CMD ["/bin/zsh", "-l"]
