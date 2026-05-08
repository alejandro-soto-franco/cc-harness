# Security policy

## Supported versions

cc-harness ships from a single branch (`main`); the latest tagged release is
the only supported version.

## Reporting a vulnerability

Please do **not** file public issues for security problems. Email the
maintainer directly:

- **sotofranco.eng@gmail.com**

Include:

- a description of the issue,
- a minimal reproduction (commands, config),
- the impact you see (what an attacker could achieve).

Expect an acknowledgement within 7 days. Fixes ship as patch releases on the
default branch and are noted in [CHANGELOG.md](CHANGELOG.md).

## Scope

The `install.sh` curl-bash flow is the most security-relevant surface:

- It downloads the release tarball and its `.sha256` from `github.com`.
- It verifies the checksum before extracting.
- It runs `make install` against the extracted tree only.

If you find a way to trick that flow (TOCTOU, redirect smuggling, archive
path traversal, anything that lets an attacker land code outside the chosen
prefix), please report it via the channel above.
