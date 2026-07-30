set shell := ["sh", "-eu", "-c"]
set dotenv-filename := ".env.local"

scripts := "rootfs/usr/local/bin/keeper rootfs/usr/local/bin/transcribe-audio rootfs/usr/local/bin/vivarium-entrypoint tests/smoke.sh"
hadolint_image := "hadolint/hadolint:v2.14.0"

default:
	just --list

build:
	docker compose build

doctor:
	docker compose run --rm vivarium keeper doctor

manifest:
	docker compose run --rm vivarium keeper manifest

smoke:
	tests/smoke.sh

shell:
	docker compose run --rm vivarium

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

ci: lint build smoke
