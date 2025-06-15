## 4.1 Purpose

Despite developers spending significant effort to avoid introducing bugs in their code, writing bugs is still a common occurrence. When developers need to locate issues in their code, they typically rely on **Print statements** (such as `fmt.Println`) to print variable values and infer whether the program execution results meet expectations. In more complex scenarios, print statements may not be sufficient, and a debugger can better assist us in locating problems.

A debugger can help us control the execution of the tracee (the process/thread being debugged) and observe the runtime memory and register states of the tracee. This allows us to implement step-by-step code execution, control code execution flow, check if variable values meet expectations, and more.

I believe that for beginners, a debugger is an indispensable tool that can also deepen their understanding of programming languages, memory models, and operating systems. Even for developers with years of experience, a debugger can be a useful helper.

This book will guide us in developing a debugger for the Go language. If readers have prior experience with symbolic debuggers (such as gdb, delve, etc.), it will be very helpful for understanding the content of this book.

Important operations that a debugger needs to support typically include:

- Setting breakpoints at specified memory addresses, functions, statements, or file line numbers;
- Single-step execution, executing one instruction at a time, one statement at a time, or running to the next breakpoint;
- Getting and setting register information;
- Getting and setting memory information;
- Evaluating expressions;
- Calling functions;
- Others;

> ps: Go is widely used in microservice development. How can we conveniently debug microservices in a microservice architecture? If it's a monolithic application, we can still understand the whole picture by tracking the states of multiple threads and coroutines. But when the processing is decomposed into multiple different microservices, how can we debug the entire processing flow through a debugger?
>
> For online services, this approach has limited applicability because it has a significant performance impact, and the container platform must relax security settings related to debugging, which means there may be more security risks. Using OpenTelemetry to observe metrics, logging, and tracing data of online services should be more effective.
>
> However, for services in the development phase, this approach has significant advantages. Solutions like OpenTelemetry have noticeable latency, which isn't a good solution for timely debugging. If we could debug the entire microservice upstream and downstream at a single point, that would be great. Is it possible? Solo.io has created [**Squash**](https://squash.solo.io/), a debugger for microservice architectures.
>
> At the end of this book, we'll also briefly explain the implementation approach of Squash to see how others have achieved this :)

The subsequent chapters of this book will introduce how to implement the above operations. If you're curious about how debuggers work internally, please continue reading.
