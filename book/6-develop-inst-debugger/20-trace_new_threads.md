## Extended Reading: How to Track Newly Created Threads

### Implementation Goal

In previous demonstrations of debugger operations, we used single-threaded programs to simplify the challenges of multi-threaded debugging. However, in real-world scenarios, our programs are often multi-threaded.

Our debugger must have the capability to debug multi-threaded programs. Here are some scenarios that need special emphasis:

- Parent-child processes: In the implementation of the debugger, tracking parent-child processes and tracking threads within a process are technically similar.
  Since this book is focused on Go debugging, we will only focus on multi-threaded debugging. Multi-process debugging will be mentioned but not covered in a dedicated section.
- Thread creation timing: Threads may be created before we attach or after we attach, through the `clone` system call.
  - For threads already created by the process, we need the ability to enumerate and initiate tracking, and switch between different threads for tracking.
  - For threads created during the debugging process, we need the ability to immediately sense thread creation and prompt the user to choose which thread to track, facilitating observation of events of interest.

In this section, we will first look at how to track newly created threads and obtain the new thread's TID to initiate tracking. In the next section, we will explore how to enumerate already created threads and selectively track specified threads.

### Basic Knowledge

Creating a new thread (or a new goroutine) is done through the `clone` system call. Here's how it works:

```go
// Clone parameters for creating a thread
const (
	cloneFlags = _CLONE_VM | /* share memory */
		_CLONE_FS | /* share cwd, etc */
		_CLONE_FILES | /* share fd table */
		_CLONE_SIGHAND | /* share sig handler table */
		_CLONE_SYSVSEM | /* share SysV semaphore undo lists (see issue #20763) */
		_CLONE_THREAD /* revisit - okay for now */
)

// Create a new thread
func newosproc(mp *m) {
	stk := unsafe.Pointer(mp.g0.stack.hi)
	/*
	 * note: strace gets confused if we use CLONE_PTRACE here.
	 */
	if false {
		print("newosproc stk=", stk, " m=", mp, " g=", mp.g0, " clone=", abi.FuncPCABI0(clone), " id=", mp.id, " ostk=", &mp, "\n")
	}

	// Disable signals during clone, so that the new thread starts
	// with signals disabled. It will enable them in minit.
	var oset sigset
	sigprocmask(_SIG_SETMASK, &sigset_all, &oset)
	ret := clone(cloneFlags, stk, unsafe.Pointer(mp), unsafe.Pointer(mp.g0), unsafe.Pointer(abi.FuncPCABI0(mstart)))
	sigprocmask(_SIG_SETMASK, &oset, nil)

	if ret < 0 {
		print("runtime: failed to create new OS thread (have ", mcount(), " already; errno=", -ret, ")\n")
		if ret == -_EAGAIN {
			println("runtime: may need to increase max user processes (ulimit -u)")
		}
		throw("newosproc")
	}
}

//go:noescape
func clone(flags int32, stk, mp, gp, fn unsafe.Pointer) int32
```

The implementation of the `clone` function in the amd64 architecture is as follows, see `go/src/runtime/sys_linux_amd64.s`:

```go
// int32 clone(int32 flags, void *stk, M *mp, G *gp, void (*fn)(void));
TEXT runtime·clone(SB),NOSPLIT,$0
	MOVL	flags+0(FP), DI 	// Prepare system call parameters
	MOVQ	stk+8(FP), SI
	...

	// Copy mp, gp, fn off parent stack for use by child.
	// Careful: Linux system call clobbers CX and R11.
	MOVQ	mp+16(FP), R13
	MOVQ	gp+24(FP), R9
	MOVQ	fn+32(FP), R12
	...

	MOVL	$SYS_clone, AX 		// Clone system call number
	syscall				// Execute system call

	// In parent, return.
	CMPQ	AX, $0
	JEQ	3(PC)
	MOVL	AX, ret+40(FP)		// Parent process, return the TID of the new thread
	RET

	// In child, on new stack.
	MOVQ	SI, SP

	// If g or m are nil, skip Go-related setup.
	CMPQ	R13, $0    // m
	JEQ	nog2
	CMPQ	R9, $0    // g
	JEQ	nog2

	// Initialize m->procid to Linux tid
	MOVL	$SYS_gettid, AX
	SYSCALL
	MOVQ	AX, m_procid(R13)

	// In child, set up new stack
	get_tls(CX)
	MOVQ	R13, g_m(R9)
	MOVQ	R9, g(CX)
	MOVQ	R9, R14 // set g register
	CALL	runtime·stackcheck(SB)

nog2:
	// Call fn. This is the PC of an ABI0 function.
	CALL	R12			// New thread, initialize related GMP scheduling, start executing the thread function mstart,
					// clone parameter includes abi.FuncPCABI0(mstart)
	...
```

