# myapp_with_deps

Smoke project demonstrating lake-house's dep injection.

`lake.house` declares one path-override dep:

```
dep "demo-lib" "0.0.1" path "deps/demo-lib"
```

`src/main.lake` imports `+demo_lib.greet.{ hello }`.  Note the
underscore — lake-frontend's loader matches the env var
`DEMO_LIB_PATH` by lowercasing the suffix and treating that as
the first import segment, so the dep name's `-` is normalised to
`_` at the import site.

## Run

From this directory:

```sh
house build      # writes src/build/main
./src/build/main # prints "hello from demo-lib!"
```

Under the hood `house build` sets:

```
DEMO_LIB_PATH=deps/demo-lib
LAKE_PATH=/home/morphe/compiler/lake-stdlib
```

before invoking `lakec src/main.lake`.
