# go runtime: Go Program Startup Process

## Overview of Go Program Startup Process

Let's examine the startup process of a Go program using the following source code as an example:

**file: main.go**

```go
package main

import "fmt"

func main() {
	fmt.Println("vim-go")
}
```

Run dlv for debugging and execute the program until main.main:

```
$ dlv debug main.go
Type 'help' for list of commands.
(dlv) b main.main
Breakpoint 1 set at 0x10d0faf for main.main() ./main.go:5
(dlv) c
> main.main() ./main.go:5 (hits goroutine(1):1 total:1) (PC: 0x10d0faf)
     1:	package main
     2:	
     3:	import "fmt"
     4:	
=>   5:	func main() {
     6:		fmt.Println("vim-go")
     7:	}
(dlv) 
```

Let's look at the call stack:

```bash
(dlv) bt
0  0x00000000010d0faf in main.main
   at ./main.go:5
1  0x000000000103aacf in runtime.main
   at /usr/local/go/src/runtime/proc.go:204
2  0x000000000106d021 in runtime.goexit
   at /usr/local/go/src/runtime/asm_amd64.s:1374
(dlv) 
```

From this, we can see that the Go program starts up in the following sequence:

1. asm_amd64.s:1374 runtime·goexit:runtime·goexit1(SB)

2. runtime/proc.go:204 runtime.main:fn()
   Here, fn is the main.main from our test source program

3. Now PC is stopped at main.main, waiting for us to continue debugging.

## Pre-Startup Initialization

Here we discuss the pre-startup initialization, which refers to the operations before our entry function main.main is executed. Understanding this part will help establish a global understanding of Go and strengthen our knowledge of implementing Go debuggers.

### Go Process Instantiation

When we type `./prog` in the shell, the operating system instantiates an instance of the prog program, and the process starts. What happens during this process?

