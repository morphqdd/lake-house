# myapp_with_deps

Smoke project demonstrating lake-house's dep injection.

`lake.house` declares two deps with different source shapes:

```
dep "demo-lib"    "0.0.1" path "deps/demo-lib"
dep "unknown-pkg" "0.0.1"
```

The first is a path-override — `lake-house` skips the cache and
points `DEMO_LIB_PATH` directly at `deps/demo-lib/`.

The second is a **bare version**: no `git+` prefix, no `path`
override.  That triggers the registry resolution flow:

1. Check `~/.lake/libs/unknown-pkg/0.0.1/` — miss.
2. Clone / refresh `~/.lake/index/` from `$LAKE_REGISTRY`
   (or `registry "<url>"` line in `lake.house`, or the default
   `https://github.com/morphqdd/lake-registry.git`).
3. Read `packages/u/unknown-pkg.lake` — missing → error
   `house: package not in registry: unknown-pkg`.

The placeholder bare-version dep deliberately fails resolution
so the smoke test exercises the full lookup path without
depending on a real registry entry.

`src/main.lake` imports `+demo_lib.greet.{ hello }`.  Note the
underscore — lake-frontend's loader matches the env var
`DEMO_LIB_PATH` by lowercasing the suffix and treating that as
the first import segment.

## Run (path-only)

Remove the bare-version dep to build successfully:

```sh
house build      # writes src/build/main
./src/build/main # prints "hello from demo-lib!"
```

## Run (registry smoke)

With the bare-version dep present, `house build` will:

```
[deps] cloning registry index
…clone log…
house: package not in registry:
  unknown-pkg
```

Override the registry URL:

```sh
LAKE_REGISTRY=file:///path/to/local-registry house build
```

Or per-project — add to `lake.house`:

```
registry "https://my-host/lake-registry.git"
```

Precedence (highest first): `LAKE_REGISTRY` env, manifest
`registry` line, default public registry.
