## Exec

### Implementation Goal: `tinydbg exec ./prog`

This section introduces the exec command for starting debugging: `tinydbg exec [executable] [flags]`. The exec operation will execute the executable and automatically attach to the corresponding process. In Chapter 6 where we introduced instruction-level debugging, we demonstrated how to specify the program to launch using exec.Command, how to start the program, and how to automatically trace it with ptrace after launch. If you've forgotten this part, you can review sections 6.1, 6.2, and 6.3.

The exec command in demo tinydbg is essentially revisiting familiar territory, except that tinydbg uses a frontend-backend separated architecture. If we only consider the target layer's control of the tracee in the backend, the key points to note are the same.

```bash
$ tinydbg help exec
Execute a precompiled binary and begin a debug session.

This command will cause Delve to exec the binary and immediately attach to it to
begin a new debug session. Please note that if the binary was not compiled with
optimizations disabled, it may be difficult to properly debug it. Please
consider compiling debugging binaries with -gcflags="all=-N -l" on Go 1.10
or later, -gcflags="-N -l" on earlier versions of Go.

Usage:
  tinydbg exec <path/to/binary> [flags]

Flags:
      --continue     Continue the debugged process on start.
  -h, --help         help for exec
      --tty string   TTY to use for the target program

Global Flags:
      --accept-multiclient               Allows a headless server to accept multiple client connections via JSON-RPC.
      --allow-non-terminal-interactive   Allows interactive sessions of Delve that don't have a terminal as stdin, stdout and stderr
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

Compared to the attach operation, the exec operation adds a `--disable-aslr` option. We'll only introduce this option here, as other options were covered when discussing the attach operation. OK, we introduced ASLR in Chapter 6 on instruction-level debugging. This feature is rarely used, so let's mention it again.

ASLR is an operating system-level security technology that primarily works by randomizing the memory loading positions of programs to increase the difficulty for attackers to predict target addresses and exploit software vulnerabilities. Its core mechanism includes dynamically randomizing the positions of various parts in the process address space, such as executable base addresses, library files, heap, and stack. The Linux kernel enables full address randomization by default, but for executable address randomization, PIE compilation mode must be enabled. While this brings certain security benefits, if you want to perform automated debugging tasks that use instruction addresses for certain operations, ASLR might cause debugging to fail.

Therefore, an option `--disable-aslr` is added here, which will disable all the address space randomization capabilities mentioned above.

### Basic Knowledge

### Code Implementation

The main code execution path is as follows:

```bash
main.go:main.main
    \--> cmds.New(false).Execute()
            \--> execCommand.Run()
                    \--> execute(0, args, conf, "", debugger.ExecutingExistingFile, args, buildFlags)
                            \--> server := rpccommon.NewServer(...)
                            \--> server.Run()
                                    \--> debugger, _ := debugger.New(...)
                                            if attach startup: debugger.Attach(...)
                                            elif core startup: core.OpenCore(...)
                                            else others debuger.Launch(...)
                                    \--> c, _ := listener.Accept() 
                                    \--> serveConnection(conn)
```

Since we've already covered the debugger backend initialization logic, including network communication initialization and debugger initialization, we'll focus directly on the core code here.

For the exec startup method, let's look at the implementation of debugger.Launch(...):

```go
// Launch will start a process with the given args and working directory.
func (d *Debugger) Launch(processArgs []string, wd string) (*proc.TargetGroup, error) {
    ...

	launchFlags := proc.LaunchFlags(0)
	if d.config.DisableASLR {
		launchFlags |= proc.LaunchDisableASLR
	}
    ...

	return native.Launch(processArgs, wd, launchFlags, d.config.TTY, d.config.Stdin, d.config.Stdout, d.config.Stderr)
}

func Launch(cmd []string, wd string, flags proc.LaunchFlags, tty string, stdinPath string, stdoutOR proc.OutputRedirect, stderrOR proc.OutputRedirect) (*proc.TargetGroup, error) {
    ...

    // Input/output redirection setup
	stdin, stdout, stderr, closefn, err := openRedirects(stdinPath, stdoutOR, stderrOR, foreground)
	if err != nil {
		return nil, err
	}
    ...

	dbp := newProcess(0)
    ...
	dbp.execPtraceFunc(func() {
        // Use personality system call to disable address space randomization (only affects current process and its children)
        // Then start our program to be debugged, which will now have address space randomization disabled
		if flags&proc.LaunchDisableASLR != 0 {
			oldPersonality, _, err := syscall.Syscall(sys.SYS_PERSONALITY, personalityGetPersonality, 0, 0)
			if err == syscall.Errno(0) {
				newPersonality := oldPersonality | _ADDR_NO_RANDOMIZE
				syscall.Syscall(sys.SYS_PERSONALITY, newPersonality, 0, 0)
				defer syscall.Syscall(sys.SYS_PERSONALITY, oldPersonality, 0, 0)
			}
		}

        // Start the program to be debugged, which now has address space randomization disabled
		process = exec.Command(cmd[0])
		process.Args = cmd
		process.Stdin = stdin
		process.Stdout = stdout
		process.Stderr = stderr
		process.SysProcAttr = &syscall.SysProcAttr{
            // Ptrace=true, in the Go standard library, PTRACEME will be called in the child process
			Ptrace:     true, 
			Setpgid:    true,
			Foreground: foreground,
		}
        ...
		err = process.Start()
	})

    // Wait for tracee to start
	dbp.pid = process.Process.Pid
	dbp.childProcess = true
	_, _, err = dbp.wait(process.Process.Pid, 0)

    // Further initialization, including bringing all existing threads and future threads under control
	tgt, err := dbp.initialize(cmd[0])
	if err != nil {
		return nil, err
	}
	return tgt, nil
}
```

see go/src/syscall/exec_linux.go

```go
func forkAndExecInChild1(...) {
    ...
	if sys.Ptrace {
		_, _, err1 = RawSyscall(SYS_PTRACE, uintptr(PTRACE_TRACEME), 0, 0)
		if err1 != 0 {
			goto childerror
		}
	}
    ...
```

This completes the target layer logic of the exec operation in the debugger backend. After the frontend-backend network I/O initialization is complete, the frontend can send debugging commands through the debugging session.

### Testing

Omitted

### Summary

This article introduced the implementation details of the tinydbg exec command. The exec command is used to start a new process and debug it, mainly implemented by setting the process's SysProcAttr.Ptrace=true. When the new process starts, the Go runtime automatically calls PTRACE_TRACEME to put the child process into a traced state. The debugger waits for the child process to start, then brings all its threads under control. This completes the target layer logic of the exec operation, preparing for subsequent debugging sessions.

We also reviewed the role of ASLR and its impact on debugging, and introduced the method of using `--disable-aslr`.
