## Attaching to a Process

### Implementation Goal: `godbg attach -p <pid>`

If a process is already running and we want to debug it, we need to attach to the process to make it stop and wait for the debugger to control it.

Common debuggers like dlv and gdb support passing the target process ID through the `-p pid` parameter to debug running processes.

We will implement the program godbg, which supports the subcommand `attach -p <pid>`. If the target process exists, godbg will attach to it, and the target process will pause execution. Then we'll make godbg sleep for a few seconds before detaching from the target process, which will then resume execution.

> ps: The few seconds of sleep here can be imagined as a series of debugging operations, such as setting breakpoints, checking process registers, examining memory, etc. We will support these capabilities in later sections.

### Basic Knowledge

#### Tracee

First, let's clarify the concept of tracee. Although it appears we're debugging a process, the debugger actually works with individual threads.

A tracee refers to the thread being debugged, not the process. For a multi-threaded program, we may need to trace some or all threads to facilitate debugging. Untraced threads will continue to execute, while traced threads are controlled by the debugger. Even different threads in the same debugged process can be controlled by different tracers.

#### Tracer

A tracer refers to the debugger process (more accurately, thread) that sends debugging control commands to the tracee.

Once a tracer and tracee establish a connection, the tracer can send various debugging commands to the tracee.

#### Ptrace

Our debugger example is written for the Linux platform, and its debugging capabilities depend on Linux ptrace.

Typically, if the debugger is also a multi-threaded program, we need to pay attention to ptrace constraints. After a tracer and tracee establish a tracing relationship, all subsequent debugging commands received by the tracee (traced thread) should come from the same tracer (tracing thread). This means that when implementing the debugger, we need to bind the task that sends debugging commands to the tracee to a specific thread. More specifically, this task can be a goroutine.

Therefore, when we look at the implementation of debuggers like dlv, we find that the goroutine sending debugging commands typically calls `runtime.LockOSThread()` to bind to a thread, specifically for sending debugging instructions (various ptrace operations) to the attached tracee.

> runtime.LockOSThread(), this function binds the calling goroutine to the current operating system thread, meaning this operating system thread will only be used to execute operations on this goroutine. Unless the goroutine calls runtime.UnLockOSThread() to remove this binding, the thread won't be used to schedule other goroutines. The calling goroutine can only execute on the current thread and won't be migrated to other threads by the scheduler. See:
>
> ```
> package runtime // import "runtime"
>
> func LockOSThread()
>     LockOSThread wires the calling goroutine to its current operating system
>     thread. The calling goroutine will always execute in that thread, and no
>     other goroutine will execute in it, until the calling goroutine has made as
>     many calls to UnlockOSThread as to LockOSThread. If the calling goroutine
>     exits without unlocking the thread, the thread will be terminated.
>
>     All init functions are run on the startup thread. Calling LockOSThread from
>     an init function will cause the main function to be invoked on that thread.
>
>     A goroutine should call LockOSThread before calling OS services or non-Go
>     library functions that depend on per-thread state.
> ```
>
> After calling this function, we can meet the tracee's requirements for the tracer: once a tracer attaches to a tracee through ptrace_attach, all subsequent ptrace requests sent to this tracee must come from the same tracer. Both tracee and tracer specifically refer to threads.

When we call attach, the tracee might not have stopped when attach returns. At this point, we need to use the wait method to wait for the tracee to stop and obtain its status information. When debugging ends, we can use the detach operation to let the tracee resume execution.

> Below is the man page description of ptrace operations attach and detach, which we'll use:

    **PTRACE_ATTACH**
    *Attach to the process specified in pid, making it a tracee of*
    *the calling process.  The tracee is sent a SIGSTOP, but will*
    *not necessarily have stopped by the completion of this call;*

> *use waitpid(2) to wait for the tracee to stop.  See the "At‐*
> *taching and detaching" subsection for additional information.*

    **PTRACE_DETACH**
    *Restart the stopped tracee as for PTRACE_CONT, but first de‐*
    *tach from it.  Under Linux, a tracee can be detached in this*
    *way regardless of which method was used to initiate tracing.*

### Code Implementation

**Source code see: golang-debugger-lessons/2_process_attach**

file: main.go

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

const (
	usage = "Usage: go run main.go exec <path/to/prog>"

	cmdExec   = "exec"
	cmdAttach = "attach"
)

