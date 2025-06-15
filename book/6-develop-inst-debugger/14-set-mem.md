## Modifying Process State (Memory)

### Implementation Goal: Modifying Memory Data

During the process of adding and removing breakpoints, we are actually modifying memory data, but the breakpoint operation modifies instruction data. Here, we emphasize modifying data. Modifying memory data in an instruction-level debugger is not as easy as in a symbol-level debugger, which can modify directly through variable names. The requirements for the debugger are higher because if one does not know what data is at what location in memory, what type it is, and how many bytes it occupies, it is difficult to modify. Symbol-level debuggers are much simpler, as they can modify directly through variable names.

In this section, we will demonstrate how to modify data in the memory data area, introduce the general interaction, and use the system call `ptrace(PTRACE_POKEDATA,...)`. This will also serve as a technical preparation for modifying values through variable names in our future symbol-level debugger. Strictly speaking, we should provide a general debugging command to modify memory: `set <addr> <value>`. OK, let's first introduce how to modify memory data at any specified address, and then implement this functionality in `godbg`.

### Code Implementation

We will implement a program that tracks the debugged process, prompts for the address of a variable and its new value, and then modifies the memory data at that address to the new value.

How do we determine the address of this variable? We will implement a Go program, compile and start it, then use the symbol-level debugger `dlv` to track it, determine its variable address, detach, and then hand it over to our program to attach to the debugged process. This way, we can input the exact variable address and new value for testing.

OK, let's look at the implementation of the program here.

```go
package main

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"syscall"
	"time"
)

var usage = `Usage:
	go run main.go <pid>

	args:
	- pid: specify the pid of process to attach
`

func main() {
	runtime.LockOSThread()

	if len(os.Args) != 2 {
		fmt.Println(usage)
		os.Exit(1)
	}

	// pid
	pid, err := strconv.Atoi(os.Args[1])
	if err != nil {
		panic(err)
	}

	if !checkPid(int(pid)) {
		fmt.Fprintf(os.Stderr, "process %d not existed\n\n", pid)
		os.Exit(1)
	}

	// step1: supposing running dlv attach here
	fmt.Fprintf(os.Stdout, "===step1===: supposing running `dlv attach pid` here\n")

	// attach
	err = syscall.PtraceAttach(int(pid))
	if err != nil {
		fmt.Fprintf(os.Stderr, "process %d attach error: %v\n\n", pid, err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stdout, "process %d attach succ\n\n", pid)

	// check target process stopped or not
	var status syscall.WaitStatus
	var options int
	var rusage syscall.Rusage

	_, err = syscall.Wait4(int(pid), &status, options, &rusage)
	if err != nil {
		fmt.Fprintf(os.Stderr, "process %d wait error: %v\n\n", pid, err)
		os.Exit(1)
	}
	if !status.Stopped() {
		fmt.Fprintf(os.Stderr, "process %d not stopped\n\n", pid)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stdout, "process %d stopped\n\n", pid)

	regs := syscall.PtraceRegs{}
	if err := syscall.PtraceGetRegs(int(pid), &regs); err != nil {
		fmt.Fprintf(os.Stderr, "get regs fail: %v\n", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stdout, "tracee stopped at %0x\n", regs.PC())

	// step2: supposing running list and disass <locspec> go get the address of interested code
	time.Sleep(time.Second * 2)

	var input string
	fmt.Fprintf(os.Stdout, "enter a address you want to modify data\n")
	_, err = fmt.Fscanf(os.Stdin, "%s", &input)
	if err != nil {
		panic("read address fail")
	}
	addr, err := strconv.ParseUint(input, 0, 64)
	if err != nil {
		panic(err)
	}
	fmt.Fprintf(os.Stdout, "you entered %0x\n", addr)

	fmt.Fprintf(os.Stdout, "enter a value you want to change to\n")
	_, err = fmt.Fscanf(os.Stdin, "%s", &input)
	if err != nil {
		panic("read value fail")
	}
	val, err := strconv.ParseUint(input, 0, 64)
	if err != nil {
		panic("read value fail")
	}
	fmt.Fprintf(os.Stdout, "you entered %x\n", val)
	fmt.Fprintf(os.Stdout, "we'll set *(%x) = %x\n", addr, val)

	// step2: supposing runnig step here
	time.Sleep(time.Second * 2)
	fmt.Fprintf(os.Stdout, "===step2===: supposing running `dlv> set *addr = 0xaf` here\n")

	var data [1]byte
	n, err := syscall.PtracePeekText(int(pid), uintptr(addr), data[:])
	if err != nil || n != 1 {
		fmt.Fprintf(os.Stderr, "read data fail: %v\n", err)
		os.Exit(1)
	}

	n, err = syscall.PtracePokeText(int(pid), uintptr(addr), []byte{byte(val)})
	if err != nil || n != 1 {
		fmt.Fprintf(os.Stderr, "write data fail: %v\n", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stdout, "change data from %x to %d succ\n", data[0], val)
}

// checkPid check whether pid is valid process's id
//
// On Unix systems, os.FindProcess always succeeds and returns a Process for
// the given pid, regardless of whether the process exists.
func checkPid(pid int) bool {
	out, err := exec.Command("kill", "-s", "0", strconv.Itoa(pid)).CombinedOutput()
	if err != nil {
		panic(err)
	}

	// output error message, means pid is invalid
	if string(out) != "" {
		return false
	}

	return true
}
```

