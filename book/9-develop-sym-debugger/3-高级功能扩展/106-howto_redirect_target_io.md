## Process I/O Redirection

### Why Do We Need Input/Output Redirection Support?

When debugging programs, controlling the input and output streams is essential for several reasons:

1. **Interactive Programs**: Many programs require user interaction input. Without proper redirection support, debugging such programs would become difficult or impossible.
2. **Testing and Automation**: Redirecting input and output allows for automated testing scenarios, enabling programmatic input provision and output capture for verification.
3. **Debug Environment Control**: Sometimes we need to separate the debugger's input/output from the target program's input/output to avoid confusion and maintain a clear debugging session.

### Redirection Methods in tinydbg

tinydbg provides two main methods to control the target program's input and output:

#### 1. TTY Redirection (`--tty`)

The `--tty` option allows you to specify a TTY device for the target program's input and output. This is particularly useful for interactive programs that require proper terminal interface.

Usage:

```bash
tinydbg debug --tty /dev/pts/X main.go
```

#### 2. File Redirection (`-r`)

The `-r` option allows you to redirect the target program's input and output to files. This is useful for non-interactive programs or situations where output needs to be captured for later analysis.

Usage:

```bash
tinydbg debug -r stdin=in.txt,stdout=out.txt,stderr=err.txt main.go
```

#### Implementation Details

When starting a debugging session, tinydbg handles the redirection of standard input/output streams (stdin, stdout, stderr) through the following process:

1. For TTY Redirection:
   - Open the specified TTY device
   - Redirect the target program's file descriptors to this TTY
   - This allows proper terminal interaction with the target program

```go
// TTY Redirection Implementation
func setupTTY(cmd *exec.Cmd, ttyPath string) error {
	tty, err := os.OpenFile(ttyPath, os.O_RDWR, 0)
	if err != nil {
		return fmt.Errorf("open tty: %v", err)
	}

	// Set standard input/output
	cmd.Stdin = tty
	cmd.Stdout = tty
	cmd.Stderr = tty

	// Set process attributes
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setctty: true,
		Setsid:  true,
	}

	return nil
}
```

2. For File Redirection:
   - Open the specified files
   - Redirect the target program's file descriptors to these files
   - This implements input/output capture and replay functionality

When implementing redirection in Go programs, we mainly achieve this by setting the `SysProcAttr` of `os/exec.Cmd` and standard input/output:

```go
// File Redirection Implementation
func setupFileRedirection(cmd *exec.Cmd, stdin, stdout, stderr string) error {
	// Set standard input
	if stdin != "" {
		stdinFile, err := os.OpenFile(stdin, os.O_RDONLY, 0)
		if err != nil {
			return fmt.Errorf("open stdin file: %v", err)
		}
		cmd.Stdin = stdinFile
	}

	// Set standard output
	if stdout != "" {
		stdoutFile, err := os.OpenFile(stdout, os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0644)
		if err != nil {
			return fmt.Errorf("open stdout file: %v", err)
		}
		cmd.Stdout = stdoutFile
	}

	// Set standard error
	if stderr != "" {
		stderrFile, err := os.OpenFile(stderr, os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0644)
		if err != nil {
			return fmt.Errorf("open stderr file: %v", err)
		}
		cmd.Stderr = stderrFile
	}

	return nil
}
```

### Test Example

Let's assume we have the following program that involves input and output:

```go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

func main() {
	fmt.Println("TTY Demo Program")
	fmt.Println("Type something and press Enter (type 'quit' to exit):")

	scanner := bufio.NewScanner(os.Stdin)
	for {
		fmt.Print("> ")
		if !scanner.Scan() {
			break
		}

		input := scanner.Text()
		if strings.ToLower(input) == "quit" {
			fmt.Println("Goodbye!")
			break
		}

		fmt.Printf("You typed: %s\n", input)
	}

	if err := scanner.Err(); err != nil {
		fmt.Fprintf(os.Stderr, "Error reading input: %v\n", err)
		os.Exit(1)
	}
}
```

Let's look at the debugging process using `-tty` and `-r` redirection.

#### TTY Redirection Example

Let's look at a practical example using the `tty_demo` program:

1. First, create a new PTY pair using socat:

```bash
socat -d -d pty,raw,echo=0 pty,raw,echo=0
```

2. Note the two PTY paths in the output (e.g., `/dev/pts/23` and `/dev/pts/24`)
3. In one terminal, run the program using the first PTY:

```bash
tinydbg debug --tty /dev/pts/23 main.go
```

4. In another terminal, you can interact with the program using:

```bash
socat - /dev/pts/24
```

The program will:

- Print a welcome message
- Wait for your input
- Echo your input
- Continue running until you type 'quit'

Example session:

```
TTY Demo Program
Type something and press Enter (type 'quit' to exit):
> hello
You typed: hello
> world
You typed: world
> quit
Goodbye!
```

#### File Redirection Example

To test file redirection, you can:

1. Create files for redirection: input.txt, output.txt
2. Run the program with redirection:

```bash
tinydbg debug -r stdin=input.txt,stdout=output.txt,stderr=output.txt main.go
```

3. Write the desired input data to the file before or during debugging, e.g.: `echo "data..." >> input.txt`
4. Observe program output through `tail -f output.txt`
5. Execute the debugging process.

Let's look at a complete file redirection test example:

```bash
## 1. Create input file
cat > input.txt << EOF
hello
world
quit
EOF

## 2. Create empty output file
touch output.txt

## 3. Start program with redirection
tinydbg debug -r stdin=input.txt,stdout=output.txt,stderr=output.txt main.go

## 4. Observe output in another terminal
tail -f output.txt
```

Expected output file content:

```
TTY Demo Program
Type something and press Enter (type 'quit' to exit):
> hello
You typed: hello
> world
You typed: world
> quit
Goodbye!
```

#### Comparison of Both Methods

Compared to the `socat - /dev/pts/X` method, the file redirection approach might be more preferred by users as it doesn't require familiarity with operations involving tty creation, reading, and writing using tools like socat, tmux, or screen. However, `socat - /dev/pts/X` offers more convenient simultaneous read/write operations. Nevertheless, file redirection might be a more stable and effective approach in the automation testing process of the debugger.

### Summary

tinydbg's redirection support provides flexible ways to control the target program's input and output streams, making it easier to debug both interactive and non-interactive programs. The `--tty` option is particularly suitable for programs requiring terminal interaction, while the `-r` option provides a way to capture and replay input/output through files.

These features make tinydbg more versatile, suitable for a wider range of debugging scenarios, from simple command-line tools to complex interactive applications.
