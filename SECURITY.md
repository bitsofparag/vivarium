# Security Policy

## Supported Versions

Until the first tagged release, security fixes target `main`.

## Reporting

Do not open public issues for exploitable vulnerabilities.

Use GitHub private vulnerability reporting if it is enabled. Otherwise, contact the maintainer via email at admin[at]bitsofparag.com. Include a minimal reproduction, affected version or digest, and impact. Once the vulnerability is fixed, new releases will be published, and an issue will be created to disclose the vulnerability.

The reporter name will be credited on request.

## Scope

Vivarium reduces accidental host damage by limiting writable mounts. It is not a hardened isolation boundary against a model or process deliberately trying to escape.

For stronger isolation, run the container with a sandboxed runtime such as gVisor or Kata Containers.
