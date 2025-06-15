## Debug

### Implementation Goal: `tinydbg debug ./path-to`

The attach operation is used to debug a program that is already running, or to wait for a program to start running using --waitfor before debugging. The exec operation is used to debug a compiled Go executable. The debug operation first compiles the source code's main package and then executes logic similar to exec. Why create a separate debug operation when go build is so simple?

From an implementation perspective, debug doesn't require much more coding work than exec. Its main purpose is to simplify the debugging experience:
1) Software debugging relies on debug information generation. We must tell the compiler to generate debug information, and this applies to all modules used;
2) The compiler optimizes code, such as function inlining. If debug information generation doesn't account for these optimizations, debugging can be problematic, so inlining is typically disabled;
Usually, you need to specify compilation options like this: `go build -gcflags 'all=-N -l'` - isn't this command a bit cumbersome to type?

The debug command simplifies this workflow. Let's take a look:

```bash
$ tinydbg help debug
Compiles your program with optimizations disabled, starts and attaches to it.

By default, with no arguments, Delve will compile the 'main' package in the
current directory, and begin to debug it. Alternatively you can specify a
package name and Delve will compile that package instead, and begin a new debug
session.

Usage:
  tinydbg debug [package] [flags]

Flags:
      --continue        Continue the debugged process on start.
  -h, --help            help for debug
      --output string   Output path for the binary.
      --tty string      TTY to use for the target program

Global Flags:
      --accept-multiclient               Allows a headless server to accept multiple client connections via JSON-RPC.
      --allow-non-terminal-interactive   Allows interactive sessions of Delve that don't have a terminal as stdin, stdout and stderr
      --build-flags string               Build flags, to be passed to the compiler. For example: --build-flags="-tags=integration -mod=vendor -cover -v"
      --disable-aslr                     Disables address space randomization
      --headless                         Run debug server only, in headless mode. Server will accept JSON-RPC client connections.
      --init string                      Init file, executed by the terminal client.
  -l, --listen string                    Debugging server listen address. Prefix with 'unix:' to use a unix domain socket. (default "127.0.0.1:0")
      --log                              Enable debugging server logging.
      --log-dest string                  Writes logs to the specified file or file descriptor (see 'dlv help log').
      --log-output string                Comma separated list of components that should produce debug output (see 'dlv help log')
  -r, --redirect stringArray             Specifies redirect rules for target process (see 'dlv help redirect')
      --wd string                        Working directory for running the program.
```

Since compilation is involved here, and `go build --tags=?` supports compiling source code with specific build tags, the debug operation also needs an option `--build-tags=` to work with it. We've covered the other options earlier.

### Basic Knowledge

The debug operation mainly ensures that the correct compilation options are passed during compilation to guarantee that the compiler and linker generate DWARF debug information, enabling smooth debugging.

Nothing else is particularly special. OK, let's look at the code implementation.

### Code Implementation

```bash
main.go:main.main
    \--> cmds.New(false).Execute()
            \--> debugCommand.Run()
                    \--> debugCmd(...)
                            \--> buildBinary
                            \--> execute(0, processArgs, conf, "", debugger.ExecutingGeneratedFile, dlvArgs, buildFlags)
                                    \--> server := rpccommon.NewServer(...)
                                    \--> server.Run()
                                            \--> debugger, _ := debugger.New(...)
                                                if attach startup: debugger.Attach(...)
                                                elif core startup: core.OpenCore(...)
                                                else others: debugger.Launch(...)
                                            \--> c, _ := listener.Accept() 
                                            \--> serveConnection(conn)
```

The operation to build the executable is as follows. This function actually supports building both main modules and test packages (isTest), but our demo tinydbg aims to be as simple as possible, and the only difference between tinydbg debug and tinydbg test is this, so we removed the test command from our demo tinydbg.

```go
func buildBinary(cmd *cobra.Command, args []string, isTest bool) (string, bool) {
    // Determine the output filename:
    // main module, go build output is __debug_bin
    // test package, uses go test -c filename method
	if isTest {
		debugname = gobuild.DefaultDebugBinaryPath("debug.test")
	} else {
		debugname = gobuild.DefaultDebugBinaryPath("__debug_bin")	
    }

    // Execute build operation go build or go test -c, with appropriate compilation options
	err = gobuild.GoBuild(debugname, args, buildFlags)
	if err != nil {
		if outputFlag == "" {
			gobuild.Remove(debugname)
		}
		fmt.Fprintf(os.Stderr, "%v\n", err)
		return "", false
	}
	return debugname, true
}

// GoBuild builds non-test files in 'pkgs' with the specified 'buildflags'
// and writes the output at 'debugname'.
func GoBuild(debugname string, pkgs []string, buildflags string) error {
	args := goBuildArgs(debugname, pkgs, buildflags, false)
	return gocommandRun("build", args...)
}
```

After the debug command successfully completes the build, it executes debugger.Launch(...) just like the exec command, completing ASLR-related settings before process startup, then setting up PTRACEME-related configurations for the forked child process, and finally starting the process. After the process starts, it continues with necessary initialization actions, such as reading binary file information and using ptrace to control all existing threads and any threads that may be created in the future. We'll summarize it briefly here without going into too much detail.

### Testing

Skipped

### Summary

This article introduced the implementation principles and usage methods of the `tinydbg debug` command. The main purpose of this command is to simplify the Go program debugging process by automatically adding necessary compilation options (such as `-gcflags 'all=-N -l'`) to ensure correct debug information generation and disable inlining optimizations. The debug command first compiles the source code (supporting build tags control through `--build-tags` if needed) and then executes initialization logic similar to exec, initializing the debugger to start and attach to the process, control process threads, and initialize the debugger's network layer communication.
