## Software Debugging Technology Panorama: Precise Matching of Tools and Scenarios

### Introduction

Software debugging is a crucial activity throughout the software lifecycle. Its target could be a process, a core dump file, a complex program with different optimization characteristics, a monolithic service, or a distributed system. **The essence of debugging is the combination of systematic cognition and scenario-specific tools**. When developers complain that "a certain tool is useless," it's often because they haven't encountered the complex scenarios that require that tool's features. This article will present a comprehensive view of modern software debugging through the analysis of core debugging technologies and their applicable scenarios.

### Core Debugging Technology Matrix

#### 1. Debugger

Debugger design and implementation is the main focus of this book, and readers should be quite familiar with it by now. A debugger is an interactive tool that observes target process states through mechanisms like breakpoint control, memory analysis, and stack tracing. Debuggers are very effective for real-time state analysis of single-process, multi-process, and multi-threaded applications. Modern debuggers like go-delve/delve even implement goroutine-level debugging capabilities. For operating system kernel debugging, kernel-level debuggers are generally needed, such as Linux kdb or Windows winDBG. For code optimized during compilation, debugging is possible with DWARF, such as for inline functions.

> As mentioned earlier, debuggers have evolved from a simple 3-layer architecture to a frontend-backend separated architecture to handle differences in software and hardware architectures. Some mainstream IDEs need standardized support at the debug protocol level, such as DAP (Debugger Adapter Protocol), to integrate with different debugger backends.
>
> Debugging single-process or a small number of processes is relatively simple, but debugging distributed systems in a microservices architecture is challenging.

#### 2. Logging System

Logging is also a very common debugging method. As long as you have the source code, whether it's a locally running command-line program or a remotely running service, you can add a few lines of code at suspicious locations, redeploy and run to observe and verify. While logging is widely applicable, it's not always efficient. For example, you might need to modify the source code multiple times, compile, build, and deploy to narrow down the problem scope. In enterprises with strict code delivery and artifact management, this process might require a series of reviews and CI/CD pipeline checks. For distributed systems, remote logging systems are generally needed, and TraceID is used to correlate complete transaction processing logs. For convenient retrieval, structured log parsing, storage, and retrieval capabilities might be needed, such as the ELK Stack.

> Logs are just continuously appended text - how do we extract valuable information from them?
>
> Before remote logging systems appeared, `tail -f <xyz.log> | grep` or `grep <xyz.log>` were the most common operations. If there were many logs, you'd also need `ls -rth` to check the last modification time to determine which file the logs were in. After remote logging systems emerged, we need to collect, clean, and parse logs, such as extracting traceid, loglevel, timestamp, event message, and other parameter information, and report them to remote logs. Remote logs build indexes based on these to facilitate retrieval.
>
> Besides the process-related issues mentioned above, remote logging systems have another inconvenience: when there's a large volume of logs, waiting for logs to be stored and become searchable usually has a minute-level delay, which can be very inconvenient for scenarios requiring efficient debugging.

#### 3. Metrics Monitoring

Monitoring metrics is a required course for software engineers. While newcomers might only add monitoring reports when errors occur, veterans will add monitoring for total requests, successful requests, and failed requests for each interface, as well as for key branches and exception branches in the processing logic. They'll also monitor overall processing time and time spent on key steps. Why? Because experienced developers understand the urgency of solving production issues and how to better locate problems. If metrics are added carefully, they can also serve as a basis for analyzing code execution paths, at least providing an overview of the system. Combined with code familiarity, it's easier to narrow down the problem scope.

> Metrics like CPU utilization and memory leak trend graphs help developers quickly identify CPU-intensive or memory-intensive code sections. Similarly, transaction processing time distribution can help identify specific processing steps. Business-side metrics are generally reported using framework-provided operations, while platform-side metrics monitoring usually comes from platform observability capabilities, such as network, file system, task scheduling, CPU, and memory conditions of machines (physical machines, virtual machines, containers). In recent years, eBPF has been particularly outstanding in this area.
>
> After narrowing down the problem scope using monitoring metrics, you still need to use source code and other means to further determine the root cause. Before determining the root cause, monitoring metrics are just symptoms.

#### 4. Tracing System

