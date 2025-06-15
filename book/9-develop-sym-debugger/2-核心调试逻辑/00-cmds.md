## Core Debugging Commands

In Chapter 5 "Debugger Overview", we analyzed the functional requirements, non-functional requirements, and general implementation approach of the debugger. Chapter 6 followed with the design and implementation of the instruction-level debugger. Chapter 7 introduced the ELF file format, compiler, linker, and loader principles closely related to debugger development, as well as the generation of debugging information. Chapter 8 specifically covered how debugging information describes source program data, instructions, and process runtime views. Section 9.1 introduced the overall architecture of modern debuggers, and this section will focus on the implementation of each debugging feature.

Before we begin, let's reiterate the functional requirements, non-functional requirements, and general technical approach. Due to space and time constraints, we cannot implement and introduce all features in detail. Therefore, we will specifically state the extent to which each feature will be implemented. Since our demo tinydbg is derived from `go-delve/delve` through modification and pruning, we can clearly indicate the extent of each feature and its differences from delve for better understanding.

### Support for Multiple Debugging Targets

| Command         | Description                    | Target Type     | Implemented | Delve Support |
| --------------- | ------------------------------ | --------------- | ----------- | ------------- |
| godbg attach    | Debug a running process        | process         | Y           | Y             |
| godbg exec      | Launch and debug a Go executable| executable      | Y           | Y             |
| godbg debug     | Debug current Go main module   | go main package | Y           | Y             |
| godbg test      | Debug test functions in current Go package | go test package | N | Y |
| godbg core      | Launch and debug a coredump    | coredump        | Y           | Y             |

> Note: Why not support `godbg test`?
>
> Go has a native unit testing framework, and `go test` should be familiar to everyone. For debugging test packages, we can do this: `go test -c -ldflags 'all=-N -l'` and then `godbg exec ./xxxx.test`. However, it would be more convenient to have a single command `godbg test` to handle the build and run operations.
>
> Nevertheless, this doesn't involve incremental core debugging logic - it's just an optimization for compilation, building, and test execution. To make tinydbg more concise and save space in this introduction, we removed the original delve implementation logic.

### Support for Multiple Debugging Modes

| Command                                | Mode                                                    | Implemented | Delve Support        |
| -------------------------------------- | ------------------------------------------------------- | ----------- | -------------------- |
| godbg debug/exec/attach                | Local debugging mode                                    | Y           | Y                    |
| godbg debug/exec/attach --headless     | Start debug server, allow remote client connection (JSON-RPC) | Y | Y |
| godbg connect                          | Start debug client, connect to remote debug server      | Y           | Y                    |
| godbg dap                              | Start debug server with DAP protocol support for VSCode integration | N | Y |
| godbg tracepoint                       | Track program execution functions                       | bp-based    | bp-based + ebpf-based|
| godbg <...> --disable-aslr             | Disable ASLR address randomization                      | N           | Y                    |
| godbg --backend=gdb/lldb/rr            | Use other debugger implementations instead of native    | N           | Y                    |

> Note: Let's explain the pruning logic here:
>
> 1. Why remove `godbg dap` support?
>    - It also starts the debugger server in --headless mode, just with DAP protocol encoding/decoding instead of JSON-RPC;
>    - Although DAP is a popular protocol for IDE integration with debuggers, it's not core debugger logic - understanding its purpose is sufficient;
>
> 2. Why remove ebpf-based implementation of `godbg tracepoint`?
>    - The ebpf-based tracing details are extensive, and explaining Linux ebpf subsystem and ebpf programming would take too much space;
>    - Breakpoint-based tracing is more concise in content and can achieve tracing capabilities, albeit with poorer performance;
>    - We mention the ebpf-based tracing tool [go-ftrace] in the extended reading section for readers to learn more;
>
> 3. Why remove ASLR disable support?
>    - We previously introduced what ASLR is;
>    - Understanding its impact on program loading and debugging (especially for saving sessions and automated debugging) is sufficient;
>
> 4. Why remove `godbg --backend` implementation?
>    - Supporting different backend implementations involves gdbserial support and integration with gdb and mozilla rr, which is code-intensive and would take too much space to explain;
>    - Supporting lldb is similar to supporting gdb, and since we've already pruned the dlv project to only support linux/amd64, keeping macOS lldb support makes no sense;
>    - Mastering the native backend implementation under linux/amd64 is the focus of this book - we'll cover how to extend this in the extended reading section;
>
> Through these selective prunings, we've retained the core design and implementation of the symbolic debugger while keeping the content manageable for readers.

