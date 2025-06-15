## Extended Reading: How to Track Already Created Threads

### Implementation Goal: Tracking Already Created Threads

The process being debugged is a multi-threaded program, and when we are ready to start debugging, these threads have already been created and are running. When we perform the debugger attach operation, we do not enumerate all threads and manually attach each one. For convenience, we only manually attach the process and hope that the program side can handle the attach operations for other threads within the process, except for the main thread.

Take Delve as an example, it may not immediately enumerate all threads and attach them one by one after `dlv attach <pid>`, but it should have this capability. For instance, when a debugger wants to track a specific thread, we can easily execute this operation, such as using `dlv>threads` to view the thread list, and then `dlv> thread <n>` to specifically track a particular thread.

Go programs are inherently multi-threaded, and they provide developers with goroutine concurrency interfaces, not thread-related interfaces. Therefore, even if Delve has this capability, it may not frequently use thread-related debugging commands. Due to the GMP scheduling model, you cannot be certain what is executing on the same thread, as the goroutines it executes will switch back and forth. Instead, `dlv> goroutines` and `dlv> goroutine <n>` are used more frequently.

Anyway, we must emphasize that we still hope to understand the underlying details of multi-threaded debugging. You might develop a debugger for another language in the future, right? It doesn't have to be Go. If that language is thread-oriented concurrency, the practical value of this knowledge still exists.

### Basic Knowledge

How do we obtain all threads within a process? We can execute `top -H -p <pid>` to list all thread information of the specified process and parse to get all thread IDs. However, the Linux `/proc` virtual file system provides a more convenient way. In fact, we just need to traverse all directory names under `/proc/<pid>/task`. The Linux kernel maintains task information corresponding to threads in the above directory, and each directory name is a thread LWP's PID. Each directory's content contains some information about this task.

For example, let's look at some information for the process with PID=1:

```bash
root🦀 ~ $ ls /proc/1/task/1/
arch_status  clear_refs  environ  io         mounts     oom_score_adj  sched         stack    uid_map
attr         cmdline     exe      limits     net        pagemap        schedstat     stat     wchan
auxv         comm        fd       maps       ns         personality    setgroups     statm
cgroup       cpuset      fdinfo   mem        oom_adj    projid_map     smaps         status
children     cwd         gid_map  mountinfo  oom_score  root           smaps_rollup  syscall
```

The `/proc` virtual file system is an interface provided by the kernel to interact with the kernel, which can be read and written. This is not a hack but a very standard method. Common tools like `top`, `vmstat`, `cgroup`, etc., also achieve related functions by accessing `/proc`.
OK, for our debugger, we currently only need to know:

- To enumerate all threads of a process, we traverse the directories under `/proc/<pid>/task`;
- To read its complete instruction data, we read the `exe` file in the directory;
- To read its startup parameter data, for convenience in restarting the debugged process or restarting debugging, we read the `cmdline` file in the directory;

OK, we can ignore the others for now.

### Design Implementation

