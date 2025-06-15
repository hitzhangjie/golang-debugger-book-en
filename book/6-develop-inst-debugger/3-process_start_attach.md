## Starting & Attaching to a Process

### Implementation Goal: Start a Process and Attach

#### Consideration: How to Make a Process Stop Immediately After Starting?

The previous sections introduced starting a process using `exec.Command(prog, args...)` and attaching to a running process using the ptrace system call. Readers might wonder: does this method of starting debugging meet our debugging requirements?

When trying to attach to a running process, the process might have already executed instructions far beyond the point we're interested in. For example, if we want to debug and trace the initialization steps of a Go program before main.main executes, the method of starting the program first and then attaching is undoubtedly too late - main.main might have already started executing, or the program might have even finished.

Considering this, we need to think about whether there are issues with the implementation method in the "Starting a Process" section. How can we make a process stop immediately after starting to wait for debugging? If we can't achieve this, it will be difficult to perform efficient debugging.

#### Kernel: What Does the Kernel Do When Starting a Process?

Starting a specified process ultimately comes down to a combination of fork+exec:

```go
cmd := exec.Command(prog, args...)
cmd.Run()
```

- cmd.Run() first creates a child process through `fork`;
- Then the child process loads and runs the target program through the `execve` function;

However, if this is all we do, the program will execute immediately, possibly without giving us any opportunity for debugging. We might not even have time to attach to the process and add breakpoints before the program finishes executing.

We need the target program's instructions to stop immediately before they start executing! To achieve this, we need to rely on the ptrace operation `PTRACE_TRACEME`.

#### Kernel: What Exactly Does PTRACE_TRACEME Do?

Let's first write a simple C program to illustrate this process. After this, we'll look at some kernel code to deepen our understanding of the PTRACE_TRACEME operation and the process startup process. These codes are implemented in C, and this brief example uses C to help readers get familiar with C syntax in advance.

```c
#include <sys/ptrace.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

// see /usr/include/sys/user.sh `struct user_regs_struct`
define ORIG_EAX_FIELD = 11
define ORIG_EAX_ALIGN = 8 // 8 for x86_64, 4 for x86

int main()
{   pid_t child;
    long orig_eax;
    child = fork();
    if(child == 0) {
        ptrace(PTRACE_TRACEME, 0, NULL, NULL);
        execl("/bin/ls", "~", NULL);
    }
    else {
        wait(NULL);
        orig_eax = ptrace(PTRACE_PEEKUSER, child, (void *)(ORIG_EAX_FIELD * ORIG_EAX_ALIGN), (void *)NULL);
        printf("The child made a system call %ld\n", orig_eax);
        ptrace(PTRACE_CONT, child, NULL, NULL);
    }
    return 0;
}
```

In the above example, the process first performs a fork. A fork return value of 0 indicates the current process is the child process. The child process executes a `ptrace(PTRACE_TRACEME,...)` operation, asking the kernel to do something on its behalf.

Let's look at what the kernel actually does. Below is the definition of ptrace, with irrelevant parts omitted. If the ptrace request is PTRACE_TRACEME, the kernel will update the debug information flag bit `current->ptrace = PT_PTRACED` of the current process `task_struct* current`.

**file: /kernel/ptrace.c**

```c
// ptrace system call implementation
SYSCALL_DEFINE4(ptrace, long, request, long, pid, unsigned long, addr,
		unsigned long, data)
{
	...

	if (request == PTRACE_TRACEME) {
		ret = ptrace_traceme();
		...
		goto out;
	}
	...
  
 out:
	return ret;
}

/**
 * ptrace_traceme is a simple wrapper function for ptrace(PTRACE_PTRACEME,...),
 * which performs checks and sets the process flag bit PT_PTRACED.
 */
static int ptrace_traceme(void)
{
	...
	/* Are we already being traced? */
	if (!current->ptrace) {
		...
		if (!ret && !(current->real_parent->flags & PF_EXITING)) {
			current->ptrace = PT_PTRACED;
			...
		}
	}
	...
	return ret;
}
```