### Support for Common Debugging Operations

#### Running the program

| Command             | Alias | Description                                                | Implemented | Delve Support |
| ------------------- | ----- | ---------------------------------------------------------- | ----------- | ------------- |
| call                | -     | Resumes process, injecting a function call                 | Y           | Y             |
| continue            | c     | Run until breakpoint or program termination                | Y           | Y             |
| next                | n     | Step over to next source line                              | Y           | Y             |
| restart             | r     | Restart process                                            | Y           | Y             |
| step                | s     | Single step through program                                | Y           | Y             |
| step-instruction    | si    | Single step a single cpu instruction                       | Y           | Y             |
| stepout             | so    | Step out of the current function                           | Y           | Y             |
| rewind              |       | Run backwards until breakpoint or start of recorded history| N           | Y             |
| checkpoints         |       | Print out info for existing checkpoints                    | N           | Y             |
| rev                 |       | Similar to gdb rnext, rstep... changes next/step/continue direction | N | Y |

> Note: Why not support rewind, checkpoints, rev operations?
>
> Mozilla rr enables stable replay of debugging sessions and deterministic debugging after recording, making it easier to locate the source of failures. The reasons for removing it are:
>
> 1) While building deterministic debugging on this foundation is beautiful, it makes the debugger itself very complex;
>    - Communication with rr through gdbserial;
>    - Interaction with rr to change program execution direction when needed;
>    - Code implementation requires extensive forward and reverse execution control logic;
> 2) rev operations that change program execution direction (affecting next/step command direction) and the reverse version of continue (rewind) depend on rr backend;
> 3) checkpoints functionality also depends on rr;
>
> We'll introduce mozilla rr's recording and replay principles and how to integrate it in the extended reading section, but we won't retain this implementation logic in demo tinydbg.

#### Manipulating breakpoints

| Command        | Alias | Description                                     | Implemented | Delve Support |
| -------------- | ----- | ----------------------------------------------- | ----------- | ------------- |
| break          | b     | Sets a breakpoint                               | Y           | Y             |
| breakpoints    | bp    | Print out info for active breakpoints           | Y           | Y             |
| clear          |       | Deletes breakpoint                              | Y           | Y             |
| clearall       |       | Deletes multiple breakpoints                    | Y           | Y             |
| condition      | cond  | Set breakpoint condition                        | Y           | Y             |
| on             |       | Executes a command when a breakpoint is hit     | Y           | Y             |
| toggle         |       | Toggles on or off a breakpoint                  | Y           | Y             |
| trace          | t     | Set tracepoint                                  | Y           | Y             |

These breakpoint-related operations are commonly used core debugging commands, and we'll retain and introduce their implementations.

#### Viewing program variables and memory

| Command       | Alias | Description                                     | Implemented | Delve Support |
| ------------- | ----- | ----------------------------------------------- | ----------- | ------------- |
| args          |       | Print function arguments                        | Y           | Y             |
| display       |       | Disassembler                                    | Y           | Y             |
| examinemem    | x     | Examine raw memory at the given address         | Y           | Y             |
| locals        |       | Print local variables                           | Y           | Y             |
| print         | p     | Evaluate an expression                          | Y           | Y             |
| regs          |       | Print contents of CPU registers                 | Y           | Y             |
| set           |       | Changes the value of a variable                 | Y           | Y             |
| vars          |       | Print package variables                         | Y           | Y             |
| whatis        |       | Prints type of an expression                    | Y           | Y             |
| ptype         |       | Print type details, including fields and methods| Y           | N             |

These operations for reading/writing registers, reading/writing memory, viewing arguments, viewing local variables, printing variables, viewing expression types, and viewing type details are commonly used core debugging commands. We'll retain and introduce their implementations. Notably, gdb's ptype command can print detailed type information for a variable. Delve's similar operation is whatis, but whatis can only print field information, not the method set defined on the type, which isn't very convenient.