- First, the shell forks a child process (let's call it child shell);
- The child shell then replaces the process's code, data, etc., by executing execvp;
- Once everything is ready, the operating system hands the prepared process state to the scheduler for execution;

Let's assume the current scheduler has selected our process and see what logic the Go process executes from startup.

When compiling C programs, we know that a source program is first compiled into *.o files, then linked with system-provided shared libraries and startup code to form the final executable. Linking can be done through internal linkage (static linking) or external linkage (dynamic linking).

Go programs are similar to C programs, with different linking methods. Refer to the `-linkmode` option description in `go tool link` for details. Typically, if there's no cgo, Go build by default produces internal linkage, which is why the size is slightly larger. This can be confirmed by checking the shared library dependencies with the system tool `ldd <prog>`, which will show an error `not dynamic executable`.

### Go Process Startup Code

After a Go program's process starts executing, its first instructions are the startup code, as shown below:

**file: asm_amd64.s**

```asm
// _rt0_amd64 is common startup code for most amd64 systems when using
// internal linking. This is the entry point for the program from the
// kernel for an ordinary -buildmode=exe program. The stack holds the
// number of arguments and the C-style argv.
TEXT _rt0_amd64(SB),NOSPLIT,$-8
	MOVQ	0(SP), DI	// argc
	LEAQ	8(SP), SI	// argv
	JMP	runtime·rt0_go(SB)
	
// main is common startup code for most amd64 systems when using
// external linking. The C startup code will call the symbol "main"
// passing argc and argv in the usual C ABI registers DI and SI.
TEXT main(SB),NOSPLIT,$-8
	JMP	runtime·rt0_go(SB)
```

The above is the startup code used when building Go programs with internal and external linkage respectively. When a Go process starts, it will first execute these instructions. The first one passes the process arguments argc and argv, then jumps to `runtime.rt0_go(SB)` for execution. The second one indicates that the C startup code will be responsible for passing argc and argv before calling main, then `runtime.rt0_go(SB)`.

Let's not discuss the impact of linkmode on startup code further and directly look at `runtime.rt0_go(SB)`.

### `runtime.rt0_go(SB)`

The assembly code here is quite lengthy, so we'll omit most of it and only keep the important steps.

```asm
TEXT runtime·rt0_go(SB),NOSPLIT,$0
	// copy arguments forward on an even stack
	...

	// create istack out of the given (operating system) stack.
	...

	// find out information about the processor we're on
	...

	// others
	...
ok:
	// set the per-goroutine and per-mach "registers"
	...

	// save m->g0 = g0
	...
	// save m0 to g0->m
	...


	// copy argc
	...
	// copy argv
	...
	CALL	runtime·args(SB)
	CALL	runtime·osinit(SB)
	CALL	runtime·schedinit(SB)

	// create a new goroutine to start program
	MOVQ	$runtime·mainPC(SB), AX		// entry
	PUSHQ	AX
	PUSHQ	$0			// arg size
	CALL	runtime·newproc(SB)
	POPQ	AX
	POPQ	AX

	// start this M
	CALL	runtime·mstart(SB)

	CALL	runtime·abort(SB)	// mstart should never return
	RET

	// Prevent dead-code elimination of debugCallV1, which is
	// intended to be called by debuggers.
	MOVQ	$runtime·debugCallV1(SB), AX
	RET
```

We can see that after completing some initialization in the first half, it also performs these operations:

1. copy argc, copy argv
2. call runtime·args(SB), call runtime·osinit(SB), call runtime·schedinit(SB)
3. create a new goroutine to start program
   1. push entry: $runtime·mainPC(SB)
   2. push arg size: $0
   3. call runtime·newproc(SB)
4. call runtime·mstart(SB)

These steps are the key parts of Go program startup that we're interested in. Let's look at them one by one.

> Note: To read Go assembly, you need to first read some basic knowledge. You can refer to [a quick guide to go's assembler](https://golang.org/doc/asm).
>
> - `FP`: Frame pointer: arguments and locals.
> - `PC`: Program counter: jumps and branches.
> - `SB`: Static base pointer: global symbols.
> - `SP`: Stack pointer: top of stack.
>
> All user-defined symbols are written as offsets to the pseudo-registers `FP` (arguments and locals) and `SB` (globals).
>
> The `SB` pseudo-register can be thought of as the origin of memory, so the symbol `foo(SB)` is the name `foo` as an address in memory. This form is used to name global functions and data. Adding `<>` to the name, as in `foo<>(SB)`, makes the name visible only in the current source file, like a top-level `static` declaration in a C file. Adding an offset to the name refers to that offset from the symbol's address, so `foo+4(SB)` is four bytes past the start of `foo`.

#### call runtime·args(SB)

Refers to the args function in the runtime package, which sets up argc, argv, and other parameters.

**file: runtime/runtime1.go**

```go
func args(c int32, v **byte) {
	argc = c
	argv = v
	sysargs(c, v)
}
```

#### runtime·osinit(SB)

Refers to the osinit function in the runtime package, which handles system settings. We won't focus on this for now.

**file: runtime/os_linux.go**

```go
func osinit() {
	ncpu = getproccount()
	physHugePageSize = getHugePageSize()
	osArchInit()
}
```

#### call runtime·schedinit(SB)

Refers to the schedinit function in the runtime package, which prepares for scheduling execution.

```go
// The bootstrap sequence is:
//
//	call osinit
//	call schedinit
//	make & queue new G
//	call runtime·mstart
//
// The new G calls runtime·main.
func schedinit() {
	// lockInit is a no-op on Linux
    ...

	// raceinit must be the first call to race detector.
	// In particular, it must be done before mallocinit below calls racemapshadow.
    
    // @see https://github.com/golang/go/blob/master/src/runtime/HACKING.md
    // Reference for getg() explanation: This should be running on the system stack, 
    // the returned _g_ should be the g0 of the current M
	_g_ := getg()
	if raceenabled {
		_g_.racectx, raceprocctx0 = raceinit()
	}

	sched.maxmcount = 10000

	moduledataverify()
	stackinit()
	mallocinit()
	fastrandinit() // must run before mcommoninit
	mcommoninit(_g_.m, -1)
	cpuinit()       // must run before alginit
	alginit()       // maps must not be used before this call
	modulesinit()   // provides activeModules
	typelinksinit() // uses maps, activeModules
	itabsinit()     // uses activeModules

	msigsave(_g_.m)
	initSigmask = _g_.m.sigmask

	goargs()
	goenvs()
	parsedebugvars()
	gcinit()

	lock(&sched.lock)
	sched.lastpoll = uint64(nanotime())
	procs := ncpu
	if n, ok := atoi32(gogetenv("GOMAXPROCS")); ok && n > 0 {
		procs = n
	}
	procresize(procs)
	...
	unlock(&sched.lock)
	...
}
```

#### Starting runtime.main & main.main

After all the initialization work above, let's look at the most direct part of runtime.main startup:

```asm
	// create a new goroutine to start program
	MOVQ	$runtime·mainPC(SB), AX		// entry
	PUSHQ	AX
	PUSHQ	$0			// arg size
	CALL	runtime·newproc(SB)
	POPQ	AX
	POPQ	AX

	// start this M
	CALL	runtime·mstart(SB)
```

Here, it first gets the address of the symbol `$runtime.mainPC(SB)` and puts it in AX. This is actually the entry address of the runtime.main function. Then it pushes the function call parameter argsize 0, because this function has no parameters.

```asm
DATA	runtime·mainPC+0(SB)/8,$runtime·main(SB)
GLOBL	runtime·mainPC(SB),RODATA,$8
```

runtime·main(SB) corresponds to the runtime.main function:

```go
// The main goroutine.
func main() {
	g := getg()

	// Racectx of m0->g0 is used only as the parent of the main goroutine.
	// It must not be used for anything else.
	g.m.g0.racectx = 0

	// Adjust goroutine stack size, maximum 1GB for 64-bit, 250M for 32-bit
    ...

	// Allow newproc to start new Ms.
	mainStarted = true

	if GOARCH != "wasm" { // no threads on wasm yet, so no sysmon
		systemstack(func() {
            // Create new m and execute sysmon, -1 means no pre-specified m id
			newm(sysmon, nil, -1)
		})
	}

    // Note, we're now executing the main goroutine, and the current thread is the main thread.
    // Calling this method will bind the main goroutine to the main thread,
    // meaning we can be certain that main.main will always run on the main thread, unless unbound later
	lockOSThread()
    ...

    // Here we execute the initialization logic of the runtime package:
    // - Each package has some imported dependencies, and these imported packages need initialization logic;
    // - Each package's internal func init() needs to be called after its dependencies are initialized;
	doInit(&runtime_inittask) // must be before defer
	...

	// Defer unlock so that runtime.Goexit during init does the unlock too.
	needUnlock := true
	defer func() {
		if needUnlock {
			unlockOSThread()
		}
	}()
	...

    // Before calling user-written program code, enable gc. Note that this doesn't create a separate thread for gc, maybe later
	gcenable()

	main_init_done = make(chan bool)
	if iscgo {
		...
		// Start the template thread in case we enter Go from
		// a C-created thread and need to create a new thread.
		startTemplateThread()
		cgocall(_cgo_notify_runtime_init_done, nil)
	}

    // Initialize main package, including its imported dependencies and func init() in the main package
	doInit(&main_inittask)
	// main package initialization complete
	close(main_init_done)

	needUnlock = false
    
    // Note, here we unbind the current goroutine from the thread again. It seems the Go designers
    // only wanted to perform certain initialization actions on the main thread, and didn't want to
    // treat the main goroutine specially afterward. The main goroutine, like other goroutines,
    // can be scheduled by the scheduler to run on other threads
	unlockOSThread()

    // If compiled as a static library or dynamic library, even though there's a main function, it can't be executed
	if isarchive || islibrary {
		return
	}
    
    // Note, calling main_main is actually main.main, see the go directive definition above:
    // //go:linkname main_main main.main, the call to main_main will transfer to main.main
    //
	// Since we've already unbound the main goroutine from the main thread, the only thing we can be certain of
    // is that the main.main method is executed on the main goroutine, but not necessarily on the main thread
	fn := main_main 
	fn()
	if raceenabled {
		racefini()
	}

	// When main.main ends, it means the entire program is ready to end.
    // If a panic occurs, it will notify all goroutines to print their stacks
	if atomic.Load(&runningPanicDefers) != 0 {
		// Running deferred functions should not take long.
		for c := 0; c < 1000; c++ {
			if atomic.Load(&runningPanicDefers) == 0 {
				break
			}
			Gosched()
		}
	}
	if atomic.Load(&panicking) != 0 {
		gopark(nil, nil, waitReasonPanicWait, traceEvGoStop, 1)
	}

	exit(0)
	...
}
```

Here we've analyzed the startup process of a Go program and can draw a very important conclusion:

> The main.main method is executed by the main goroutine, but the main goroutine is not necessarily scheduled by the main thread.
>
> There is no default binding relationship between the main goroutine and the main thread!

Understanding this is very important, as it will help us understand why the main method doesn't stop when using `godbg attach <pid>`.