#### Kernel: How Does PTRACE_TRACEME Affect execve?

In the C library functions, common exec family functions include execl, execlp, execle, execv, execvp, execvpe, all of which are implemented by the system call execve.

The code execution path of the execve system call roughly includes:

```c
-> sys_execve
 |-> do_execve
   |-> do_execveat_common
```

The code execution path of the do_execveat_common function roughly includes the following, whose purpose is to replace the current process's code segment and data segment (initialized & uninitialized data) with the newly loaded program, then execute the new program.

```c
-> retval = bprm_mm_init(bprm);
 |-> retval = prepare_binprm(bprm);
   |-> retval = copy_strings_kernel(1, &bprm->filename, bprm);
     |-> retval = copy_strings(bprm->envc, envp, bprm);
       |-> retval = exec_binprm(bprm);
         |-> retval = copy_strings(bprm->argc, argv, bprm);
```

There's quite a bit of code involved here. Let's focus on `exec_binprm(bprm)` in the above process, which contains part of the logic for executing the new program.

**file: fs/exec.c**

```c
static int exec_binprm(struct linux_binprm *bprm)
{
	pid_t old_pid, old_vpid;
	int ret;

	/* Need to fetch pid before load_binary changes it */
	old_pid = current->pid;
	rcu_read_lock();
	old_vpid = task_pid_nr_ns(current, task_active_pid_ns(current->parent));
	rcu_read_unlock();

	ret = search_binary_handler(bprm);
	if (ret >= 0) {
		audit_bprm(bprm);
		trace_sched_process_exec(current, old_pid, bprm);
		ptrace_event(PTRACE_EVENT_EXEC, old_vpid);
		proc_exec_connector(current);
	}

	return ret;
}
```

Here, `exec_binprm(bprm)` internally calls `ptrace_event(PTRACE_EVENT_EXEC, message)`, which checks the process's ptrace status. Once it finds that the process's ptrace flag bit is set to PT_PTRACED, the kernel will send a SIGTRAP signal to the process, thus entering the SIGTRAP signal handling logic.

**file: include/linux/ptrace.h**

```c
/**
 * ptrace_event - possibly stop for a ptrace event notification
 * @event:	%PTRACE_EVENT_* value to report
 * @message:	value for %PTRACE_GETEVENTMSG to return
 *
 * Check whether @event is enabled and, if so, report @event and @message
 * to the ptrace parent.
 *
 * Called without locks.
 */
static inline void ptrace_event(int event, unsigned long message)
{
	if (unlikely(ptrace_event_enabled(current, event))) {
		current->ptrace_message = message;
		ptrace_notify((event << 8) | SIGTRAP);
	} else if (event == PTRACE_EVENT_EXEC) {
		/* legacy EXEC report via SIGTRAP */
		if ((current->ptrace & (PT_PTRACED|PT_SEIZED)) == PT_PTRACED)
			send_sig(SIGTRAP, current, 0);
	}
}
```

In Linux, the SIGTRAP signal will cause the process to pause execution and notify its parent process of its state change. The parent process obtains the child process's state change information through the wait system call.

```bash
|-> ptrace_notify
	|-> ptrace_do_notify
		|-> ptrace_stop
			|-> do_notify_parent_cldstop
```

Let's take a final look at how the function ptrace_stop -> do_notify_parent_cldstop() that notifies the tracer or its real parent process is implemented:

