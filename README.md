# lake-house

`house` — minimal project & build tool for Lake.  Built **in Lake**,
dogfooding the experimental stdlib (`std.experimental.fs`,
`std.experimental.process`).  Until pluggable subcommands land, new
commands ship as new source files compiled into the binary.

## Commands (planned)

| command                 | what it does                                 |
|-------------------------|----------------------------------------------|
| `house new <name>`      | scaffold a new project directory             |
| `house build`           | run `lakec` on the manifest's `entry`        |
| `house run`             | `build` + exec the produced binary           |
| `house help`            | print usage                                  |

## Manifest (`lake.house`)

Whitespace-delimited, line-based.  Quoted strings can contain spaces:

```
project "myapp" "0.1.0"
entry   "src/main.lake"

dep "lake-rails" "0.1.0"
dep "lake-orm"   "0.2.0"
```

Parsed by `house` directly — no Lake-eval round-trip; the file is
*Lake-flavoured* but read as ASCII tokens.

## Building

```sh
LAKE_PATH=../lake-stdlib lakec src/main.lake -o house
```
