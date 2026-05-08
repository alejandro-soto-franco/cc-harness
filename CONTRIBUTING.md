# Contributing to cc-harness

Thanks for the interest. cc-harness is a single bash script with a bats test
suite; the contribution loop is short.

## Dev setup

```bash
git clone https://github.com/alejandro-soto-franco/cc-harness
cd cc-harness
git submodule update --init --recursive   # bats-core
```

Required tools:

- `bash` 3.2+ (macOS system bash is 3.2; we test against it)
- `tmux` 3.0+
- `shellcheck` 0.9+
- `shfmt` 3.x (for `make fmt` / `make fmt-check`)
- `pandoc` (only for `make man`)
- `fpm` (only for `make deb` / `make rpm`)

## Workflow

```bash
make test          # bats suite
make lint          # shellcheck
make fmt-check     # shfmt diff against tracked files
```

CI runs lint + fmt-check + bats on `{ubuntu-latest, macos-latest}` with both
bash 3.2 and bash 5.2; if you change anything that touches associative
arrays, `mapfile`, `[[ -v ]]`, `${var,,}`, or BSD-vs-GNU userspace
differences, run those tests locally first.

## Bash 3.2 portability

macOS still ships bash 3.2. To stay portable:

- No associative arrays (`declare -A`); use parallel arrays or files.
- No `mapfile` / `readarray`; use `while IFS= read -r ...`.
- No `${var^^}` / `${var,,}`; use `tr '[:upper:]' '[:lower:]'`.
- No `[[ -v var ]]`; use `[[ -n "${var-}" ]]` or `${var:-default}`.
- No `wait -n`. No `coproc`.

Where a feature genuinely needs bash 4+, gate it behind a runtime check and
print a clear error rather than silently breaking.

## Commit format

[Conventional Commits](https://www.conventionalcommits.org/):
`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`. Bodies should
explain *why*; the diff already shows *what*.

## PR checklist

- [ ] Tests for new behavior (happy path + at least one error path)
- [ ] `make lint` clean (or inline `# shellcheck disable=SCxxxx # reason`)
- [ ] `make fmt-check` clean
- [ ] Docs updated for any user-facing change (man page, README,
      per-subcommand `_help_<name>`)
- [ ] No new dependencies without discussion

## DCO

Sign off your commits with `git commit -s` (Developer Certificate of Origin).
This stays even if/when we add other governance later.

## Filing bugs

`cc-harness doctor` output goes a long way. Include:

- `cc-harness --version`
- `tmux -V`
- OS / shell
- Minimal projects.conf to reproduce
- Exact command run