```c
static int ptrace_stop(int exit_code, int why, unsigned long message,
		       kernel_siginfo_t *info)
	__releases(&current->sighand->siglock)
	__acquires(&current->sighand->siglock)
{
	...

	/*
	 * Notify parents of the stop.
	 *
	 * While ptraced, there are two parents - the ptracer and
	 * the real_parent of the group_leader.  The ptracer should
	 * know about every stop while the real parent is only
	 * interested in the completion of group stop.  The states
	 * for the two don't interact with each other.  Notify
	 * separately unless they're gonna be duplicates.
	 */
	if (current->ptrace)
		do_notify_parent_cldstop(current, true, why);
	if (gstop_done && (!current->ptrace || ptrace_reparented(current)))
		do_notify_parent_cldstop(current, false, why);
	...
}

/**
 * do_notify_parent_cldstop - notify parent of stopped/continued state change
 * @tsk: task reporting the state change
 * @for_ptracer: the notification is for ptracer
 * @why: CLD_{CONTINUED|STOPPED|TRAPPED} to report
 *
 * Notify @tsk's parent that the stopped/continued state has changed.  If
 * @for_ptracer is %false, @tsk's group leader notifies to its real parent.
 * If %true, @tsk reports to @tsk->parent which should be the ptracer.
 *
 * CONTEXT:
 * Must be called with tasklist_lock at least read locked.
 */
static void do_notify_parent_cldstop(struct task_struct *tsk,
				     bool for_ptracer, int why)
{
	...
	if (for_ptracer) {
		parent = tsk->parent;
	} else {
		tsk = tsk->group_leader;
		parent = tsk->real_parent;
	}

	clear_siginfo(&info);
	info.si_signo = SIGCHLD;
	info.si_errno = 0;
	info.si_pid = task_pid_nr_ns(tsk, task_active_pid_ns(parent));
	info.si_uid = from_kuid_munged(task_cred_xxx(parent, user_ns), task_uid(tsk));
	info.si_utime = nsec_to_clock_t(utime);
	info.si_stime = nsec_to_clock_t(stime);

 	info.si_code = why;
 	switch (why) {
 	case CLD_CONTINUED:
 		info.si_status = SIGCONT;
 		break;
 	case CLD_STOPPED:
 		info.si_status = tsk->signal->group_exit_code & 0x7f;
 		break;
 	case CLD_TRAPPED:
 		info.si_status = tsk->exit_code & 0x7f;
 		break;
 	default:
 		BUG();
 	}

	sighand = parent->sighand;
	if (sighand->action[SIGCHLD-1].sa.sa_handler != SIG_IGN &&
	    !(sighand->action[SIGCHLD-1].sa.sa_flags & SA_NOCLDSTOP))
		send_signal_locked(SIGCHLD, &info, parent, PIDTYPE_TGID);
	/*
	 * Even if SIGCHLD is not generated, we must wake up wait4 calls.
	 */
	__wake_up_parent(tsk, parent);
	...
}
```

这里的tracee通知tracer（或者父进程）我已经停下来了，是通过发送信号 SIGCHLD 的方式来通知的。

那么tracer（或者父进程）wait4 的实现，是怎么实现的呢? 我们这里也进行了一个精简版的总结。

Simply put, the tracer or parent process adds itself to a wait queue for child process state changes, then sets itself to the "INTERRUPTIBLE" state, meaning it can be awakened by signals, such as the SIGCHLD signal. Then the tracer calls process scheduling once, yielding the CPU to wait until the tracee stops due to PTRACE_TRACEME and sends a SIGCHLD signal to notify the tracer, at which point the tracer is awakened and executes the signal handler.

At this point, the tracer will change itself from the "INTERRUPTIBLE" state to the "RUNNING" state, remove itself from the wait queue for tracee state changes, and wait to be scheduled by the scheduler.

Then, after the tracer's syscall.Wait4 operation completes, it can continue with subsequent ptrace operations.

#### Put it Together

Now, let's review the entire process and straighten it out by combining the above example.

First, after the parent process calls fork and the child process is successfully created, it is in the ready state and can run. Then, the child process first executes `ptrace(PTRACE_TRACEME, ...)` to tell the kernel "**The current process wants to stop after executing the new program, waiting for the parent process's ptrace operation, so please notify me when it's time to stop**". The child process then executes execve to load the new program and reinitialize the process execution required code segment, data segment, etc.

Before the new program is initialized, the kernel will adjust the process status to "**UnInterruptible Wait**" to prevent it from being scheduled and responding to external signals. After completion, it will be adjusted to "**Interruptible Wait**", meaning that if a signal arrives, the process is allowed to handle the signal.

