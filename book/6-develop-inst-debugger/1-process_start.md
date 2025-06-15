## Starting a Process

### Implementation Goal: `godbg exec <prog>`

When a debugger performs debugging, it first needs to determine the target to debug. This could be a process instance or a core file. For convenience, the debugger can also handle compilation operations, such as dlv debug which can target a Go main module.

Let's first focus on how to debug a process. A core file is just a kernel dump of a process, and the debugger can only view the stack frame situation at that time. The aspects involved in debugging a process basically cover the content of debugging a core file, so we'll focus on process debugging first.

There are mainly the following scenarios for debugging a process:

- If the process doesn't exist yet, we need to start the specified process, such as when dlv exec, gdb, etc. specify a program name to start debugging;
- If the process already exists, we need to track the process through its pid, such as dlv attach, gdb, etc. using -p to specify the pid for debugging a running process;

For development and debugging convenience, the debugger may also include compilation and build tasks, such as ensuring the build product contains debug information and avoiding the negative impact of excessive optimization on debugging. Usually, these operations require passing special options to the compiler and linker, which isn't very user-friendly for developers. Considering this, the Go debugger dlv automatically passes the `-gcflags="all=-N -l"` option when executing the `dlv debug` command to disable inlining and optimization during the compilation and build process, ensuring the build product meets the debugger's needs.

Let's first introduce the first scenario: specifying a program path to start the program and create a process.

We will implement the program godbg, which supports the exec subcommand and accepts the parameter prog. godbg will start the program prog and obtain its execution results.

> prog represents an executable program, which could be a path to an executable program or the name of an executable program that can be found in the PATH.

### Basic Knowledge

The Go standard library provides the os/exec package, which allows starting a process by specifying a program name. Let's first introduce how to start a program and create a process using the Go standard library.

Through the `cmd = exec.Command(...)` method, we can create a Cmd instance:

- After that, we can start the program using the `cmd.Start()` method. If we want to get the results, we can use `cmd.Wait()` to wait for the process to end and then get the results;
- If we want to start the program and wait for it to finish, we can also use `cmd.Run()`. The stdout and stderr information of the command output can be collected by modifying cmd.Stdout and cmd.Stderr to a bytes.Buffer;
- If we want to start the program, wait for it to finish, and get the stdout and stderr output information, we can also use `buf, err := Cmd.CombineOutput()`.

```go
package exec // import "os/exec"

// Command This method receives an executable program name or path, arg is the parameter information passed to the executable program.
// This function returns a Cmd object, through which we can start the program, get program execution results, etc. Note that the parameter name
// can be a path to an executable program or the name of an executable program that can be found in PATH
func Command(name string, arg ...string) *Cmd

// Cmd Through Cmd, we can execute programs, get program execution results, etc. Once Cmd calls methods like Start, Run, etc.,
// it cannot be reused
type Cmd struct {
    ...
}

// CombinedOutput Returns the information output to stdout and stderr during program execution
func (c *Cmd) CombinedOutput() ([]byte, error)

// Output Returns the information output to stdout during program execution. The error in the return value list indicates an error encountered during execution
func (c *Cmd) Output() ([]byte, error)

// Run Starts the program and waits for it to finish. The error in the return value list indicates an error encountered during execution
func (c *Cmd) Run() error

// Start Starts the program but doesn't wait for it to finish. The error in the return value list indicates an error encountered during execution
func (c *Cmd) Start() error

...

// Wait Waits for cmd to finish executing. This method must be used in conjunction with the Start() method. The error return value indicates an error encountered during execution
//
// Wait waits for the program to finish executing and obtains the program's exit code (that is, the return value, os.Exit(?) returns the value to the operating system and is then obtained by the parent process),
// and releases corresponding resources (such as id resources, think of PCB)
func (c *Cmd) Wait() error
```

### Code Implementation

**Source code see: golang-debugger-lessons/1_process_start**

Below is a demonstration of how to start a program and create a process instance using the Go standard library `os/exec` package.

file: main.go

```go
package main

import (
	"fmt"
	"os"
	"os/exec"
)

const (
	usage = "Usage: go run main.go exec <path/to/prog>"

	cmdExec = "exec"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "%s\n\n", usage)
		os.Exit(1)
	}
	cmd := os.Args[1]

	switch cmd {
	case cmdExec:
		prog := os.Args[2]
		progCmd := exec.Command(prog)
		buf, err := progCmd.CombinedOutput()
		if err != nil {
			fmt.Fprintf(os.Stderr, "%s exec error: %v, \n\n%s\n\n", err, string(buf))
			os.Exit(1)
		}
		fmt.Fprintf(os.Stdout, "%s\n", string(buf))
	default:
		fmt.Fprintf(os.Stderr, "%s unknown cmd\n\n", cmd)
		os.Exit(1)
	}

}
```

The program logic here is relatively simple:

- When the program runs, it first checks the command line arguments,
  - `godbg exec <prog>`, there should be at least 3 arguments. If the number of arguments is incorrect, it reports an error and exits;
  - Next, it checks the second argument. If it's not exec, it also reports an error and exits;
- With normal arguments, the third argument should be a program path or executable program filename. We create an exec.Command object, then start it and get the running results;

### Code Testing

You can compile and build it yourself to complete the relevant tests.

```bash
1_start-process $ GO111MODULE=off go build -o godbg main.go

./godbg exec <prog>
```

> ps: Of course, you can also consider copying godbg to the PATH or using go install before testing.

The current program logic can be completed in a single file, so `go run main.go` can be used for quick testing. For example, execute `GO111MODULE=off go run main.go exec ls` in the directory golang-debugger-lessons/1_start-process for testing.

```bash
1_start-process $ GO111MODULE=off go run main.go exec ls
tracee pid: 270
main.go
README.md
```

godbg successfully executed the ls command and displayed the files in the current directory. Later, we will use normal Go programs as the debugged process. For this section, it's sufficient to understand how to start a process.

> ps: Regarding the testing environment, it's strongly recommended that readers use the same environment as the author during development to facilitate smooth testing. To simplify this process, the godbg project provides container development configuration `devcontainer.json`. Please use VSCode or GoLand 2023.2's container development mode to open the project and perform testing.
>
> ps: 2025.2.18, the isolation of containers is relatively weak. I'm now considering providing a matching virtual machine to facilitate testing, but virtual machine files (vmdk) are often very large, making it difficult for everyone to download this environment. However, for some beginners, they might be more familiar with using virtual machines than container technology.
