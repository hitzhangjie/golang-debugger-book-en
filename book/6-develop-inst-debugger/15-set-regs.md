## Modifying Process State (Registers)

### Implementation Goal: Modifying Register Data

Before continuing execution after hitting a breakpoint, we need to restore the instruction data at PC-1 and modify the register PC=PC-1. We have already demonstrated how to read and modify register data, but its modification action is built into the `continue` debugging command. Here, we need a general debugging command `set <register> <value>`. OK, we indeed need such a debugging command, especially for instruction-level debuggers, where the operands of instructions are either immediate values, memory addresses, or registers. We will implement this debugging command to modify any register in `godbg`. However, this section will focus on explaining the necessity of mastering this operation and how to implement it through specific examples.

### Code Implementation

We will first implement a test program that prints the process pid every 1 second. The loop condition of the for-loop is a function `loop()` that always returns true. We want to modify the return value of the function call `loop()` by changing the register value.

```go
package main

import (
	"fmt"
	"os"
	"runtime"
	"time"
)

func main() {
	runtime.LockOSThread()

	for loop() {
		fmt.Println("pid:", os.Getpid())
		time.Sleep(time.Second)
	}
}

//go:noinline
func loop() bool {
	return true
}

```

Below is the debugging program we wrote. It first attaches to the debugged process, then prompts us to obtain and input the return address of the `loop()` function call. It then adds a breakpoint, runs to that breakpoint location, adjusts the value of the RAX register (the return value of `loop()` is stored in RAX), and then resumes execution. We will see the program exit the loop.

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

	// step2: supposing running `dlv> b <addr>`  and `dlv> continue` here
	time.Sleep(time.Second * 2)
	fmt.Fprintf(os.Stdout, "===step2===: supposing running `dlv> b <addr>`  and `dlv> continue` here\n")

	// read the address
	var input string
	fmt.Fprintf(os.Stdout, "enter return address of loop()\n")
	_, err = fmt.Fscanf(os.Stdin, "%s", &input)
	if err != nil {
		fmt.Fprintf(os.Stderr, "read address fail\n")
		os.Exit(1)
	}
	addr, err := strconv.ParseUint(input, 0, 64)
	if err != nil {
		panic(err)
	}
	fmt.Fprintf(os.Stdout, "you entered %0x\n", addr)

	// add breakpoint and run there
	var orig [1]byte
	if n, err := syscall.PtracePeekText(int(pid), uintptr(addr), orig[:]); err != nil || n != 1 {
		fmt.Fprintf(os.Stderr, "peek text fail, n: %d, err: %v\n", n, err)
		os.Exit(1)
	}
	if n, err := syscall.PtracePokeText(int(pid), uintptr(addr), []byte{0xCC}); err != nil || n != 1 {
		fmt.Fprintf(os.Stderr, "poke text fail, n: %d, err: %v\n", n, err)
		os.Exit(1)
	}
	if err := syscall.PtraceCont(int(pid), 0); err != nil {
		fmt.Fprintf(os.Stderr, "ptrace cont fail, err: %v\n", err)
		os.Exit(1)
	}

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

	// step3: supposing change register RAX value from true to false
	time.Sleep(time.Second * 2)
	fmt.Fprintf(os.Stdout, "===step3===: supposing change register RAX value from true to false\n")
	if err := syscall.PtraceGetRegs(int(pid), &regs); err != nil {
		fmt.Fprintf(os.Stderr, "ptrace get regs fail, err: %v\n", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stdout, "before RAX=%x\n", regs.Rax)

	regs.Rax &= 0xffffffff00000000
	if err := syscall.PtraceSetRegs(int(pid), &regs); err != nil {
		fmt.Fprintf(os.Stderr, "ptrace set regs fail, err: %v\n", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stdout, "after RAX=%x\n", regs.Rax)

	// step4: let tracee continue and check it behavior (loop3.go should exit the for-loop)
	if n, err := syscall.PtracePokeText(int(pid), uintptr(addr), orig[:]); err != nil || n != 1 {
		fmt.Fprintf(os.Stderr, "restore instruction data fail: %v\n", err)
		os.Exit(1)
	}
	if err := syscall.PtraceCont(int(pid), 0); err != nil {
		fmt.Fprintf(os.Stderr, "ptrace cont fail, err: %v\n", err)
		os.Exit(1)
	}
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

Testing method:

1. First, we prepare a test program, `loop3.go`, which outputs the pid every 1 second, with the loop controlled by the `loop()` function that always returns true. See `testdata/loop3.go` for details.

2. According to the ABI calling convention, the return value of the function call `loop()` will be returned through the RAX register. Therefore, we want to modify the return value to false by changing the value of the RAX register after the `loop()` function call returns.

   We first determine the return address of the `loop()` function. This can be done by adding a breakpoint at `loop3.go:13` using the `dlv` debugger, then disassembling, and we can determine the return address as `0x4af15e`.

   After determining the return address, we can detach the tracee and resume its execution.

```bash
(dlv) disass
Sending output to pager...
TEXT main.main(SB) /home/zhangjie/debugger101/golang-debugger-lessons/testdata/loop3.go
        loop3.go:10     0x4af140        493b6610                cmp rsp, qword ptr [r14+0x10]
        loop3.go:10     0x4af144        0f8601010000            jbe 0x4af24b
        loop3.go:10     0x4af14a        55                      push rbp
        loop3.go:10     0x4af14b        4889e5                  mov rbp, rsp
        loop3.go:10     0x4af14e        4883ec70                sub rsp, 0x70
        loop3.go:11     0x4af152        e8e95ef9ff              call $runtime.LockOSThread
        loop3.go:13     0x4af157        eb00                    jmp 0x4af159
=>      loop3.go:13     0x4af159*       e802010000              call $main.loop
        loop3.go:13     0x4af15e        8844241f                mov byte ptr [rsp+0x1f], al
        ...
(dlv) quit
Would you like to kill the process? [Y/n] n
```

3. If we do not interfere, `loop3` will continuously output the pid information every 1 second.

```bash
$ ./loop3
pid: 4946
pid: 4946
pid: 4946
pid: 4946
pid: 4946
...
zhangjie🦀 testdata(master) $
```

4. Now run our debugging tool `./15_set_regs 4946`.

```bash
$ ./15_set_regs 4946
===step1===: supposing running `dlv attach pid` here
process 4946 attach succ
process 4946 stopped
tracee stopped at 476263

===step2===: supposing running `dlv> b <addr>`  and `dlv> continue` here
enter return address of loop()
0x4af15e

you entered 4af15e
process 4946 stopped

===step3===: supposing change register RAX value from true to false
before RAX=1
after RAX=0                   <= we changed retvalue to zero
```

```bash
...
pid: 4946
pid: 4946
pid: 4946                      <= we changed retvalue, so loop stop
zhangjie🦀 testdata(master) $
```

```bash
(dlv) disass
TEXT main.loop(SB) /home/zhangjie/debugger101/golang-debugger-lessons/testdata/loop3.go
        loop3.go:20     0x4af260        55              push rbp
        loop3.go:20     0x4af261        4889e5          mov rbp, rsp
=>      loop3.go:20     0x4af264*       4883ec08        sub rsp, 0x8
        loop3.go:20     0x4af268        c644240700      mov byte ptr [rsp+0x7], 0x0
        loop3.go:21     0x4af26d        c644240701      mov byte ptr [rsp+0x7], 0x1
        loop3.go:21     0x4af272        b801000000      mov eax, 0x1 <== retvalue save in eax
        loop3.go:21     0x4af277        4883c408        add rsp, 0x8
        loop3.go:21     0x4af27b        5d              pop rbp
        loop3.go:21     0x4af27c        c3              ret
```

Through this example, we have demonstrated how to set register values. We will implement the godbg> `set reg value` command in [hitzhangjie/godbg](https://github.com/hitzhangjie/godbg) to modify register values.

### Summary

In this section, we introduced how to modify register values and demonstrated a case of tampering with function return values by modifying registers. Of course, if you have a thorough understanding of stack frame composition, combined with reading and writing registers and memory operations, you can also modify function call parameters and return addresses.