Next, if the process does not have special ptrace flag bits, the child process status will be updated to runnable waiting for next scheduling. When the kernel finds that the child process ptrace flag bit is PT_PTRACED, the kernel will execute such logic: the kernel sends a **SIGTRAP** signal to this child process, which will be added to the process's pending signal queue, and try to wake up the process. When the kernel task scheduler schedules to this process, it finds that there is a pending signal arrival, and will execute the SIGTRAP signal handling logic, although SIGTRAP is special and is handled by the kernel.

**What does SIGTRAP signal handling specifically do?** It will pause the target process execution and notify its parent process of its state change through SIGCHLD signal. Note that the parent process calls `ptrace(PTRACE_ATTACH, ...)` operation does not wait for tracee to stop. The parent process obtains the tracee state change information through the system call wait, and at this time the tracee might not have stopped. tracer calls wait will change tracer status to "**Interruptible Wait**", and current tracer will be added to tracee process state change waiting queue. Until the previous mentioned kernel processing tracee SIGTRAP signal and stopping it, then sending SIGCHLD signal to notify tracer to wake up tracer.

At this point, tracer is awakened, and wait can return the tracee process state change information. tracer finds that tracee process has stopped (and because of SIGTRAP stopped), can initiate subsequent ptrace operation corresponding to tracer debugging command, such as reading and writing memory data.

### Code Implementation

**Source code see: golang-debugger-lessons/3_process_startattach**

Similar to the C language fork+exec approach, the Go standard library provides a ForkExec function implementation, allowing us to rewrite the above C language example in Go. However, the Go standard library provides another more concise way.

We first get a cmd object through `cmd := exec.Command(prog, args...)`, and open the process flag bit `cmd.SysProcAttr.Ptrace=true` before starting the process with `cmd.Start()`, then start the process with `cmd.Start()`, and finally call `Wait` function to wait for the child process (because SIGTRAP) to stop and get the child process status.

After this, the parent process can continue to do some debugging related work, such as reading and writing memory, etc.

Here's the example code, which is modified from the previous example code:

```go
package main

import (
    "fmt"
    "os"
    "os/exec"
    "syscall"
)

func main() {
    if len(os.Args) < 3 {
        fmt.Fprintf(os.Stderr, "Usage: %s exec <prog> [args...]\n", os.Args[0])
        os.Exit(1)
    }

    cmd := exec.Command(os.Args[2], os.Args[3:]...)
    cmd.SysProcAttr = &syscall.SysProcAttr{
        Ptrace: true,
    }

    err := cmd.Start()
    if err != nil {
        fmt.Fprintf(os.Stderr, "start error: %v\n", err)
        os.Exit(1)
    }

    var (
        status syscall.WaitStatus
        rusage syscall.Rusage
    )
    _, err = syscall.Wait4(cmd.Process.Pid, &status, syscall.WSTOPPED, &rusage)
    if err != nil {
        fmt.Fprintf(os.Stderr, "wait error: %v\n", err)
        os.Exit(1)
    }

    fmt.Printf("process %d stopped: %v\n", cmd.Process.Pid, status.Stopped())

    // TODO: implement debug session
    fmt.Println("debug session started...")
    fmt.Println("type 'exit' to quit")

    // Simple debug session
    for {
        var input string
        fmt.Print("godbg> ")
        fmt.Scanln(&input)
        if input == "exit" {
            break
        }
    }

    // Let the process continue
    err = syscall.PtraceCont(cmd.Process.Pid, 0)
    if err != nil {
        fmt.Fprintf(os.Stderr, "continue error: %v\n", err)
        os.Exit(1)
    }
}
```

### Code Testing

Next, we test the adjusted code:

```bash
$ go build -o godbg main.go
$ ./godbg exec ls
process 2479 stopped: true
debug session started...
type 'exit' to quit
godbg> exit
cmd go.mod go.sum LICENSE main.go syms target
```

First, we enter the example code directory to compile and install godbg, then run `godbg exec ls`, intending to debug the PATH executable program `ls`.