In the field of distributed systems under microservices architecture, tracking the complete process of transaction processing is a challenge. [Google dapper](https://static.googleusercontent.com/media/research.google.com/en//archive/papers/dapper-2010-1.pdf) details how to solve these challenges, such as which services are called in transaction processing, call order, respective time consumption, success or failure, request and response parameters, and related event information. After this paper was published, many open-source products like zipkin and jaeger emerged.

You can actually see similar network request tracing visualization information in Chrome Developer Tools' Timing Tab. The difference is that each span in dapper often shows microservice-level information, while the Timing Tab shows information for each key step, such as Queueing, Request Sent, Wait for response, and Content Download. go tool trace also borrowed from this idea, incorporating the entire go runtime execution into tracing analysis, and providing APIs for developers to create their own tracing of interest.

> Early opentracing often focused on the tracing domain, with less integration with metrics and logging. This meant that when you saw a span that took a long time, you might still not know the problem details without logging system support. Without associated metrics, you wouldn't know what monitoring points were triggered by a specific request.
>
> This was the limitation of early opentracing and opencensus. Now opentelemetry recognizes this and integrates logging, metrics, and tracing together, forming a new industry observability standard. [opentelemetry](https://opentelemetry.io/) can be implemented at the framework level or as a platform capability using eBPF's powerful features.

#### 5. Bisect Method

##### Binary Search

Binary search is particularly suitable for finding target elements in ordered arrays, with a time complexity of O(log n). It continuously narrows the search range through binary division until the target is found or its absence is confirmed. Those with an algorithm background should be familiar with this. Here, we want to discuss the practice of binary thinking in bug localization.

##### git bisect

Using git bisect to find the commit that introduced a bug: `git bisect (good|bad) [<rev>...]`. Suppose we find a bug in the current version (bad=HEAD), but it wasn't introduced in the current version. If we remember that v1.0 was normal, then the bug-introducing commit must be between v1.0 and the current latest version. Git commit history is ordered chronologically, meaning we can use binary search to test each commit and use `git bisect good|bad` to feedback the comparison results to git, helping git determine the next search range. The appendix [《Appendix: Using git bisect to locate the commit that introduced a bug》](../12-appendix/3-git-bisect.md) provides an example.

`git bisect` can lock down bugs at the git commit level, but this isn't enough for large projects. Consider these questions: 1) The program has more than one bug; 2) The bug only appears when several features are enabled together; 3) The code for these features is scattered across multiple commits and source file locations. In this case, using `git bisect` to determine the minimal set of source file locations causing the bug is difficult, especially in projects of a certain scale. How can we solve such problems?

##### bisect reduce

Russ Cox and others proposed a method for quickly locating bug positions in the Go compiler and Go runtime: [Hash-Based Bisect Debugging in Compilers and Runtimes](https://research.swtch.com/bisect). Before this, other technicians had proposed similar techniques, such as List-Based Bisect-Reduce and Counter-Based Bisect-Reduce. Russ Cox and others built on these to propose Hash-Based Bisect-Reduce. The difference is using hash values to uniquely identify code related to each feature (Hash("feat1")) or specific source file locations (Hash("file:lineno")), rather than using lengthy locspec lists or position counters (which become invalid as code changes).

The general idea of bisect reduce is to adopt a "feature toggle" practice, though not exactly the same as feature toggles. It could also be a simple optimization changelist (like multiple source file locations or specific source lines corresponding to a feature)... We give the changelist a name, like MyChangeList. Suppose we use [go bisect](https://github.com/golang/tools/cmd/bisect) and the corresponding [golang/tools/internal/bisect library](https://github.com/golang/tools/tree/master/internal/bisect) to control changelist enabling/disabling and reporting. Then executing the program with `MyChangeList=y ./a.out` is equivalent to enabling all source locations in that changelist, while `MyChangeList=n ./a.out` is equivalent to disabling them. We expect no bug when the changelist is disabled and a bug when enabled. At this point, combined with reporting, we can collect all source locations involved in the changelist, then perform bisect-based reduction on this basis.

The general approach is: first enable half the locations (set a) and check if the expected bug appears. If not, add another half (set b). If there's a bug, reduce the newly added b by half (set c). If the bug disappears after reduction, we can determine that the newly added half (difference set b-c) causes the expected bug. Fix these suspicious locations (b-c) and include them in subsequent searches, then continue searching for possible locations in a... Eventually, we can determine a locally minimal set of source file locations that cause the bug to appear when all are enabled. For the detailed algorithm, refer to https://research.swtch.com/bisect.

Here's a demo for learning how to use bisect in Go projects: [bisect example](https://github.com/hitzhangjie/golang-debugger-lessons/tree/master/1000_hash_based_bisect_reduce).

> Note: bisect reduce and binary search are both based on divide-and-conquer or binary thinking, but they're not exactly the same. In this scenario, using binary search as the core algorithm would be incorrect.

#### 6. Dynamic Tracing

eBPF (extended Berkeley Packet Filter) is a powerful technology that allows users to safely inject and execute custom code without modifying or restarting the kernel or significantly reducing system performance. It's mainly used in networking, performance analysis, and monitoring. Here, we emphasize eBPF's application in dynamic tracing technology. Linux kprobe, uprobe, and tracepoint now support eBPF program callbacks, enabling very powerful dynamic tracing capabilities, such as bpftrace.

For Go language debugging, combining eBPF can achieve dynamic tracing at any source file location, as long as the tool is implemented carefully enough. The author currently maintains a Go program dynamic tracing tool [go-ftrace](https://github.com/hitzhangjie/go-ftrace), which identifies specific function locations based on DWARF debugging information, dynamically adds uprobes, and registers eBPF time-consuming statistics programs, thus achieving powerful function call tracing capabilities.

```bash
$ sudo ftrace -u 'main.*' -u 'fmt.Print*' ./main 'main.(*Student).String(s.name=(*+0(%ax)):c64, s.name.len=(+8(%ax)):s64, s.age=(+16(%ax)):s64)'
...
23 17:11:00.0890           main.doSomething() { main.main+15 ~/github/go-ftrace/examples/main.go:10
23 17:11:00.0890             main.add() { main.doSomething+37 ~/github/go-ftrace/examples/main.go:15
23 17:11:00.0890               main.add1() { main.add+149 ~/github/go-ftrace/examples/main.go:27
23 17:11:00.0890                 main.add3() { main.add1+149 ~/github/go-ftrace/examples/main.go:40
23 17:11:00.0890 000.0000        } main.add3+148 ~/github/go-ftrace/examples/main.go:46
23 17:11:00.0890 000.0000      } main.add1+154 ~/github/go-ftrace/examples/main.go:33
23 17:11:00.0890 000.0001    } main.add+154 ~/github/go-ftrace/examples/main.go:27
23 17:11:00.0890             main.minus() { main.doSomething+52 ~/github/go-ftrace/examples/main.go:16
23 17:11:00.0890 000.0000    } main.minus+3 ~/github/go-ftrace/examples/main.go:51

23 17:11:00.0891             main.(*Student).String(s.name=zhang<ni, s.name.len=5, s.age=100) { fmt.(*pp).handleMethods+690 /opt/go/src/fmt/print.go:673
23 17:11:00.0891 000.0000    } main.(*Student).String+138 ~/github/go-ftrace/examples/main.go:64
23 17:11:01.0895 001.0005  } main.doSomething+180 ~/github/go-ftrace/examples/main.go:22
```

#### 7. Deterministic Replay

Even with all these impressive technologies, there's still a problem troubling developers: "**We know there's a bug, but how do we reproduce it stably?**" Flaky tests are one of the most headache-inducing problems for developers during debugging. There are several ways to address this: 1) Start by preparing reproducible test cases to see if we can construct test parameters that make the originally unstable bug reproducible; 2) Use deterministic replay technology to first record the scenario when the problem occurs, then replay this scenario unlimited times. The first approach should be understood as an engineering practice that we should do daily. But when facing tricky problems, even doing this might not work. Here, we focus on the second approach.

> You record a failure once, then debug the recording, deterministically, as many times as you want. The same execution is replayed every time.
>
> As long as you can record a failure once, you can use this recording for unlimited replay and deterministic debugging.

The star project **Mozilla RR** achieves this by recording the complete context information of non-deterministic program execution, enabling precise replay of the state during debugging based on the recording file. RR also supports reverse debugging, such as reverse debugging commands in gdb and dlv, which can be implemented when using Mozilla RR as the debugger backend. This is very useful as you don't need to restart the entire debugging process just because you missed an execution statement.

Readers might be curious about what "recording complete context information" means in RR. It includes system call results, received signals, thread creation and destruction, thread scheduling order, shared memory access, clocks and counters, hardware interrupts, sources of randomness, memory allocation situations, and more. For details on how these problems are solved, see the paper: [Engineering Record And Replay For Deployability: Extended Technical Report](https://arxiv.org/pdf/1705.05937). Based on recording this information, we can do some work with the tracer during debugging to achieve precise state replay, thus solving the problem of interference from variable factors that cause flaky tests.

> Note: How is recording data precisely replayed? Readers can first think about the series of controls that ptrace (introduced in this book) has over the tracee, such as controlling how many instructions the tracee executes before stopping, reading and writing register information, etc., to see if there are any ideas. For the complete solution, refer to Mozilla RR's paper.

#### 8. Distributed System Debugging

In system architecture design, microservices architecture is increasingly favored for its advantages like independent deployment, technological diversity, scalability, fault isolation, team autonomy, and modular design. However, it also brings some challenges, which is why the industry has developed targeted solutions for microservices governance, such as a series of star projects in CNCF. Here, we focus on the challenges it brings to software debugging.

Under microservices architecture, since a complete transaction is processed across multiple microservices, debugging becomes very troublesome:

- First, the entire system's operation depends on the correct deployment of all microservices, which might involve many machines, not necessarily supporting mixed deployment, and not necessarily guaranteeing each developer has their own testing environment;
- Without a dedicated testing environment, the traditional debugger approach of attaching to a process for tracking would affect service normal operation and other people's testing;
- Even with a dedicated testing environment, if mixed deployment isn't possible, you still need to log into multiple machines to attach to target processes for tracking;
- Even with a dedicated testing environment and mixed deployment capability, it's still difficult to coordinate attaching to multiple processes and setting breakpoints at the right locations and times;
- ……

In short, trying to solve this problem using the debugger approach is really difficult. We generally solve such problems in microservices architecture through Logging, Metrics, and Tracing systems, which work quite well in production environments. But to say this solution is perfect would be unrealistic. For example, in development and testing environments, we want to quickly locate problems, but the reality is: 1) You might need to wait a while to observe logs, monitoring reports, and trace information, with some delay. 2) You might need to repeatedly modify code (adding logs, monitoring, creating new traces or spans), compile, build, deploy for testing... before you can observe.

What a debugger might solve in seconds, just because it's difficult to coordinate attaching to multiple processes on multiple machines and setting breakpoints at the right time, should we consider debuggers incapable of handling this scenario? SquashIO provides a complete solution for cloud-native scenarios: Squash Debugger, supporting container orchestration platforms like Kubernetes, Openshift, and Istio, real-time injection of debug containers, automatic association with corresponding version source code, automatic triggering of breakpoints for specific interface handling functions after RPC calls, and UI support for automatic switching to target services, supporting common IDEs like VSCode.

### Debugging Technology Selection Philosophy

From monolithic applications to cloud-native and distributed systems, debugging technology has formed a multi-dimensional arsenal, creating a technology matrix for different scenarios. The upcoming series of articles will deeply analyze the implementation principles, best practices, and cutting-edge developments of each technology, helping developers establish a three-dimensional debugging mindset of "scenario-tool-methodology." Debugging is not just a process of solving problems but a cognitive revolution in understanding system essence. Mastering debugging technologies for different scenarios gives developers a god's-eye view, allowing them to understand the system's full picture and investigate everything through the fog.

### References

1. [Hash-Based Bisect Debugging in Compilers and Runtimes](https://research.swtch.com/bisect)
2. [go bisect tool](https://github.com/golang/tools/tree/master/cmd/bisect)
3. [go bisect library](https://github.com/golang/tools/tree/master/internal/bisect)
4. [Engineering Record And Replay For Deployability: Extended Technical Report](https://arxiv.org/pdf/1705.05937)
5. [Squash Debugger Docs](https://squash.solo.io/)
6. [Squash Debugger GitHub](https://github.com/solo-io/squash)
7. [Lightning Talk: Debugging microservices applications with Envoy + Squash - Idit Levine, Solo.io](https://www.youtube.com/watch?v=i5_eacXkw3w)
8. [Dapper, a Large-Scale Distributed System Tracing Infrastructure](https://static.googleusercontent.com/media/research.google.com/en//archive/papers/dapper-2010-1.pdf)
9. [OpenTelemetry](https://opentelemetry.io/)
