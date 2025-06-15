## Extended Reading: Introduction to the Go Compiler

`cmd/compile` contains the main packages that make up the Go compiler. The compiler can be logically divided into four phases, and we will briefly describe each phase and list the packages containing their code.

You may have heard the terms "front-end" and "back-end". Roughly speaking, they correspond to the first two phases and the last two phases we list. A third term, "middle-end", typically refers to most of the work done in the second phase.

Note that the `go/*` series of packages (such as `go/parser` and `go/types`) are primarily used by the compiler's internal API. Since the compiler was originally written in C, the `go/*` packages were developed for writing tools that process Go code (like `gofmt` and `vet`). However, over time, the compiler's internal API has gradually evolved to be more in line with the habits of `go/*` package users.

To clarify, "gc" stands for "Go compiler" and is unrelated to the uppercase "GC" that represents garbage collection.

### 1. Parsing

* `cmd/compile/internal/syntax` (lexer, parser, syntax tree)

The first phase of compilation tokenizes (lexical analysis) and parses (syntax analysis) the source code, building a syntax tree for each source file.

Each syntax tree is an exact representation of the corresponding source file, with nodes corresponding to various elements of the source code (such as expressions, declarations, and statements). The syntax tree also includes position information used for error reporting and debug information generation.

### 2. Type checking

* `cmd/compile/internal/types2` (type checking)

The `types2` package is a version of `go/types` ported to use the AST from the `syntax` package instead of `go/ast`.

### 3. IR construction ("noding")

* `cmd/compile/internal/types` (compiler types)
* `cmd/compile/internal/ir` (compiler AST)
* `cmd/compile/internal/noder` (creating compiler AST)

The compiler's middle-end uses its own AST definition and Go type representation (derived from the C version). The next step after type checking is to convert the `syntax` and `types2` representations to `ir` and `types`. This process is called "noding".

The node representation is built using a technique called Unified IR, which is based on a serialized version of the type-checked code from phase 2. Unified IR also participates in package import/export and inlining optimizations.

### 4. Middle-end optimizations

* `cmd/compile/internal/inline` (function call inlining)
* `cmd/compile/internal/devirtualize` (devirtualization of known interface method calls)
* `cmd/compile/internal/escape` (escape analysis)

Multiple optimization processes are performed on the IR representation:

- Dead code elimination
- (Early) devirtualization
- Function call inlining
- Escape analysis

Early dead code elimination is integrated into the Unified IR writing phase.

### 5. Walk

* `cmd/compile/internal/walk` (evaluation order, desugaring)

The final processing step for the IR representation is "walk", which:

1. Breaks down complex statements into simple ones, introducing temporary variables and maintaining evaluation order (also known as the "order" phase)
2. Desugars high-level Go constructs into primitive forms. For example:
   - `switch` statements are converted to binary search or jump tables
   - map and channel operations are replaced with runtime calls

### 6. Generic SSA

* `cmd/compile/internal/ssa` (SSA passes and rules)
* `cmd/compile/internal/ssagen` (converting IR to SSA)

In this phase, the IR is converted to Static Single Assignment (SSA) form, a low-level intermediate representation with specific properties that facilitate optimization and final machine code generation.

During the conversion, intrinsics are applied - special functions that the compiler replaces with highly optimized code for specific cases. Some nodes are also lowered to simpler components (e.g., the `copy` built-in function is replaced with memory moves, `range` loops are rewritten as `for` loops). For historical reasons, some conversions currently happen before SSA conversion, but the long-term plan is to centralize all conversions in this phase.

This is followed by a series of machine-independent passes and rules, including:

- Dead code elimination
- Removal of redundant nil pointer checks
- Removal of unused branches

Generic rewrite rules mainly involve expression optimization, such as replacing certain expressions with constants, optimizing multiplication and floating-point operations.

### 7. Generating machine code

* `cmd/compile/internal/ssa` (SSA lowering and architecture-specific passes)
* `cmd/internal/obj` (machine code generation)