### Code Testing

Below is the testing method. For convenience, we need to prepare a test program to easily obtain the address of a variable, then modify its value, and verify the modification through the program's execution effect.

1. First, we prepared a test program `testdata/loop.go`.

   This program prints the current process's pid every 1 second through a for loop, with the loop control variable `loop` defaulting to true.

```go
   package main
   
   import (
   	"fmt"
   	"os"
   	"time"
   )
   
   func main() {
   	loop := true
   	for loop {
   		fmt.Println("pid:", os.Getpid())
   		time.Sleep(time.Second)
   	}
   }
```

2. We first build and run this program, noting that to prevent the variable from being optimized away, we need to disable optimization during the build: `go build -gcflags 'all=-N -l'`

```bash
   $ cd../testdata && make
   $./loop
   pid:49701
   pid:49701
   pid:49701
   pid:49701
   pid:49701
   ...
```

3. Then we use `dlv` to observe the memory location of the variable `loop`.

```bash
   $dlvattach49701

   (dlv) b loop.go:11
    Breakpoint 1 set at 0x4af0f9 for main.main() ./debugger101/golang-debugger-lessons/testdata/loop.go:11
    (dlv) c
    > [Breakpoint 1] main.main() ./debugger101/golang-debugger-lessons/testdata/loop.go:11 (hitsgoroutine(1):1total:1) (PC:0x4af0f9)
         6:         "time"
         7: )
         8:
         9:funcmain() {
        10:         loop:=true
    =>  11:         forloop{
        12:                 fmt.Println("pid:",os.Getpid())
        13:                 time.Sleep(time.Second)
        14:         }
        15:}
    (dlv) p &loop
    (*bool)(0xc0000caf17)
    (dlv) x 0xc0000caf17
    0xc0000caf17:   0x01
    ...
    ```

3. Then we let the `dlv` process exit to resume the execution of `loop`.

   ```bash
   (dlv) quit
   Would you like to kill the process? [Y/n] n
```

4. Then we execute our program.

```bash
   $ ./14_set_mem 49701
    ===step1===: supposing running `dlv attach pid` here
    process 49701 attach succ
    process 49701 stopped
    tracee stopped at 476203

    enter a address you want to modify data         <= input address of variable `loop`
    0xc0000caf17
    you entered c0000caf17

    enter a value you want to change to             <= input false of variable `loop`
    0x00
    you entered 0

    we'll set *(c0000caf17) = 0                     <= do loop=false

    ===step2===: supposing running `dlv> set *addr = 0xaf` here     <= do loop=false succ
    change data from 1 to 0 succ
```

   At this point, because `loop=false`, the `for loop {...}` loop ends, and the program will execute to completion.

```bash
    pid:49701
    pid:49701
    pid:49701                       <= tracee exit successfully for `loop=false`
    zhangjie🦀testdata(master) $
```

### Summary

In this section, we implemented the functionality to modify data at any memory address in an instruction-level debugger. This is a very important feature, as we know how crucial it is to modify memory data when debugging and changing program execution behavior. After understanding the implementation techniques here, we will continue to implement variable value modification when implementing symbol-level debugging. For developers working with high-level languages, the ability to adjust variable values is a very important feature for observing program execution behavior.

In the next section, we will look at how to modify register values, which is also important in certain debugging scenarios.