The implementation code for this part can be found in [hitzhangjie/golang-debugger-lessons](https://github.com/hitzhangjie/golang-debugger-lessons) / 21_trace_old_threads.

First, for convenience in testing, we prepare a test program `testdata/fork_noquit.c`, similar to the previous section's `testdata/fork.c`. It creates threads and prints PID and TID information, but the difference is that the threads here never exit, mainly to give us more time for debugging and avoid tracking failures due to thread exit.

```c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <pthread.h>

pid_t gettid(void);

void *threadfunc(void *arg) {
    printf("process: %d, thread: %u\n", getpid(), syscall(SYS_gettid));
    while (1) {
        sleep(1);
    }
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
    while(1) {
        sleep(1);
    }
}
```

This program can be compiled with `gcc -o fork_noquit fork_noquit.c -lpthread`, and then run `./fork_noquit` to observe its output.

Next, let's look at the debugger's code logic. This is mainly to demonstrate how to track already created threads in the process being debugged, and how to switch from tracking one thread to another.

The core logic of the program is as follows:

- We execute `./21_trace_old_threads $(pidof fork_noquit)`, which checks if the process exists.
- Then, we enumerate the threads already created in the process by reading information from `/proc` and output all thread IDs.
- We prompt the user to input a target thread ID to track, and after input, we start tracking this thread.
- When tracking a thread, if there was a previously tracked thread, we need to stop tracking the old thread before continuing to track the new thread.

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

	fmt.Fprintf(os.Stdout, "===step1===: check target process existed or not\n")
	// pid
	pid, err := strconv.Atoi(os.Args[1])
	if err != nil {
		panic(err)
	}

	if !checkPid(int(pid)) {
		fmt.Fprintf(os.Stderr, "process %d not existed\n\n", pid)
		os.Exit(1)
	}

	// enumerate all threads
	fmt.Fprintf(os.Stdout, "===step2===: enumerate created threads by reading /proc\n")

	// read dir entries of /proc/<pid>/task/
	threads, err := readThreadIDs(pid)
	if err != nil {
		panic(err)
	}
	fmt.Fprintf(os.Stdout, "threads: %v\n", threads)

	// prompt user which thread to attach
	var last int64

	// attach thread <n>, or switch thread to another one thread <m>
	for {
		fmt.Fprintf(os.Stdout, "===step3===: supposing running `dlv> thread <n>` here\n")
		var target int64
		n, err := fmt.Fscanf(os.Stdin, "%d\n", &target)
		if n == 0 || err != nil || target <= 0 {
			panic("invalid input, thread id should > 0")
		}

		if last > 0 {
			if err := syscall.PtraceDetach(int(last)); err != nil {
				fmt.Fprintf(os.Stderr, "switch from thread %d to thread %d error: %v\n", last, target, err)
				os.Exit(1)
			}
			fmt.Fprintf(os.Stderr, "switch from thread %d thread %d\n", last, target)
		}

		// attach
		err = syscall.PtraceAttach(int(target))
		if err != nil {
			fmt.Fprintf(os.Stderr, "thread %d attach error: %v\n\n", target, err)
			os.Exit(1)
		}
		fmt.Fprintf(os.Stdout, "process %d attach succ\n\n", target)

		// check target process stopped or not
		var status syscall.WaitStatus
		var rusage syscall.Rusage
		_, err = syscall.Wait4(int(target), &status, 0, &rusage)
		if err != nil {
			fmt.Fprintf(os.Stderr, "process %d wait error: %v\n\n", target, err)
			os.Exit(1)
		}
		if !status.Stopped() {
			fmt.Fprintf(os.Stderr, "process %d not stopped\n\n", target)
			os.Exit(1)
		}
		fmt.Fprintf(os.Stdout, "process %d stopped\n\n", target)

		regs := syscall.PtraceRegs{}
		if err := syscall.PtraceGetRegs(int(target), &regs); err != nil {
			fmt.Fprintf(os.Stderr, "get regs fail: %v\n", err)
			os.Exit(1)
		}
		fmt.Fprintf(os.Stdout, "tracee stopped at %0x\n", regs.PC())

		last = target
		time.Sleep(time.Second)
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

// reads all thread IDs associated with a given process ID.
func readThreadIDs(pid int) ([]int, error) {
	dir := fmt.Sprintf("/proc/%d/task", pid)
	files, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}

	var threads []int
	for _, file := range files {
		tid, err := strconv.Atoi(file.Name())
		if err != nil { // Ensure that it's a valid positive integer
			continue
		}
		threads = append(threads, tid)
	}
	return threads, nil
}
```

### Code Testing

1. First, let's look at `testdata/fork_noquit.c`. This program creates a pthread thread every few seconds.

The main thread and other threads will print the PID and TID (where TID is the corresponding LWP's PID) of the thread.

> Note: The difference between `fork_noquit.c` and `fork.c` is that each thread continuously `sleep(1)` and never exits. The purpose is that our test takes a long time, and keeping the threads from exiting can avoid failures when we input a thread ID to execute `attach thread` or `switch thread1 to thread2` due to the thread already exiting.

Below is the execution of the program waiting to be debugged:

```bash
zhangjie🦀 testdata(master) $ ./fork_noquit
process: 12368, thread: 12368
process: 12368, thread: 12369
process: 12368, thread: 12527
process: 12368, thread: 12599
process: 12368, thread: 12661
...
```

2. We will simultaneously observe the execution of `./21_trace_old_threads <fork_noquit program process pid>`.

```bash
zhangjie🦀 21_trace_old_threads(master) $ ./21_trace_old_threads 12368
===step1===: check target process existed or not

===step2===: enumerate created threads by reading /proc
threads: [12368 12369 12527 12599 12661 12725 12798 12864 12934 13004 13075]    <= created thread IDs

===step3===: supposing running `dlv> thread <n>` here
12369
process 12369 attach succ                                                       <= prompt user input and attach thread
process 12369 stopped
tracee stopped at 7f06c29cf098

===step3===: supposing running `dlv> thread <n>` here
12527
switch from thread 12369 thread 12527
process 12527 attach succ                                                       <= prompt user input and switch thread
process 12527 stopped
tracee stopped at 7f06c29cf098

===step3===: supposing running `dlv> thread <n>` here
```

3. Above, we input two thread IDs, the first one was 12369, and the second one was 12527. Let's see how the thread states changed during these two inputs.

Initially, without input, the thread states were all S, indicating Sleep, because the threads were continuously doing `while(1) {sleep(1);}`, which is understandable.

```bash
$ top -H -p 12368

top - 00:54:17 up 8 days,  2:10,  2 users,  load average: 0.02, 0.06, 0.08
Threads:   7 total,   0 running,   7 sleeping,   0 stopped,   0 zombie
%Cpu(s):  0.1 us,  0.1 sy,  0.0 ni, 99.8 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st
MiB Mem :  31964.6 total,  26011.4 free,   4052.5 used,   1900.7 buff/cache
MiB Swap:   8192.0 total,   8192.0 free,      0.0 used.  27333.2 avail Mem

  PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND
12368 zhangjie  20   0   55804    888    800 S   0.0   0.0   0:00.00 fork_noquit
12369 zhangjie  20   0   55804    888    800 S   0.0   0.0   0:00.00 fork_noquit
12527 zhangjie  20   0   55804    888    800 S   0.0   0.0   0:00.00 fork_noquit
12599 zhangjie  20   0   55804    888    800 S   0.0   0.0   0:00.00 fork_noquit
12661 zhangjie  20   0   55804    888    800 S   0.0   0.0   0:00.00 fork_noquit
12725 zhangjie  20   0   55804    888    800 S   0.0   0.0   0:00.00 fork_noquit
12798 zhangjie  20   0   55804    888    800 S   0.0   0.0   0:00.00 fork_noquit
...
```

After we input 12369, the state of thread 12369 changed from S to t, indicating that the thread is now being debugged by the debugger (traced state).

```bash
12369 zhangjie  20   0   88588    888    800 t   0.0   0.0   0:00.00 fork_noquit
```

After we input 12527, the debugging behavior switched from tracking thread 12369 to tracking 12527. We saw that thread 12369 switched back from t to S, and 12527 switched from S to t.

```bash
12369 zhangjie  20   0   88588    888    800 S   0.0   0.0   0:00.00 fork_noquit
12527 zhangjie  20   0   88588    888    800 t   0.0   0.0   0:00.00 fork_noquit
```

OK, press Ctrl+C to kill the `./21_trace_old_threads` process, and then we continue to observe the thread states. They will automatically change from t to S, because the kernel is responsible for cleanup, i.e., resuming all tracees after the tracer exits.

### Further Discussion

When debugging multi-threaded programs, you might only track one thread or track multiple threads simultaneously. The final implementation form depends on the debugger's interaction design. For example, command-line debuggers often tend to track one thread due to interface interaction reasons, but some graphical IDEs might prefer to provide the ability to track multiple threads simultaneously (I often did this when debugging Java multi-threaded programs with Eclipse). We demonstrated how to implement this capability here, and readers should be able to implement tracking multiple threads simultaneously on their own.