The compiler's machine-specific phase begins with the "lower" pass, which rewrites generic values into their machine-specific variants. For example, on the amd64 architecture, memory operands are allowed, so many load-store operations can be combined.

Note that the lowering pass runs all machine-specific rewrite rules, so it currently also performs many optimizations.

Once the SSA is "lowered" and specialized for the target architecture, final code optimization passes are run, including:

- Another dead code elimination
- Moving values closer to their use
- Removing local variables that are never read
- Register allocation

Other important work in this step includes:

- Stack frame layout (allocating stack offsets for local variables)
- Pointer liveness analysis (computing the liveness state of stack pointers at each GC safe point)

At the end of the SSA generation phase, Go functions have been converted to a series of `obj.Prog` instructions. These instructions are passed to the assembler (`cmd/internal/obj`), which converts them to machine code and outputs the final object file. The object file will also contain reflection data, export data, and debug information.

### 7a. Export

In addition to writing object files for the linker, the compiler also writes "export data" files for downstream compilation units. The export data contains the following information computed when compiling package P:

- Type information for all exported declarations
- IR for inlinable functions
- IR for generic functions that might be instantiated in other packages
- Summary of function parameter escape analysis results

The export data format has gone through several iterations, with the current version called "unified", which is a serialized representation of the object graph with indices that allow lazy decoding of parts of the content (since most imports are only used to provide a few symbols).

The GOROOT repository contains readers and writers for the unified format; it encodes and decodes to/from the compiler's IR. The `golang.org/x/tools` repository also provides a public API for export data readers (using `go/types` representation), always supporting the compiler's current file format and a few historical versions. (`x/tools/go/packages` uses it when type information is needed but syntax patterns with type annotations are not.)

The `x/tools` repository also provides a public API for export type information (type information only) using the older "index format". (For example, `gopls` uses this version to store workspace information databases, which include type information.)