Therefore, we want to support a new debugging command ptype, and in this process, we can also let readers learn to use DWARF to extend debugger functionality.

#### Listing and switching between threads and goroutines

| Command       | Alias | Description                                | Implemented | Delve Support |
| ------------- | ----- | ------------------------------------------ | ----------- | ------------- |
| goroutine     | gr    | Shows or changes current goroutine         | Y           | Y             |
| goroutines    | grs   | List program goroutines                    | Y           | Y             |
| thread        | tr    | Switch to the specified thread             | Y           | Y             |
| threads       |       | Print out info for every traced thread     | Y           | Y             |

Different programming languages provide different concurrency programming interfaces. For example, C, C++, Java, Rust provide thread-oriented concurrency programming interfaces, while Go provides goroutine-oriented concurrency programming interfaces. However, software debugging on operating systems supporting protected mode essentially leverages kernel-provided capabilities. For example, under Linux, it uses ptrace operations to control process instruction and data read/write, process scheduling control, state acquisition, etc. Go is special in that it implements a goroutine-oriented scheduling system, commonly known as GMP scheduling. The task queue (G to be scheduled) on P (virtual processor resource) is ultimately executed by M. G's scheduling is controlled by Go runtime GMP scheduler, while thread M's scheduling is controlled by kernel scheduler. The debugger influences kernel scheduling of target debug threads through ptrace system calls to achieve debugging.

Therefore, for Go debuggers, to have more flexible control, we need to know which threads (`threads`) and which goroutines (`goroutines`) exist, and implement thread switching (`thread n`) and goroutine switching (`goroutine m`) based on this.

#### Viewing the call stack and selecting frames

| Command     | Alias | Description                                                         | Implemented | Delve Support |
| ----------- | ----- | ------------------------------------------------------------------- | ----------- | ------------- |
| stack       | bt    | Print stack trace                                                   | Y           | Y             |
| frame       |       | Set the current frame, or execute command on a different frame      | Y           | Y             |
| up          |       | Move the current frame up                                           | Y           | Y             |
| down        |       | Move the current frame down                                         | Y           | Y             |
| deferred    |       | Executes command in the context of a deferred call                  | Y           | Y             |

These are operations related to the call stack. bt views the call stack, frame selects a stack frame to view parameters and variable states within that frame, up and down facilitate movement in the call stack, essentially the same as frame operations. deferred is special, providing specific support for Go's defer functions. A function can have multiple defer function calls, and `defer <n>` can conveniently add breakpoints to the nth defer function and execute specific commands when reaching that point, such as printing locals.

These are commonly used core debugging commands for Go language, and we'll retain and introduce them all.

#### Source Code commands

| Command        | Alias    | Description                          | Implemented | Delve Support |
| -------------- | -------- | ------------------------------------ | ----------- | ------------- |
| list           | ls / l   | Show source code                     | Y           | Y             |
| disassemble    | disass   | Disassembler                         | Y           | Y             |
| types          |          | Print list of types                  | Y           | Y             |
| funcs          |          | Print list of functions              | Y           | Y             |
| libraries      |          | List loaded dynamic libraries        | Y           | Y             |

These are operations related to source code, such as viewing source code, disassembling source code, viewing type lists, function lists, and shared library lists that the source code depends on. Among these, list and disassemble are commonly used operations and are our focus for introduction. types and funcs were already introduced when we demonstrated what can be obtained through DWARF.

#### Automatically Debugging

| Command    | Alias | Description                                                | Implemented               | Delve Support                                 |
| ---------- | ----- | ---------------------------------------------------------- | ------------------------- | --------------------------------------------- |
| source     |       | Executes a file containing a list of delve commands        | script of dlv commands    | script of dlv commands + script of starlark   |
| sources    |       | Print list of source files                                 | Y                         | Y                                             |

In automated debugging, we write some debugging commands and execute them in the debugging session using source. This isn't used much, but it can be useful in specific scenarios, so we'll briefly introduce it.

