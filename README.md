<div align="center">
  <picture>
    <img alt="Zig-DbC Logo" src="logo.svg" height="20%" width="20%">
  </picture>
<br>

<h2>Zig-DbC</h2>

[![Tests](https://img.shields.io/github/actions/workflow/status/habedi/zig-dbc/tests.yml?label=tests&style=flat&labelColor=282c34&logo=github)](https://github.com/habedi/zig-dbc/actions/workflows/tests.yml)
[![CodeFactor](https://img.shields.io/codefactor/grade/github/habedi/zig-dbc?label=code%20quality&style=flat&labelColor=282c34&logo=codefactor)](https://www.codefactor.io/repository/github/habedi/zig-dbc)
[![Zig Version](https://img.shields.io/badge/Zig-0.14.1-orange?logo=zig&labelColor=282c34)](https://ziglang.org/download/)
[![Docs](https://img.shields.io/github/v/tag/habedi/zig-dbc?label=docs&color=blue&style=flat&labelColor=282c34&logo=read-the-docs)](https://habedi.github.io/zig-dbc/)
[![Release](https://img.shields.io/github/release/habedi/zig-dbc.svg?label=release&style=flat&labelColor=282c34&logo=github)](https://github.com/habedi/zig-dbc/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-007ec6?label=license&style=flat&labelColor=282c34&logo=open-source-initiative)](https://github.com/habedi/zig-dbc/blob/main/LICENSE)

A Design by Contract Library for Zig

</div>

---

Zig-DbC is a small library that provides a collection of functions to use
[design by contract](https://en.wikipedia.org/wiki/Design_by_contract) (DbC) principles in software written in Zig
programming language.
It provides a simple and idiomatic API for defining *preconditions*, *postconditions*, and *invariants* that can be
checked at runtime.

A common use case for DbC (and by extension Zig-DbC) is adding checks that guarantee the code behaves as intended.
This can be especially useful, for example, during the implementation of complex data structures and algorithms
(like balanced trees and graphs) where correctness depends on specific conditions being met.

### Features

* **Explicit Contracts**: A simple API to define `preconditions`, `postconditions`, and `invariants`
* **Zero-Cost**: In `ReleaseFast` mode, all contract checks are removed at compile time
* **Safety-Focused**: Contracts are active in `Debug`, `ReleaseSafe`, and `ReleaseSmall` modes to catch bugs early
* **Error Handling**: The `contract` function passes errors from your code to the caller
* **Error Tolerance**: An optional mode to handle partial state changes in functions that can return errors

> [!IMPORTANT]
> Zig-DbC is in early development, so bugs and breaking API changes are expected.
> Please use the [issues page](https://github.com/habedi/zig-dbc/issues) to report bugs or request features.

---

### Getting Started

You can add Zig-DbC to your project and start using it by following the steps below.

#### Installation

Run the following command in the root directory of your project to download Zig-DbC:

```sh
zig fetch --save=dbc "https://github.com/habedi/zig-dbc/archive/<branch_or_tag>.tar.gz"
```

Replace `<branch_or_tag>` with the desired branch or tag, like `main` (for the development version) or `v0.1.0`
(for the latest release).
This command will download zig-dbc and add it to Zig's global cache and update your project's `build.zig.zon` file.

#### Adding to Build Script

Next, modify your `build.zig` file to make zig-dbc available to your build target as a module.

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "your-zig-program",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 1. Get the dependency object from the builder
    const zig_dbc_dep = b.dependency("dbc", .{});

    // 2. Get Zig-DbC's top-level module
    const zig_dbc_module = zig_dbc_dep.module("dbc");

    // 3. Add the module to your executable so you can @import("zig-dbc")
    exe.root_module.addImport("dbc", zig_dbc_module);

    b.installArtifact(exe);
}
```

#### Using Zig-DbC in Your Code

Finally, you can `@import("dbc")` and start using it in your Zig code.

```zig
const dbc = @import("dbc");

pub fn MyStruct() type {
    return struct {
        const Self = @This();
        field: i32,
        is_ready: bool,

        fn invariant(self: Self) void {
            dbc.require(self.field > 0, "Field must always be positive");
        }

        pub fn doSomething(self: *Self) !void {
            const old = .{ .field = self.field };
            return dbc.contract(self, @TypeOf(old), old, struct {
                fn run(ctx: @TypeOf(old), s: *Self) !void {
                    // Precondition
                    dbc.require(s.is_ready, "Struct not ready");

                    // ... method logic ...
                    s.field += 1;

                    // Postcondition
                    dbc.ensure(s.field > ctx.field, "Field must increase");
                }
            }.run);
        }
    };
}
```

---

### Documentation

You can find the API documentation for the latest release of Zig-DbC [here](https://habedi.github.io/zig-dbc/).

Alternatively, you can use the `make docs` command to generate the documentation for the current version of Zig-DbC.
This will generate HTML documentation in the `docs/api` directory, which you can serve locally with `make serve-docs`
and view in a web browser.

### Examples

Check out the [examples](examples/) directory for example usages of Zig-DbC.

---

### Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to make a contribution.

### License

Zig-DbC is licensed under the MIT License (see [LICENSE](LICENSE)).

### Acknowledgements

* The chain links logo is from [SVG Repo](https://www.svgrepo.com/svg/9153/chain-links).
