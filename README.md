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
| `house publish`         | append current pkg to registry + push        |
| `house help`            | print usage                                  |

## Manifest (`lake.house`)

Whitespace-delimited, line-based.  Quoted strings can contain spaces:

```
project "myapp" "0.1.0"
entry   "src/main.lake"

dep "lake-rails" "0.1.0"
dep "marine"     "git+https://github.com/morphqdd/marine#dev"
dep "lash"       "0.2.0" path "/abs/path/to/lash"
```

Parsed by `house` directly — no Lake-eval round-trip; the file is
*Lake-flavoured* but read as ASCII tokens.

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

`house publish` runs from inside a project directory and appends the
current `project "<name>" "<version>"` to the registry index, then
commits + pushes.  Flow:

1. read `lake.house`, parse name + version + optional `registry "<url>"`,
2. refresh `~/.lake/index/` from the picked registry URL (env
   `LAKE_REGISTRY` > manifest `registry` > built-in default),
3. capture `git config --get remote.origin.url` of the current repo
   (used as the dep's git url),
4. capture `git describe --tags --exact-match` (preferred) or
   `git rev-parse HEAD` (fallback) for the rev,
5. compute the shard path
   `~/.lake/index/packages/<first-letter>/<name>.lake`,
6. refuse if the file already has a `version "<v>"` line for the
   current version,
7. otherwise create the file with a `package "<name>"` header (or
   append a new line if the file exists),
8. `git add` / `commit -m "publish: <name> <v>"` / `push origin HEAD`
   inside the registry checkout.

Capturing process output: `std.experimental.process.run3` inherits
the parent's stdio, so `house` redirects the git command's stdout
into `/tmp/lake-house-<stem>-<pid>` via `/bin/sh -c "<cmd> > <file>"`
and reads the file back (see `src/cmd/git_capture.lake`).

If the push fails (auth, sandbox, offline), `house` prints the
exact `git add` / `commit` / `push` invocations the user can run
manually against the registry checkout.

## Example

See [`examples/myapp_with_deps/`](examples/myapp_with_deps) — a
path-override dep + smoke `main.lake`.
