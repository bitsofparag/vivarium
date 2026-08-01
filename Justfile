set shell := ["sh", "-eu", "-c"]
set dotenv-filename := ".env.local"

scripts := "rootfs/usr/local/bin/keeper rootfs/usr/local/bin/transcribe-audio rootfs/usr/local/bin/vivarium-entrypoint tests/smoke.sh"
hadolint_image := "hadolint/hadolint:v2.14.0"

default:
	just --list

_rootless-option-check:
	@grep -q '"name=rootless"' || { \
		printf '%s\n' 'rootless Docker required; use an explicit rootful recipe only when necessary' >&2; \
		exit 1; \
	}

rootless-check:
	@docker info --format json | just _rootless-option-check

_rootful-option-check:
	@options="$(cat)"; \
	[ -n "$options" ] || { printf '%s\n' 'unable to determine Docker security mode' >&2; exit 1; }; \
	case "$options" in \
		*'"name=rootless"'*) \
			printf '%s\n' 'rootful recipe requires a rootful Docker daemon; use the default recipe here' >&2; \
			exit 1; \
			;; \
	esac

rootful-check:
	@docker info --format json | just _rootful-option-check

_build:
	docker compose build

build: rootless-check _build

doctor: rootless-check
	docker compose run --rm vivarium keeper doctor

doctor-rootful uid=`id -u` gid=`id -g`: rootful-check
	VIVARIUM_ROOTFUL_UID={{uid}} VIVARIUM_ROOTFUL_GID={{gid}} \
		docker compose -f compose.yaml -f examples/compose.rootful.yaml run --rm vivarium keeper doctor

manifest: rootless-check
	docker compose run --rm vivarium keeper manifest

manifest-rootful uid=`id -u` gid=`id -g`: rootful-check
	VIVARIUM_ROOTFUL_UID={{uid}} VIVARIUM_ROOTFUL_GID={{gid}} \
		docker compose -f compose.yaml -f examples/compose.rootful.yaml run --rm vivarium keeper manifest

_smoke:
	VIVARIUM_EXPECTED_USER=root VIVARIUM_EXPECTED_UID=0 VIVARIUM_EXPECTED_HOME=/root tests/smoke.sh

smoke: rootless-check _smoke

build-rootful uid=`id -u` gid=`id -g`: rootful-check
	VIVARIUM_ROOTFUL_UID={{uid}} VIVARIUM_ROOTFUL_GID={{gid}} \
		docker compose -f compose.yaml -f examples/compose.rootful.yaml build

smoke-rootful uid=`id -u` gid=`id -g`: rootful-check
	COMPOSE_FILE=compose.yaml:examples/compose.rootful.yaml \
		VIVARIUM_ROOTFUL_UID={{uid}} VIVARIUM_ROOTFUL_GID={{gid}} \
		VIVARIUM_EXPECTED_USER=agent VIVARIUM_EXPECTED_UID={{uid}} \
		VIVARIUM_EXPECTED_HOME=/home/agent \
		tests/smoke.sh

identity-contract:
	docker build --quiet --target identity . >/dev/null
	docker build --quiet --target identity \
		--build-arg USERNAME=agent --build-arg USER_UID=1000 --build-arg USER_GID=1000 \
		--build-arg USER_HOME=/home/agent . >/dev/null
	! docker build --quiet --target identity \
		--build-arg USERNAME=agent --build-arg USER_UID=0 --build-arg USER_GID=0 \
		--build-arg USER_HOME=/home/agent . >/dev/null 2>&1
	! docker build --quiet --target identity \
		--build-arg USERNAME=root --build-arg USER_UID=1000 --build-arg USER_GID=1000 \
		--build-arg USER_HOME=/root . >/dev/null 2>&1

security-contract:
	printf '%s\n' '["name=rootless"]' | just _rootless-option-check
	printf '%s\n' '["name=seccomp","name=rootless","name=cgroupns"]' | just _rootless-option-check
	! printf '%s\n' '["name=seccomp"]' | just _rootless-option-check >/dev/null 2>&1
	printf '%s\n' '["name=seccomp"]' | just _rootful-option-check
	! printf '%s\n' '["name=rootless"]' | just _rootful-option-check >/dev/null 2>&1
	! printf '' | just _rootful-option-check >/dev/null 2>&1

shell: rootless-check
	docker compose run --rm vivarium

shell-rootful uid=`id -u` gid=`id -g`: rootful-check
	VIVARIUM_ROOTFUL_UID={{uid}} VIVARIUM_ROOTFUL_GID={{gid}} \
		docker compose -f compose.yaml -f examples/compose.rootful.yaml run --rm vivarium

shellcheck:
	shellcheck {{scripts}}

hadolint:
	docker run --rm -i -v "$PWD/.hadolint.yaml:/.hadolint.yaml:ro" {{hadolint_image}} hadolint --config /.hadolint.yaml - < Dockerfile

yamllint:
	yamllint .

lint: shellcheck hadolint yamllint

fmt:
	shfmt -w {{scripts}}

fmt-check:
	shfmt -d {{scripts}}

ci: lint security-contract identity-contract build smoke
