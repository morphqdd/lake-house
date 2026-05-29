# lake-house

`house` — minimal project & build tool for Lake.  Built **in Lake**,
dogfooding the experimental stdlib (`std.experimental.fs`,
`std.experimental.process`).  Until pluggable subcommands land, new
commands ship as new source files compiled into the binary.

## Commands

| command                 | what it does                                 |
|-------------------------|----------------------------------------------|
| `house new <name>`      | scaffold a new project directory             |
| `house build`           | install deps + run `lakec` on `entry`        |
| `house run`             | `build` + exec the produced binary           |
| `house test`            | build + run `tests/main.lake` (exit 0 = pass)|
| `house publish`         | open a fork+PR against the registry          |
| `house add <pkg> <ver>` | resolve + pin a registry dep into the project|
| `house help`            | print usage                                  |

## Manifest (`lake.house`)

Whitespace-delimited, line-based.  Quoted strings can contain spaces:

```
project "myapp" "0.1.0"
entry   "src/main.lake"

dep "lake-rails" "0.1.0"
dep "marine"     "git+https://github.com/morphqdd/marine#dev"
dep "lash"       "0.2.0" path "/abs/path/to/lash"

env  "DATABASE_URL" "postgres://localhost/dev"
flag "--release"
```

Parsed by `house` directly — no Lake-eval round-trip; the file is
*Lake-flavoured* but read as ASCII tokens.

### `env` and `flag` lines

| line                  | effect                                                  |
|-----------------------|---------------------------------------------------------|
| `env "KEY" "VALUE"`   | injected into the spawned `lakec`'s environment as `KEY=VALUE` |
| `flag "<arg>"`        | appended to the `lakec` CLI argv (one token per line)   |

`env` entries join the auto-injected `<LIBNAME>_PATH` dep roots and
`LAKE_PATH` in the child envp.  `flag` lines pass compiler options
through — e.g. `flag "--release"` builds in release mode, `flag "-O"`
+ `flag "speed"` sets the opt level (each token is a separate line).

### Dep source shapes

| shape                              | resolution                                       |
|------------------------------------|--------------------------------------------------|
| `"0.1.0"`                          | semver — registry not yet wired (errors at install) |
| `"git+<url>#<ref>"`                | `git clone --depth 1 --branch <ref> <url> <dir>` |
| `"<ver>" path "<override-path>"`   | use `<override-path>` verbatim, no install        |

## Dep cache

Git-source deps land in:

```
~/.lake/libs/<name>/<ref>/
```

`is_installed` does a read-only `open(2)` on the cache dir to
decide whether to skip the clone — no lockfile yet; concurrent
`house build` invocations on the same dep are not protected.

## Env-var injection

Before spawning `lakec`, `house` builds an envp containing:

* every existing parent env entry (so `PATH`, `HOME`, etc. are
  inherited),
* one `<LIBNAME>_PATH=<resolved-dir>` per declared dep (override
  path wins over cache path),
* `LAKE_PATH=/home/morphe/compiler/lake-stdlib`.

The uppercasing rule: lowercase ASCII -> upper, `-` and `.` -> `_`.
So `dep "demo-lib" ...` produces `DEMO_LIB_PATH=...`.
lake-frontend's loader (`SearchPaths::from_env` in
`lake-frontend/src/loader.rs`) lowercases the suffix and uses it
as a per-library root keyed by the first import segment.  That's
why imports use the *underscored* form:

```
+demo_lib.greet.{ hello }
```

## Building

```sh
LAKE_PATH=../lake-stdlib lakec src/main.lake
```

## Publishing

`house publish` runs from inside a project directory and opens a
pull request against the registry.  Non-owners always go through
the fork+PR flow; registry admins are routed the same way unless
`LAKE_HOUSE_DIRECT_PUSH=1` is set (kept as an opt-in shortcut for
rapid iteration).

Flow:

1. read `lake.house`, parse name + version + optional `registry "<url>"`,
2. refresh `~/.lake/index/` from the picked registry URL (env
   `LAKE_REGISTRY` > manifest `registry` > built-in default),
3. capture `git config --get remote.origin.url` (the dep's git url),
4. capture `git describe --tags --exact-match` (preferred) or
   `git rev-parse HEAD` (fallback) for the rev,
5. check ownership via
   `gh repo view <owner>/<repo> --json viewerCanAdminister`,
6. if owner + `LAKE_HOUSE_DIRECT_PUSH=1`: write into the local index
   clone and `git push origin HEAD` (legacy path).
7. otherwise (default): `gh repo fork`, clone the fork into
   `~/.lake/index-fork-<gh-user>/`, hard-reset to `origin/master`,
   branch `publish/<name>-<version>`, edit
   `packages/<f>/<name>.lake`, commit, push with
   `--force-with-lease`, then `gh pr create --base master`.

Non-`github.com` registry URLs fall back to the direct-push path
with a warning since `gh` only knows GitHub.

Capturing process output: `std.experimental.process.run3` inherits
the parent's stdio, so `house` redirects each `gh`/`git` command's
stdout into `/tmp/lake-house-<stem>-<pid>` via
`/bin/sh -c "<cmd> > <file>"` (see `src/cmd/git_capture.lake`).

If any `gh`/`git` step fails (auth, sandbox, offline), `house`
prints a manual runbook with the exact commands needed to finish
the publish by hand.

## Adding a dep

`house add <pkg> <ver>` resolves a package from the registry,
appends a `dep "<pkg>" "<ver>"` line to the current project's
`lake.house`, clones the dep into the cache, captures the resolved
HEAD SHA, and rewrites `lake.lock`.

## Lockfile

`house build` reads `lake.lock` if present.  When every dep listed
in `lake.house` has a matching entry in the lock, builds skip the
registry-index refresh and use the lock's pinned `(url, ref, sha)`
directly.  Any miss falls back to the registry resolver; the lock
is rewritten at the end of the build so the next run is fast.

Lockfile format (Lake-flavoured, same tokeniser as `lake.house`):

```
# Auto-generated by house — do not edit.
project "myapp" "0.1.0"
dep "hello-world-pkg" "0.1.0" git "https://github.com/morphqdd/hello-world-pkg.git" rev "v0.1.0" sha "cd0ffd464e3d434bf4b670696fb73dad681416df"
```

## Example

See [`examples/myapp_with_deps/`](examples/myapp_with_deps) — a
path-override dep + smoke `main.lake`.