> Note: Why remove starlark script support from source?
>
> 1) Automated debugging can be performed using regular scripts containing dlv commands, which already provides some automated testing capabilities;
> 2) However, the method in 1) is not as flexible as starlark language scripts, where starlark binding code can directly call debugger's built-in debugging operations;
> 3) Combined with starlark's programming capabilities for processing debugging command input and output, more automated debugging possibilities can be explored;
>
> We'll introduce how to integrate starlark in Go programs, but since this isn't a particularly core debugging capability, in demo tinydbg, we've kept two branches:
>
> - tinydbg branch: Removed linux/amd64 unrelated code, removed backend gdb, lldb, mozilla rr code, removed record&replay, reverse debugging code, removed dap code, etc., but retained starlark implementation and provided a starlark automated testing demo `starlark_demo` in the examples directory. If you're interested, you can run the related tests;
> - tinydbg_minimal branch: More aggressively pruned and refactored based on the tinydbg branch's current state, making its functionality implementation more aligned with what we'll introduce in this chapter... everything simplified, including removing starlark script support;
>
> You can choose either branch for learning and testing as needed.

#### Other commands

| Command    | Alias     | Description                                               | Implemented | Delve Support |
| ---------- | --------- | --------------------------------------------------------- | ----------- | ------------- |
| config     |           | Changes configuration parameters                          | Y           | Y             |
| dump       |           | Creates a core dump from the current process state        | Y           | Y             |
| edit       | ed        | Open where you are in $DELVE_EDITOR or $EDITOR            | Y           | Y             |
| rebuild    | -         | Rebuild the target executable and restarts it             | Y           | Y             |
| exit       | quit / q  | Exit the debugger                                         | Y           | Y             |
| help       | h         | Prints the help message                                   | Y           | Y             |

These debugging commands involve custom configuration, core dump generation, viewing or modifying source code, recompiling after modifications, and viewing help and exit operations. Here, dump is what we'll introduce - it's closely related to the core command, one for generation and one for reading and debugging. edit and rebuild are highlights, solving the inconvenience of switching editor windows to edit and modify during debugging. exit and help are more conventional.

The above debugging command capabilities roughly represent the complete set of features that a modern Go symbolic debugger should support, meeting engineering application requirements. If you've used go-delve/delve, you'll notice that the above features are basically all go-delve/delve's debugging commands? That's right - I've listed go-delve/delve's debugging commands here, with an additional ptype command inspired by gdb for printing type details.

> The original intention of writing this book was to explain how to develop a symbolic debugger, not to write a new debugger. Considering factors such as debugging feature completeness, coverage of related knowledge, engineering complexity, and limited personal time, I ultimately adopted a very "open source" approach, borrowing and pruning code from go-delve/delve, retaining core functionality, removing linux/amd64 unrelated architecture extension code, and moving rr (record and play) and dap (debugger adapter protocol) to additional reading chapters (possibly in appendices or extended reading) for introduction.
>
> This way, the author can ensure the first draft of this book is completed in 2022, to meet readers in electronic book form as soon as possible (paper version will also be considered).

### What else needs attention

Making a product requires focusing on user experience, and making a debugger is no different - we need to consider how to make it convenient for developers to use and debug smoothly from a developer's perspective. We've organized so many debugging commands that need to be supported, which is a reflection of focusing on product experience.

We provide many debugging commands, which are functionally sufficient. However, for a command-line-based debugger, richer debugging commands might feel more like a burden, as implementing command input is not an easy task.

We need to pay special attention to the following points:

- Simplify command-line input, especially for cases requiring multiple consecutive inputs;
- Make it easy to view command help, with reasonable grouping of related commands and concise, useful help information;
- Make it easy to observe multiple variables, such as during execution observation, breakpoint hit observation, or when executing a defer function;
- Ensure robustness - during debugging, debugger crashes, process crashes, incompatible DWARF data, Go AST incompatibilities, etc., preventing smooth debugging completion, should be detected early and problems thrown to avoid wasting developers' precious time.

#### Debugger Usability

**1 Many debugging commands, need to reduce memory and usage costs**