godbg will start the ls process and stop it (through SIGTRAP) by PTRACE_TRACEME, and we can see from the debugger output `process 2479 stopped: true`, indicating that the process pid 2479 has stopped executing.

And also started a debugging session, the terminal command prompt should become `godbg> `, indicating that the debugging session is waiting for user input debugging command, we have not implemented other debugging commands except `exit` command, we input `exit` to exit the debugging session.

> NOTE: About debugging session
>
> Here, the debugging session allows user input debugging command, all user input will be passed to cobra generated debugRootCmd processing, debugRootCmd contains many subcmd, such as breakpoint, list, continue, step, etc. debugging commands.
>
> At the time of writing this document, we are still based on cobra-prompt to manage debugging session command and input completion, after we input some information, prompt will process our input and pass it to debugRootCmd registered same name command for processing.
>
> For example, we input exit, then debugRootCmd registered exitCmd will be called for processing. exitCmd just executes os.Exit(0) to let process exit, before exiting, the kernel will automatically do some cleanup operations, such as tracee being tracked by it will be automatically removed from tracking by the kernel, allowing tracee to continue executing.

When we exit the debugging session, we will use `ptrace(PTRACE_COND,...)` operation to restore the tracee execution, that is, ls normal execution command to list the files in the directory, we also saw it output the current directory file information `cmd go.mod go.sum LICENSE main.go syms target`.

`godbg exec <prog>` command is now all right!

> NOTE: In the example, the program exits without displaying a call to `ptrace(PTRACE_COND,...)` to restore tracee execution. In fact, if tracee is still there when tracer exits, the kernel will automatically remove tracee tracking state.
>
> If tracee is our display (not attach), then we should kill the process (or allow the choice to kill the process or let it continue executing) instead of defaulting to continue executing.

Again, if we exec execute a go program, how should we handle it? Because go program is naturally multi-threaded program, from its main thread startup to create other gc, sysmon, execute numerous goroutines threads is a process, then this process we are difficult to perceive human, how does the debugger automatically start ptrace attach for these numerous threads created in the process?

There's no good way, as a normal user program, the debugger can only request the operating system to provide services on behalf of it, this involves the specific ptrace attach options `PTRACE_O_TRACECLONE`. Adding this option will cause the kernel to send necessary signals to the new thread when the tracee is cloned, and when the new thread is scheduled, it will naturally stop.

> **PTRACE_O_TRACECLONE**:
>
> Stop the tracee at the next clone(2) and automatically start tracing the newly cloned process, which will start with a SIGSTOP, or PTRACE_EVENT_STOP if PTRACE_SEIZE was used.

### This Section Summary

This section implements a complete "start, track" implementation principle, code explanation, example demonstration. This section uses start+attach or exec+attach expressions, doing this is just to highlight the layered relationship of the section content.

Strictly speaking, we should use trace instead of attach expression. Because attach will mislead readers to think that it is tracer actively `ptrace(PTRACE_ATTACH,)` implemented, it is actually tracee actively `ptrace(PTRACE_TRACEME,)` implemented. However, attach is more in line with people's habits, so we still use attach this term.

Also for multi-thread debugging, if we want new threads created automatically to be traced, we need tracer to execute system call `syscall.PtraceSetOptions(traceePID, syscall.PTRACE_O_TRACECLONE)` to complete the tracee setting, so that when tracee internal new threads, the kernel will automatically handle it to stop and notify tracer. In addition, for better debugging, usually tracer launch tracee after immediately attach tracee, then immediately set PTRACE_O_TRACECLONE option for tracee, so it's foolproof, tracee and its started threads will be under tracer tracking.

> ps: We will see if there is a need to specially open a small section, corresponding demo …… Actually, our final demo has this part of code, comment explanation.

### Reference Content

- Playing with ptrace, Part I, Pradeep Padala, https://www.linuxjournal.com/article/6100
- Playing with ptrace, Part II, Pradeep Padala, https://www.linuxjournal.com/article/6210
- Understanding Linux Execve System Call, Wenbo Shen, https://wenboshen.org/posts/2016-09-15-kernel-execve.html