From this, we can see that as long as the tracee executes the `clone` system call, the kernel can notify us, for example, through `ptrace(PTRACE_SYSCALL, pid, ...)`. This way, when the tracee executes the `clone` system call, it will stop at the enter and exit points of the system call, allowing us to perform debugging tasks. We can read the value of the RAX register to determine if the current system call number is `__NR_clone`. If it is, it indicates that the `clone` system call was executed, and we can use this to determine that a new thread was created. Similarly, at the exit of the system call, we can use a similar method to obtain the TID information of the new thread.

This method allows us to sense that the tracee has created a new thread. However, this method `ptrace(PTRACE_SYSCALL, pid, ...)` is too general, and you need to understand the ABI calling conventions (such as register allocation for system call numbers and return values), making it less convenient to use.

There is another method: when executing `ptrace(PTRACE_ATTACH, pid, ...)`, pass the option `PTRACE_O_TRACECLONE`. This operation is specifically set for tracking the `clone` system call, and afterward, you can:

1. **Tracer**: Run `ptrace(PTRACE_ATTACH, pid, NULL, PTRACE_O_TRACECLONE)`
   This operation will cause the kernel to send a SIGTRAP signal to the tracer when the tracee executes the `clone` system call, notifying that a new thread or process has been created.

2. **Tracer**: Actively sense the occurrence of this event through two methods:
   - Through a signal handler to sense the occurrence of this signal;
   - Through `waitpid()` to sense that the tracee's running state has changed, and determine if it is a PTRACE_EVENT_CLONE event through the status returned by `waitpid`.
     See: `man 2 ptrace` for details on the option `PTRACE_O_TRACECLONE`.

3. **Tracer**: If it is confirmed that it is due to `clone`, you can further obtain the new thread's PID information through `newpid = ptrace(PTRACE_GETEVENTMSG, pid, ...)`.

4. After obtaining the thread PID, you can proceed to do other things, such as automatically tracking the new thread by default, or choosing to release the new thread or observe and control it.