func main() {
    // issue: https://github.com/golang/go/issues/7699
    //
    // Why does syscall.PtraceDetach, detach error: no such process?
    // Because ptrace requests should come from the same tracer thread,
    // 
    // ps: If it's not, we might need more complex handling of the tracee's status display, need to consider signals?
    // Currently, this is how the system call parameters are passed.
	runtime.LockOSThread()

	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "%s\n\n", usage)
		os.Exit(1)
	}
	cmd := os.Args[1]

	switch cmd {
	case cmdExec:
		prog := os.Args[2]

		// run prog
		progCmd := exec.Command(prog)
		buf, err := progCmd.CombinedOutput()

		fmt.Fprintf(os.Stdout, "tracee pid: %d\n", progCmd.Process.Pid)

		if err != nil {
			fmt.Fprintf(os.Stderr, "%s exec error: %v, \n\n%s\n\n", err, string(buf))
			os.Exit(1)
		}
		fmt.Fprintf(os.Stdout, "%s\n", string(buf))

	case cmdAttach:
		pid, err := strconv.ParseInt(os.Args[2], 10, 64)
		if err != nil {
			fmt.Fprintf(os.Stderr, "%s invalid pid\n\n", os.Args[2])
			os.Exit(1)
		}

		// check pid
		if !checkPid(int(pid)) {
			fmt.Fprintf(os.Stderr, "process %d not existed\n\n", pid)
			os.Exit(1)
		}

		// attach
		err = syscall.PtraceAttach(int(pid))
		if err != nil {
			fmt.Fprintf(os.Stderr, "process %d attach error: %v\n\n", pid, err)
			os.Exit(1)
		}
		fmt.Fprintf(os.Stdout, "process %d attach succ\n\n", pid)

		// wait
		var (
			status syscall.WaitStatus
			rusage syscall.Rusage
		)
		_, err = syscall.Wait4(int(pid), &status, syscall.WSTOPPED, &rusage)
		if err != nil {
			fmt.Fprintf(os.Stderr, "process %d wait error: %v\n\n", pid, err)
			os.Exit(1)
		}
		fmt.Fprintf(os.Stdout, "process %d wait succ, status:%v, rusage:%v\n\n", pid, status, rusage)

		// detach
		fmt.Printf("we're doing some debugging...\n")
		time.Sleep(time.Second * 10)

		// MUST: call runtime.LockOSThread() first
		err = syscall.PtraceDetach(int(pid))
		if err != nil {
			fmt.Fprintf(os.Stderr, "process %d detach error: %v\n\n", pid, err)
			os.Exit(1)
		}
		fmt.Fprintf(os.Stdout, "process %d detach succ\n\n", pid)

	default:
		fmt.Fprintf(os.Stderr, "%s unknown cmd\n\n", cmd)
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

The program logic here is also relatively simple:

- When the program runs, it first checks the command line arguments,
  - `godbg attach <pid>`, there should be at least 3 arguments. If the number of arguments is incorrect, it reports an error and exits;
  - Next, it checks the second argument. If it's an invalid subcommand, it also reports an error and exits;
  - If it's attach, then the pid parameter should be an integer, if not, it exits directly;
- With normal arguments, it begins trying to attach to the tracee;
- After attaching, the tracee might not stop immediately, so we need to wait to get its status changes;
- After the tracee stops, we sleep for 10 seconds, as if we're doing some debugging operations;
- After 10 seconds, the tracer tries to detach from the tracee, letting the tracee resume execution.

When implementing on the Linux platform, we need to consider platform-specific issues, including:

- Checking if a pid corresponds to a valid process. Usually, we would use `exec.FindProcess(pid)` to check, but on Unix platforms, this function always returns OK, so it doesn't work. Therefore, we use the classic approach of `kill -s 0 pid` to check the validity of the pid.
- When performing detach operations between tracer and tracee, we use the ptrace system call, which is also platform-dependent. As the Linux man page states, we must ensure that all ptrace requests for a tracee come from the same tracer thread, which we need to pay attention to in our implementation.

### Code Testing

Here's a test example to help you better understand the role of attach and detach.

First, we start a command in bash that runs continuously, then get its pid and have godbg attach to it, observing the program's pause and resume execution.

For example, we first execute the following command in bash, which prints the current pid every second:

```bash
$ while [ 1 -eq 1 ]; do t=`date`; echo "$t pid: $$"; sleep 1; done

Sat Nov 14 14:29:04 UTC 2020 pid: 1311
Sat Nov 14 14:29:06 UTC 2020 pid: 1311
Sat Nov 14 14:29:07 UTC 2020 pid: 1311
Sat Nov 14 14:29:08 UTC 2020 pid: 1311
Sat Nov 14 14:29:09 UTC 2020 pid: 1311
Sat Nov 14 14:29:10 UTC 2020 pid: 1311
Sat Nov 14 14:29:11 UTC 2020 pid: 1311
Sat Nov 14 14:29:12 UTC 2020 pid: 1311
Sat Nov 14 14:29:13 UTC 2020 pid: 1311
Sat Nov 14 14:29:14 UTC 2020 pid: 1311  ==> 14s
^C
```

Then we execute the command:

```bash
$ go run main.go attach 1311

process 1311 attach succ

process 1311 wait succ, status:4991, rusage:{{12 607026} {4 42304} 43580 0 0 0 375739 348 0 68224 35656 0 0 0 29245 153787}
```

### Discussion

To help readers quickly grasp the core debugging principles, we intentionally simplified the example. For instance, the debugged process is a single-threaded program. Would the results be different for a multi-threaded program? Yes, and we would need to make some special handling. Let's discuss this further.

#### Issue: Multi-threaded Program Still Running After Attach?

Some readers might develop a Go program as the debugged program and may encounter some confusion due to multi-threading. Let's address this.

If I use the following Go program as the debugged program:

```go
import (
    "fmt"
    "time"
    "os"
)
func main() {
    for  {
        time.Sleep(time.Second)
        fmt.Println("pid:", os.Getpid())
    }
}
```

You might find that after executing `godbg attach <pid>`, the program is still running. Why is this?

This is because Go programs are inherently multi-threaded - sysmon, garbage collection, and other features may use separate threads. When we attach, we're only attaching to one thread of the process corresponding to the pid. Other threads remain untraced and can execute normally.

So which thread does ptrace attach to when we specify a pid? **Isn't the thread corresponding to this pid the one executing main.main? Let me answer: Actually, not necessarily!**

**In Go programs, the function main.main is executed by the main goroutine, but the main goroutine has no default binding relationship with the main thread.** So it's incorrect to assume that main.main must run on the thread corresponding to the pid!

> ps: The appendix "Go Runtime: Go Program Startup Process" analyzes the startup process of Go programs, which can help readers clear up any doubts about main.main, main goroutine, and main thread.

In Linux, threads are implemented through Lightweight Processes (LWP). The pid parameter in ptrace is actually the process id of the LWP corresponding to the thread. Performing a ptrace attach operation on process pid only results in the thread corresponding to that process pid being traced.

**In debugging scenarios, a tracee refers to a thread, not all threads contained in a process**, although sometimes we use process terminology for convenience in description.

> A multi-threaded process can be understood as a thread group containing multiple threads. Threads in the thread group are created using the clone system call with the CLONE_THREAD parameter to ensure all newly created threads have the same pid, similar to how clone+CLONE_PARENT makes all cloned child processes have the same parent process id.
>
> In Go, threads are created using the clone system call with the following options:
>
> ```go
> cloneFlags = _CLONE_VM | /* share memory */
>     _CLONE_FS | /* share cwd, etc */
>     _CLONE_FILES | /* share fd table */
>     _CLONE_SIGHAND | /* share sig handler table */
>     _CLONE_SYSVSEM | /* share SysV semaphore undo lists (see issue #20763) */
>     _CLONE_THREAD /* revisit - okay for now */
> ```
>
> For more information about clone options, you can check the man page `man 2 clone`.

A ptrace link is established between the thread (or LWP) identified by pid and the thread (or LWP) sending the ptrace request. Their roles are tracee and tracer respectively. The tracee expects all subsequent ptrace requests to come from this tracer. For this reason, Go programs, which are naturally multi-threaded, need to ensure that the goroutine actually sending ptrace requests must execute on the same thread.

If there are other threads in the debugged process, they can still run. This is why some readers find that the debugged program is still continuously outputting - because the tracer hasn't set a breakpoint inside main.main, and the main goroutine executing this function might be executed by other untraced threads, so you can still see the program continuously outputting.

#### Issue: How to Stop the Thread Executing main.main?

If you want to stop the debugged process from executing, the debugger needs to enumerate the threads contained in the process and perform ptrace attach operations on them one by one. Specifically for Linux, you can list all thread (or LWP) pids under `/proc/<pid>/task` and perform ptrace attach on each one.

We will further improve the attach command in the subsequent process to make it capable of debugging in multi-threaded environments.

#### Issue: How to Determine if a Process is Multi-threaded?

How can we determine if the target process is a multi-threaded program? There are two simple methods to help determine this.

- `top -H -p pid`

  The `-H` option will list the threads under process pid. The process 5293 below has 4 threads. In Linux, threads are implemented through lightweight processes, and the lightweight process with PID 5293 is the main thread.

  ```bash
  $ top -H -p 5293
  ........
  PID USER      PR  NI    VIRT    RES    SHR S %CPU %MEM     TIME+ COMMAND                                                     
   5293 root      20   0  702968   1268    968 S  0.0  0.0   0:00.04 loop                                                        
   5294 root      20   0  702968   1268    968 S  0.0  0.0   0:00.08 loop                                                        
   5295 root      20   0  702968   1268    968 S  0.0  0.0   0:00.03 loop                                                        
   5296 root      20   0  702968   1268    968 S  0.0  0.0   0:00.03 loop
  ```

  In the top display information, column S represents the process state. Common values and their meanings are as follows:

  ```bash
  'D' = uninterruptible sleep
  'R' = running
  'S' = sleeping
  'T' = traced or stopped
  'Z' = zombie
  ```

  You can identify which threads in a multi-threaded program are being debugged and traced by the state **'T'**.

- `ls /proc/<pid>/task`

  ```bash
  $ ls /proc/5293/task/

  5293/ 5294/ 5295/ 5296/
  ```

  In Linux, /proc is a virtual file system that contains various state information during system runtime. The following command can view the threads under process 5293. The result is the same as what top shows.

#### Issue: Explanation of syscall.Wait4 Parameters

The Linux system has multiple system calls for waiting for process state changes, with subtle differences in usage and functionality. We use syscall.Wait4 here, which corresponds to the Linux system call wait4. For detailed usage instructions, you can refer to the man page.

The strongly relevant parts from the man page are as follows:

man 2 wait4

> **Name**
>
> *wait3, wait4 - wait for process to change state, BSD style*
>
> **SYNOPSIS**
>
> pid_t wait3(int *wstatus, int options,
> struct rusage *rusage);
>
> pid_t wait4(pid_t pid, int *wstatus, int options,
> struct rusage *rusage);
>
> **Description**
>
> **These functions are obsolete; use waitpid(2) or waitid(2) in new programs.**
>
> The wait3() and wait4() system calls are similar to waitpid(2), but additionally return resource usage information about the child in the structure pointed to by rusage.
>
> man 2 waitpid
>
> **Name**
>
> wait, waitpid, waitid - wait for process to change state
>
> **SYNOPSIS**
>
> pid_t wait(int *wstatus);
>
> pid_t waitpid(pid_t pid, int *wstatus, int options);
>
> int waitid(idtype_t idtype, id_t id, siginfo_t*infop, int options);
> /* This is the glibc and POSIX interface; see
> NOTES for information on the raw system call. */
>
> **SYNOPSIS**
>
> All of these system calls are used to wait for state changes in a child of the calling process, and obtain information about the child whose state has changed. A state change is considered to be: the child terminated;
> the child was stopped by a signal; or the child was resumed by a signal. In the case of a terminated child, performing a wait allows the system to release the resources associated with the child; if a wait is not performed, then the terminated child remains in a "zombie" state (see NOTES below).
>
> If a child has already changed state, then these calls return immediately. Otherwise, they block until either a child changes state or a signal handler interrupts the call (assuming that system calls are not automatically restarted using the SA_RESTART flag of sigaction(2)). In the remainder of this page, a child whose state has changed and which has not yet been waited upon by one of these system calls is termed waitable.
>
> wait() and waitpid()
> The wait() system call suspends execution of the calling process until one of its children terminates. The call wait(&wstatus) is equivalent to:
>
> waitpid(-1, &wstatus, 0);
>
> The waitpid() system call suspends execution of the calling process until a child specified by pid argument has changed state. By default, waitpid() waits only for terminated children, but this behavior is modifiable via the options argument, as described below.
>
> The value of pid can be:
>
> - \<-1: meaning wait for any child process whose process group ID is equal to the absolute value of pid.
> - -1: meaning wait for any child process.
> - 0: meaning wait for any child process whose process group ID is equal to that of the calling process.
> - \>0: meaning wait for the child whose process ID is equal to the value of pid.
>
> The value of options is an OR of zero or more of the following constants:
>
> - WNOHANG: ... blabla
> - WUNTRACED: ... blabla
> - WCONTINUED: ... blabla
>
> (For Linux-only options, see below.)
>
> - WIFSTOPPED: returns true if the child process was stopped by delivery of a signal; this is possible only if the call was done using WUNTRACED or when the child is being traced (see ptrace(2)).
> - ... blabla