Export data typically provides "deep" summaries, so compiling package Q only needs to read the export data file for each direct import to ensure these files provide all necessary information for indirect imports (such as methods and struct fields of types referenced in P's public API). Deep export data simplifies the build system because each direct dependency only needs one file. However, when high in the import graph of a large repository, this leads to export data bloat: if there are common types with large APIs, almost every package's export data will contain copies. This issue drove the development of the "index" design, which allows partial loading on demand.

### 8. Practical Tips

#### Getting Started

* If you've never contributed to the compiler, a simple approach is to add logging statements or `panic("here")` at interesting locations to get an initial understanding of the problem.
* The compiler itself provides logging, debugging, and visualization capabilities:
  ```bash
  $ go build -gcflags=-m=2                   # Print optimization information (including inlining, escape analysis)
  $ go build -gcflags=-d=ssa/check_bce/debug # Print bounds check information
  $ go build -gcflags=-W                     # Print internal parse tree after type checking
  $ GOSSAFUNC=Foo go build                   # Generate ssa.html file for function Foo
  $ go build -gcflags=-S                     # Print assembly code
  $ go tool compile -bench=out.txt x.go      # Print timing information for compiler phases
  ```
* Some flags change compiler behavior, for example:
  ```bash
  $ go tool compile -h file.go               # Panic on first compilation error
  $ go build -gcflags=-d=checkptr=2          # Enable additional unsafe pointer checks
  ```
* More flag details can be obtained via:
  ```bash
  $ go tool compile -h              # View compiler flags (like -m=1 -l)
  $ go tool compile -d help         # View debug flags (like -d=checkptr=2)
  $ go tool compile -d ssa/help     # View SSA flags (like -d=ssa/prove/debug=2)
  ```

#### Testing Changes

* Be sure to read the [Quick Testing Changes](https://go.dev/doc/contribute#quick_test) section.
* Some tests are in the `cmd/compile` package and can be run with `go test ./...`, but many tests are in the top-level [test](https://github.com/golang/go/tree/master/test) directory:

  ```bash
  $ go test cmd/internal/testdir                           # Run all tests in the 'test' directory
  $ go test cmd/internal/testdir -run='Test/escape.*.go'   # Run tests matching a pattern
  ```

  See the [testdir README](https://github.com/golang/go/tree/master/test#readme) for details.
  The `errorCheck` method in `testdir_test.go` helps parse the `ERROR` comments used in tests.
* The new [application-based coverage analysis](https://go.dev/testing/coverage/) can be used with the compiler:

  ```bash
  $ go install -cover -coverpkg=cmd/compile/... cmd/compile  # Build compiler with coverage instrumentation
  $ mkdir /tmp/coverdir                                      # Choose location for coverage data
  $ GOCOVERDIR=/tmp/coverdir go test [...]                   # Use compiler and save coverage data
  $ go tool covdata textfmt -i=/tmp/coverdir -o coverage.out # Convert to traditional coverage format
  $ go tool cover -html coverage.out                         # View coverage with traditional tools
  ```

#### Handling Compiler Versions

* Many compiler tests use the `go` command in `$PATH` and its corresponding `compile` binary.
* If you're in a branch and `$PATH` includes `<go-repo>/bin`, running `go install cmd/compile` will build the compiler using the branch code and install it in the correct location for subsequent `go` commands to use the new compiler.
* [toolstash](https://pkg.go.dev/golang.org/x/tools/cmd/toolstash) provides functionality to save, run, and restore known good versions of the Go toolchain. For example:

  ```bash
  $ go install golang.org/x/tools/cmd/toolstash@latest
  $ git clone https://go.googlesource.com/go
  $ cd go
  $ git checkout -b mybranch
  $ ./src/all.bash               # Build and confirm good starting point
  $ export PATH=$PWD/bin:$PATH
  $ toolstash save               # Save current toolchain
  ```

  The edit/compile/test cycle after that is similar:

  ```bash
  <... modify cmd/compile source ...>
  $ toolstash restore && go install cmd/compile   # Restore known good toolchain and build compiler
  <... 'go build', 'go test', etc. ...>           # Test with new compiler
  ```
* `toolstash` also allows comparing the installed compiler with the stored version, for example to verify behavior consistency after refactoring:

  ```bash
  $ toolstash restore && go install cmd/compile   # Build latest compiler
  $ go build -toolexec "toolstash -cmp" -a -v std # Compare std library generated by old and new compilers
  ```
* If versions are out of sync (e.g., `linked object header mismatch` error), you can run:

  ```bash
  $ toolstash restore && go install cmd/...
  ```

#### Other Useful Tools

* [compilebench](https://pkg.go.dev/golang.org/x/tools/cmd/compilebench) is used for benchmarking compiler speed.
* [benchstat](https://pkg.go.dev/golang.org/x/perf/cmd/benchstat) is the standard tool for reporting performance changes from compiler modifications:
  ```bash
  $ go test -bench=SomeBenchmarks -count=20 > new.txt   # Test with new compiler
  $ toolstash restore                                   # Restore old compiler
  $ go test -bench=SomeBenchmarks -count=20 > old.txt   # Test with old compiler
  $ benchstat old.txt new.txt                           # Compare results
  ```
* [bent](https://pkg.go.dev/golang.org/x/benchmarks/cmd/bent) makes it easy to run benchmark suites from community Go projects in Docker containers.
* [perflock](https://github.com/aclements/perflock) improves benchmark consistency by controlling CPU frequency and other means.
* [view-annotated-file](https://github.com/loov/view-annotated-file) can overlay inlining, bounds check, and escape information on source code.
* [godbolt.org](https://go.godbolt.org) is widely used to view and share assembly output, supporting comparison of assembly code from different Go compiler versions.

---

### Further Reading

For a deeper understanding of how the SSA package works (including its passes and rules), see [cmd/compile/internal/ssa/README.md](internal/ssa/README.md).

If anything in this document or the SSA README is unclear, or if you have suggestions for improvements, please leave a comment in [issue 30074](https://go.dev/issue/30074).