> Note: Occasionally, the terms PID and TID may be mixed. For threads, it is essentially a lightweight process (LWP) created by `clone`. However, when describing a thread's ID, the term TID should be used, not PID. Due to certain function call parameters, I may occasionally write them the same, such as when attaching a thread, the parameter should be TID, not the thread's PID, as their values are different.
>
> - The PID of the process to which this thread belongs can be obtained with `getpid()`.
> - The TID of this thread (or described as the corresponding LWP's PID) can be obtained with `syscall(SYS_gettid)`.

The second method is easier to understand and maintain, and we will adopt it in our design and implementation. However, the first method also has potential, such as tracking arbitrary system calls during debugging, which we can implement using a similar approach. In the extended reading section, we will also introduce this further in a dedicated section.

### Design Implementation

The implementation code for this part can be found in [hitzhangjie/golang-debugger-lessons](https://github.com/hitzhangjie/golang-debugger-lessons) / 20_trace_new_threads.

First, for convenience in later testing, we will implement a multi-threaded program in C. The program logic is simple: it creates a new thread every few seconds, and the thread function prints the current thread's PID and the LWP's PID.

```c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <pthread.h>

pid_t gettid(void);

void *threadfunc(void *arg) {
    printf("process: %d, thread: %u\n", getpid(), syscall(SYS_gettid));
    sleep(1);
}

int main() {
    printf("process: %d, thread: %u\n", getpid(), syscall(SYS_gettid));

    pthread_t tid;
    for (int i = 0; i < 100; i++)
    {
        if (i % 10 == 0) {
            int ret = pthread_create(&tid, NULL, threadfunc, NULL);
            if (ret != 0) {
                printf("pthread_create error: %d\n", ret);
                exit(-1);
            }
        }
        sleep(1);
    }
    sleep(15);
}
```

This program can be compiled with `gcc -o fork fork.c -lpthread`, and then run `./fork` for testing to see the running effect without debugging and tracking.

Next, let's look at the debugger's code logic. This is mainly to demonstrate how the tracer (debugger) can sense newly created threads in a multi-threaded program and automatically track them, and if necessary, implement a debugging effect similar to gdb's `set follow-fork-mode=child/parent/ask`.

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
	var rusage syscall.Rusage
	_, err = syscall.Wait4(int(pid), &status, 0, &rusage)
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

	// step2: setup to trace all new threads creation events
	time.Sleep(time.Second * 2)

	opts := syscall.PTRACE_O_TRACEFORK | syscall.PTRACE_O_TRACEVFORK | syscall.PTRACE_O_TRACECLONE
	if err := syscall.PtraceSetOptions(int(pid), opts); err != nil {
		fmt.Fprintf(os.Stderr, "set options fail: %v\n", err)
		os.Exit(1)
	}

	for {
		// Release the main thread, as it will stop every time it hits clone
		if err := syscall.PtraceCont(int(pid), 0); err != nil {
			fmt.Fprintf(os.Stderr, "cont fail: %v\n", err)
			os.Exit(1)
		}

		// Check the main thread's status, and if the status is a clone event, continue to obtain the LWP PID of the cloned thread
		var status syscall.WaitStatus
		rusage := syscall.Rusage{}
		_, err := syscall.Wait4(pid, &status, syscall.WSTOPPED|syscall.WCLONE, &rusage)
		if err != nil {
			fmt.Fprintf(os.Stderr, "wait4 fail: %v\n", err)
			break
		}
		// Check if the status information is a clone event (see `man 2 ptrace` for details on the option PTRACE_O_TRACECLONE)
		isclone := status>>8 == (syscall.WaitStatus(syscall.SIGTRAP) | syscall.WaitStatus(syscall.PTRACE_EVENT_CLONE<<8))
		fmt.Fprintf(os.Stdout, "tracee stopped, tracee pid:%d, status: %s, trapcause is clone: %v\n",
			pid,
			status.StopSignal().String(),
			isclone)

		// Obtain the LWP PID of the child thread
		msg, err := syscall.PtraceGetEventMsg(int(pid))
		if err != nil {
			fmt.Fprintf(os.Stderr, "get event msg fail: %v\n", err)
			break
		}
		fmt.Fprintf(os.Stdout, "eventmsg: new thread lwp pid: %d\n", msg)

		// Release the child thread to continue execution
		_ = syscall.PtraceDetach(int(msg))

		time.Sleep(time.Second * 2)
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

1. First, let's look at `testdata/fork.c`. This program creates a pthread thread every few seconds.

The main thread and other threads will print the PID and TID (where TID is the corresponding LWP's PID) of the thread.

```
zhangjie🦀 testdata(master) $ ./fork 
process: 35573, thread: 35573
process: 35573, thread: 35574
process: 35573, thread: 35716
process: 35573, thread: 35853
process: 35573, thread: 35944
process: 35573, thread: 36086
process: 35573, thread: 36192
process: 35573, thread: 36295
process: 35573, thread: 36398
...
```

2. We will simultaneously observe the execution of `./20_trace_new_threads <fork program process pid>`.

```
zhangjie🦀 20_trace_new_threads(master) $ ./20_trace_new_threads 35573
===step1===: supposing running `dlv attach pid` here
process 35573 attach succ

process 35573 stopped

tracee stopped at 7f318346f098
tracee stopped, tracee pid:35573, status: trace/breakpoint trap, trapcause is clone: true
eventmsg: new thread lwp pid: 35716
tracee stopped, tracee pid:35573, status: trace/breakpoint trap, trapcause is clone: true
eventmsg: new thread lwp pid: 35853
tracee stopped, tracee pid:35573, status: trace/breakpoint trap, trapcause is clone: true
eventmsg: new thread lwp pid: 35944
tracee stopped, tracee pid:35573, status: trace/breakpoint trap, trapcause is clone: true
eventmsg: new thread lwp pid: 35944
tracee stopped, tracee pid:35573, status: trace/breakpoint trap, trapcause is clone: true
eventmsg: new thread lwp pid: 35944
tracee stopped, tracee pid:35573, status: trace/breakpoint trap1, trapcause is clone: true
eventmsg: new thread lwp pid: 36086
tracee stopped, tracee pid:35573, status: trace/breakpoint trap, trapcause is clone: true
eventmsg: new thread lwp pid: 36192
tracee stopped, tracee pid:35573, status: trace/breakpoint trap, trapcause is clone: true
eventmsg: new thread lwp pid: 36295
tracee stopped, tracee pid:35573, status: trace/breakpoint trap, trapcause is clone: true
eventmsg: new thread lwp pid: 36398
..
```

3. `20_trace_new_threads` prints an event message: `<new thread LWP pid>` every few seconds.

The conclusion is that by explicitly setting `PtraceSetOptions(pid, syscall.PTRACE_O_TRACECLONE)`, we can resume the tracee's execution. When the tracee executes the `clone` system call, it will trigger a TRAP, and the kernel will send a SIGTRAP to notify the tracer of the tracee's running state change. The tracer can then check the corresponding status data to determine if it is a clone event.

If it is a clone event, we can further obtain the LWP PID of the newly cloned thread through `syscall.PtraceGetEventMsg(...)`.

To check if it is a clone event, refer to the `man 2 ptrace` manual for details on the option `PTRACE_O_TRACECLONE`, which explains how the status value is encoded in the case of a clone.

4. Additionally, after setting the option `PTRACE_O_TRACECLONE`, the new thread will automatically be traced, so the new thread will also be paused. If you want the new thread to resume execution, you need to explicitly call `syscall.PtraceDetach` or execute `syscall.PtraceContinue` to allow the new thread to resume execution.

### Further Discussion

With the testing method introduced, we can prompt the user: do you want to track the current thread or the new thread? This is similar to the very useful feature in gdb for debugging multi-process and multi-threaded programs, such as `set follow-fork-mode`. We can choose between `parent`, `child`, or `ask`, and allow switching between these options during debugging. If we plan ahead whether to track the current thread or the child thread (or process) after a fork, this feature will be very useful.

Delve provides a different approach, allowing switching of the debugged thread through `threads`. In reality, Go does not expose thread-related APIs to developers, and most of the time, you should not need to explicitly track the execution of new threads after a clone. Therefore, it is rare to use it like gdb's `set follow-fork-mode` debugging mode. We are just extending the discussion here.
