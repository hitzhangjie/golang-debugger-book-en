## More About Instruction-Level Debugging

### Brief Review

This chapter builds an instruction-level debugger from scratch using Go language, explaining it through detailed descriptions and examples, allowing readers to practice and understand every detail hands-on. We not only provided test code that can be directly compiled and run but also carefully designed each test operation and expected results, striving to make it easy for every learner to get started and gain profound experience through practice.

Throughout the development process, we delved deep into the Go language runtime environment and operating system kernel level work, helping readers establish a more comprehensive debugging knowledge framework. This is not just a technical exploration journey; we believe it has also reduced readers' fear of the Go runtime and Linux kernel while increasing their interest in further study and research. This experience is very important for those who aspire to become excellent software engineers.

> Note: Without the contributions of open-source experts, I would have nothing to learn, summarize, or share. Special thanks to [derekparker](https://github.com/derekparker) and [arzilli](https://github.com/aarzilli) for their contributions to the Go language debugger `go-delve/delve` 👍

### Famous Tools Review

This book dedicates a chapter to introducing common features of instruction-level debuggers and related technical details, but there's still a distance from being highly efficient and practical. The original intention of this book was not to implement a more efficient debugger, but a powerful debugger is truly fascinating - it's like giving you the eyes of God and the hands of a creator, allowing you to observe how the world runs and influence its trajectory with a touch of your fingertips.

How can the technical details behind their implementation not be fascinating? Therefore, I want to share these insights, so that based on this understanding or consensus, everyone can continue to explore and make good use of these powerful tools for their own purposes.

Here are some well-known debuggers that support instruction-level debugging:

1. **GDB (GNU Debugger)** - When used in assembly mode, it provides complete instruction-level debugging capabilities. GDB supports multiple processor architectures and can be integrated with various front-end interfaces.
2. **WinDbg** - A powerful low-level debugger developed by Microsoft, widely used for Windows system debugging and driver development. It supports kernel-mode and user-mode debugging, and can analyze dump files and live systems.
3. **OllyDbg** - A tool widely used for Windows binary analysis, featuring a user-friendly interface and a rich plugin ecosystem. Particularly suitable for reverse engineering and malware analysis.
4. **IDA Pro** - A professional-grade disassembler and debugger that provides interactive debugging capabilities, supports multiple platforms and processor architectures, and is very popular in security research and reverse engineering.
5. **LLDB** - Part of the LLVM project, provides functionality similar to GDB but with a more modern architecture, particularly suitable for debugging programs compiled with LLVM.
6. **x64dbg/x32dbg** - Open-source Windows debugger with an intuitive user interface and powerful feature set, very popular among security researchers and reverse engineers.
7. **Radare2/Cutter** - Open-source reverse engineering framework, providing powerful command-line tools and graphical interface (Cutter), supporting multiple file formats and architectures.
8. **Ghidra** - Reverse engineering tool released by the National Security Agency, featuring powerful analysis capabilities and plugin system, including debugging functionality.

### Their Advantages

**Advantages of Instruction-Level Debugging**:

As introduced above, these well-known disassembly tools, debuggers, and software reverse engineering tools are indeed powerful, and we recommend readers take time to understand them. However, specifically regarding instruction-level debugging, I think their advantages are mainly reflected in the following aspects, which might not be the focus of symbolic debugger design and implementation (for example, dlv supports disass but not callgraph like radare2).

* **Compiler Optimization Issues**: When compiler optimizations cause unexpected behavior, requiring examination of actually generated instructions.
* **Hardware-Related Issues**: Debugging code that directly interacts with hardware, such as drivers and embedded systems.
* **Software Analysis Without Source Code**: Reverse engineering commercial software or legacy systems.
* **Complex Crash Analysis**: Investigating complex crash paths not obvious from source code.
* **Security Vulnerability Research**: Analyzing and developing exploit or defense mechanisms.

**Advantages of Symbolic Debugging**:

While instruction-level debuggers are powerful, it depends on the scenario and the developer. For most developers writing business logic in high-level languages, a good symbolic debugger might be more practical. Therefore, we need to emphasize the respective advantages of instruction-level and symbolic debuggers - they are not separate, and some symbolic debuggers also support common instruction-level debugging.

* **Higher Level of Abstraction**: Using variables, functions, and data structures instead of registers and memory addresses makes the debugging process more intuitive.
* **Faster Debugging Process**: More intuitive for developers familiar with source code, allowing faster problem location.
* **Language Feature Support**: Understanding specific programming language constructs, such as classes, exception handling, generics, etc.
* **Productivity Enhancement**: Quicker problem identification in self-written code, more efficient for most daily development debugging tasks.
* **Team Collaboration**: Easier to share and discuss findings with team members, as debugging is done at the source code level.

### Summary

Although instruction-level debugging has a steep learning curve, it provides depth and control that source-level debugging cannot match, making it an indispensable tool for developers and researchers who need to deeply understand how systems work internally.

> Note: Here we recommend readers to master the use of radare2, which also has a version with graphical interface support called Cutter. Previously, I often used Hopper on macOS, but by chance, I learned about radare2, and I recommend it to everyone.

OK, regarding instruction-level debugging, we'll stop here. Next, we'll continue to unveil the mystery of symbolic debugging. Instruction-level debuggers solve problems at the control level of the tracee (execution, pause, register access, memory access, etc.), while symbolic debuggers solve how to establish the connection between source code and process image, such as the relationship between source code and instructions, the relationship between variable values, data types, and memory data, etc. Symbolic debuggers make debugging simpler and more efficient, especially when you don't need to care about lower-level details.

Support for symbolic debuggers is an even larger project. We will learn how debugging information establishes support for different programming languages and program constructs (DWARF), understand how this information is generated (compiler, linker) and utilized (debugger), and learn how to build understanding of source code and process memory data based on debugging information guidance.

Let's begin ~
