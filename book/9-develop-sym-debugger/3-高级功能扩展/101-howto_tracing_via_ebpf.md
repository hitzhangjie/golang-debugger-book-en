## Extended Reading: Breakpoint-based vs. eBPF-based Tracing

In program debugging and performance analysis, tracing is a very important technique. Currently there are two main implementation approaches: breakpoint-based and eBPF-based. Let's look at the characteristics of these two approaches in detail.

### Comparison of Two Tracing Approaches 

#### Breakpoint-based Tracing

Breakpoint tracing is a traditional tracing method with the following main characteristics:

- Implementation principle: Set software breakpoints (int3 instruction) at target function entry points, when program execution hits the breakpoint it triggers a trap exception which is caught and handled by the debugger
- Advantages:
  - Simple implementation, no kernel support needed
  - Can obtain complete context information (registers, call stack etc.)
  - Supports any user space program
- Disadvantages:
  - High performance overhead, each breakpoint causes process to pause
  - Does not support kernel function tracing
  - Intrusive to program execution

#### eBPF-based Tracing

eBPF tracing is an emerging tracing technology with the following main characteristics:

- Implementation principle: Uses kernel eBPF mechanism to inject tracing programs into kernel, data collection is done directly in kernel space
- Advantages:
  - Low performance overhead, no process pausing needed
  - Can trace both kernel and user space functions
  - Almost no intrusion to program execution
- Disadvantages:
  - Requires newer kernel version support
  - Relatively complex implementation
  - Limited by eBPF security restrictions

Due to performance considerations, when using eBPF-based tracing to print function parameters, usually only direct function parameters are obtained without dereferencing pointers in function parameters, because this involves ptrace-related memory read operations which must be done when memory addresses are valid. The most reliable approach is like debuggers requiring the target program to be in TRACED and Stopped state, since heap and stack memory changes dynamically. However, this approach will significantly impact target program performance.

See also the discussion:

- [go-delve/delve/issues/3586: Can dlv trace print the value of the arguments passed to a function?
  ](https://github.com/go-delve/delve/issues/3586#issuecomment-2911771133)

### eBPF Tracing Implementation

The basic implementation steps for eBPF tracing are as follows:

1. Write eBPF program
   - Define events to trace (kprobe/uprobe)
   - Write event handling logic
   - Define data storage structure (map)

2. Load eBPF program
   - Compile eBPF program
   - Load into kernel via bpf system call
   - Attach program to specified trace points

3. Data collection and processing
   - eBPF program executes in kernel, collecting data
   - Share data with user space program via map
   - User space program reads and processes data

4. Result presentation
   - Real-time display of trace data
   - Statistical analysis
   - Visualization

Through eBPF tracing, we can implement powerful tracing functionality with extremely low overhead, making it the preferred technology for modern performance analysis and monitoring tools.

### Go Program Tracing Cases

#### Challenges Faced

Due to Go program's special GMP scheduling, each M may execute multiple Gs. If M first executes G1 hitting function fn's entry, then switches to execute G2 also hitting function fn's entry and successfully completes hitting fn's exit. At this time from M's perspective, the uprobe hit sequence is: fn entry -> fn entry -> fn exit, but which G hit fn's exit - was it G1 or G2?

This is a problem. Although there are many eBPF-based tracing tools, they are more focused on thread-based programming languages like C/C++. They don't understand Go's runtime scheduling, so using tools like bpftrace and utrace to trace Go programs will result in confused statistics.

The correct solution is to first understand Go Runtime's GMP scheduling, then get `m.tls.g.goid` from current thread's local storage, using goid as the tracing object. The above scenario can then be broken down into:

- goroutine-1(goid1) event sequence: hit fn entry
- goroutine-2(goid2) event sequence: hit fn entry -> hit fn exit

This way tracing information can be printed from goroutine's perspective rather than thread's perspective.

#### Existing Cases

Currently the main tools that have successfully implemented eBPF-based tracing for Go programs are:

- github.com/go-delve/delve, dlv trace
- https://github.com/jschwinger233/gofuncgraph  
- github.com/hitzhangjie/go-ftrace

Among them, go-ftrace is forked from gofuncgraph which I studied, modified and optimized, and wrote related examples and several detailed articles about it. Due to length limitations, tinydbg does not retain go-delve/delve's ebpf-based tracing implementation. If you're interested, you can refer to the following two articles before studying the source code:

1. [Observing Go Function Calls: go-ftrace](https://www.hitzhangjie.pro/blog/2023-09-25-%E8%A7%82%E6%B5%8Bgo%E5%87%BD%E6%95%B0%E8%B0%83%E7%94%A8go-ftrace/)
2. [Observing Go Function Calls: go-ftrace Design Implementation](https://www.hitzhangjie.pro/blog/2023-12-12-%E8%A7%82%E6%B5%8Bgo%E5%87%BD%E6%95%B0%E8%B0%83%E7%94%A8go-ftrace%E8%AE%BE%E8%AE%A1%E5%AE%9E%E7%8E%B0/)

### Article Summary

This article introduced how to implement program tracing using eBPF technology, explaining in detail the basic flow of eBPF tracing including writing eBPF programs, loading into kernel, data collection processing and result presentation. It specifically pointed out the special challenges faced when tracing Go programs - traditional thread-based tracing approaches don't work due to Go's GMP scheduling model. The article analyzed the essence of this problem and introduced the correct solution: achieving accurate function call tracing by obtaining goroutine ID. It also introduced several open source tools that successfully implemented eBPF tracing for Go programs, providing readers with references for further learning and practice.