- First, the debugger has many debugging commands, and memorizing these commands has a certain learning cost, and command-line-based debuggers have a steeper learning curve than GUI-based debuggers;
- Command-line-based debuggers need to consider debugging command input efficiency issues, such as inputting commands and their corresponding parameters. GUI debuggers can usually add a breakpoint at a source line very simply with a mouse click, but command-line-based debuggers require users to explicitly provide a source location, like "break main.go:15" or "break main.main";
- For the debugger's many debugging commands, we need to consider command auto-completion, parameter auto-completion, and if aliases are supported, that would be a good option. The debugger also needs to remember the last used debugging command for easy reuse, for example, frequent step-by-step execution command sequences <next, next, next> can be replaced by command sequences <next, enter, enter>, where the enter key defaults to using the last command, which is more convenient for users;
- Every command and command parameter should have clear help information, and users can easily view what command cmd does and what options it includes through `help cmd`.

**2 Command-line debugger, need to display multiple observation values simultaneously**

- Command-line-based debuggers have UI based on terminal text mode display, not graphical mode, which means they can't flexibly and conveniently display multiple types of information like GUI interfaces, such as simultaneously displaying source code, breakpoints, variables, registers, call stack information, etc.;
- However, the debugger also needs to provide similar capabilities, so users can observe multiple variables and register states after executing a debugging command (like next, step). And in this process, users shouldn't need manual operation. Also, the refresh action for multiple observation variables and register values should be quick, approaching the time taken for next and step execution.

#### Debugger Extensibility

**1 Command and option extension should have good, concise support**

- The debugger has multiple startup methods, corresponding to multiple startup commands, such as `godbg exec <prog>`, `godbg debug <module>`, `godbg attach <pid>`, `godbg core <coredump>`, each with different parameters. Additionally, the debugger has multiple interactive debugging commands, such as `break <locspec>`, `break <locspec> cond <expression>`, etc., each also with different parameters. How to manage these commands and their options in an extensible way needs careful consideration;
- Command options should follow GNU/POSIX option style as much as possible, which is more in line with everyone's usage habits, and options should support both long and short options when ambiguity can be eliminated, providing more convenience for development input;

**2 Debugger should satisfy personalized definitions to meet different debugging habits**

- Good products shape user habits, but better habits should only be known by users themselves - a configurable debugger is more appropriate, such as allowing users to customize command alias information, etc.;

**3 Cross-platform, support for different debugging backends, support for IDE integration**

- The debugger itself may need to consider future application scenarios, whether it has sufficient adaptability for use in various application scenarios, such as whether it can be used in GoLand, VSCode and other IDEs, or possible remote debugging scenarios, etc. These also place requirements on the debugger's software architecture design;
- Consider future expansion to darwin/windows and powerpc, i386 and other different systems and platforms - necessary abstraction design should be provided in software design, separating abstraction from implementation;
- Debugger implementation isn't omnipotent - there are scenarios where we need to rely on other debugger implementations to complete certain functions, possibly because our implementation doesn't support the system/platform where the program being debugged is located, or other debugger implementation methods are better. For example, Mozilla rr (record and replay) has complex implementation for recording and replay, and gdb, lldb, dlv's reverse debugging is basically built on rr. This requires the debugger to implement a front-end/back-end separated architecture, and the back-end part's interface and implementation should be separated, satisfying replaceability, such as easily switching from dlv to Mozilla rr;

#### Debugger Robustness

- The debugger itself depends on some operating system capability support, such as Linux ptrace system call support. The use of this system call has some constraints, such as ptrace_attach followed by tracee's subsequent ptrace requests must come from the same tracer. There are also some special cases with syscall.Wait system call on Linux platform... there are many such cases, and the debugger should consider these cases for compatibility handling;
- Go debugger also depends on some debugging information generated by go compilation toolchain. Different go versions' compiled products have differences in data type representation and signal handling. The debugger implementation should consider these cases for necessary handling, striving for robustness. For example, we can limit the currently supported go toolchain version, and if the compiled product's corresponding go version doesn't match, abandon debugging;

There are many non-functional requirements. We've described them from usability, to command management maintainability, to selection standardization, to how to expand to different operating systems, hardware platforms, debugger backend implementations, and its own robustness. Besides debugging functionality itself, these are also very important factors affecting whether a debugger can be accepted by everyone.

### Section Summary

This section actually provides a detailed analysis of the functional requirements and non-functional requirements for the upcoming Go symbolic debugger demo tinydbg - this is our goal. OK, let's move on to the design and implementation of these debugging commands, Let's Go!!!
