## Symbol-Level Debugging Basics

### Content Review

Previously, we introduced various controls over the tracee during instruction-level debugging, such as thread tracking, execution to breakpoints, single-step execution, reading and writing memory, and reading and writing registers. These are also essential control capabilities for symbol-level debugging. As mentioned earlier, a well-designed symbol-level debugger should have at least a three-layer architecture, including the UI layer, the symbolic layer, and the target layer. This organization provides a clear software structure and better extensibility:

![debugger-arch-1](../5-debugger-skeleton/assets/debugger-arch-1.png)

Let's review the three-layer architecture of the debugger:

- **UI Layer**: Primarily responsible for user interaction, 1) executing debugging actions, such as adding breakpoints and single-step execution; 2) displaying debugging information, such as variable values and stack information. Separating the UI layer facilitates the separation of interaction and display logic from core debugging logic, making it easier to change or support different user interfaces.
- **Symbolic Layer**: Primarily responsible for parsing debug symbol information, such as understanding variables, functions, source code locations, and the conversion of memory instructions and data addresses, as well as call stacks. It serves as a bridge between user UI operations and the execution control of the target program. For example, when we print a variable value, we use the variable name, and when adding a breakpoint, we use the source code file:line number. Separating the symbolic layer makes it easier to support different debug information formats.
- **Target Layer**: The target layer directly interacts with the program being debugged, responsible for executing debugging commands to control the process, read and write data, such as setting breakpoints, single-step execution, reading memory and register data, etc. Separating the target layer makes it more convenient to support different platforms, such as different operating systems and hardware architectures. The control capabilities over the process implemented in Chapter 6 for instruction-level debugging will be partially delegated to the target layer.

### Challenges Faced

Symbol-level debugging relies on debug information generated by the compiler and linker under the guidance of debug information standards. There are various types of debug information, with DWARF (Debugging With Attributed Record Formats) being widely used today. The Go language compilation toolchain also uses DWARF, and debuggers like GDB and Delve support DWARF.

Are we ready to understand DWARF? Probably not yet. Before detailing DWARF's powerful descriptive capabilities for different programming languages, I need to assume that readers may not have a comprehensive understanding of the compilation toolchain (which might indeed be the case). Here, I will prepare for the worst and supplement some necessary knowledge to help most readers smoothly transition to the DWARF chapter, and then we can proceed to the development of symbol-level debuggers. If readers are familiar with this area, they can skim through it more quickly.

OK, let's quickly summarize: to implement a symbol-level debugger, besides the instruction-level debugging content we have already mastered, we need to understand how the Go compiler and linker use DWARF to describe different program constructs in Go. This way, after the debugger reads the DWARF debug information in the Go program, it can also know what specific program construct in Go is being described.

Taking the Linux ELF file format as an example, the compiler and linker are responsible for generating DWARF debug information and storing it in the `.(z)debug_` sections of the ELF file. From the DWARF standard, based on the different objects being described, DWARF debug information can be subdivided into the following major categories:

- Describing data types;
- Describing variables;
- Describing function definitions;
- Describing line number tables;
- Describing call stack information tables;
- Describing symbol tables;
- Describing string tables;
- And more.

Besides generating DWARF debug information, the compilation toolchain also considers support for some language runtime features, which adds some language-specific sections. It also needs to consider generating common sections to be compatible with existing binary tools. For example, the Go compiler and linker generate DWARF debug information (.[z]debug_* sections) for debuggers to use, and they additionally generate .gosymtab and .gopclntab for the Go runtime to track call stack information, and .note.go.buildid to preserve Go build ID information. Additionally, they generate .symtab for general binary analysis tools like readelf.

The implementation of symbol-level debugging relies on DWARF, but whether it fully depends on DWARF depends on the specific implementation. This depends on whether the compiler and linker generate sufficiently complete debug information, or whether the parsing efficiency of the debug information is high enough. Some language compilation toolchains do not achieve this level, or the DWARF version used does not design the data format for efficient parsing. Some debuggers may fall back to reading other ELF sections to help implement debugging functions, or to improve debugging efficiency and experience.

Therefore, implementing a symbol-level debugger can theoretically rely on DWARF, but in practice, more real-world issues need to be considered. Implementing an efficient and usable symbol-level debugger requires recognizing that this area might have been a challenge in the past. Now, there should be no worry, as go-delve/delve relies entirely on DWARF, while GDB still uses some information from the symbol table.

### Chapter Goals

In this chapter, I plan to introduce the commonly used ELF file format in Linux executable programs, the differences between sections and segments, and how the compiler, linker, and loader work together. We will discuss how our written programs go from source code to executable programs, to being loaded into memory address space, and being scheduled for execution by the operating system process scheduler. Then, we will briefly introduce some interesting feature implementations related to the Go language, such as goroutines. During this process, we will explain why the compiler and linker generate certain sections and segments, and how segments are loaded into the process address space by the loader, and how symbol resolution and relocation are completed. After this chapter, readers will have a clearer understanding of the compilation toolchain and the various parts of the ELF file, fully recognizing that this is a cleverly designed collaborative ecosystem.

If we choose to skip this chapter, the following issues may arise: 1) Readers may not be familiar with ELF, compiler, and linker working principles, and it may be difficult to understand them in a short time, likely leading to a loss of confidence to continue. 2) Debugger design and implementation indeed cannot do without this knowledge, so it's better to systematically go through this muddy water, lest readers have to search for various materials to fill in the gaps. 3) We will frequently mention some terms, such as symbols being used in multiple scenarios but actually being different things. Readers who do not understand the content of this chapter may confuse many technical details.

So, this chapter finally meets everyone, and after reading it, you will have a more comprehensive understanding. This chapter first introduces some basic ELF knowledge, including what some important sections and segments are used for, then introduces the working process of the compiler and linker, how they use certain section data in ELF, and where they generate DWARF debug information, and how to roughly view it. Then, in Chapter 8, we can introduce how DWARF debug information describes the program, and we will enter symbol-level debugging development in Chapter 9. You can also read this chapter with a goal in mind, at least to know who generates DWARF debug information, when and where it is stored, who reads and utilizes it, and how to read it.

> ps: Regarding the term "symbol," it plays different roles at different stages, and the information it carries varies in emphasis:
>
> - **Symbol information in .symtab** is mainly used by the linker for symbol resolution and relocation during linking, or by the dynamic linker (loader) during program loading. This information typically includes function addresses, global variable addresses, etc., used to combine different code and data segments into an executable file.
> - **Information in .debug_info (or .debug_*)** is mainly for debuggers, providing source-level debugging information, such as type names, variable names, function names, etc., stored in the form of DWARF (Debugging With Attributed Record Formats) DIE (Debugging Information Entry). Debuggers use this information for symbol display, breakpoint setting, single-step debugging, etc.
> - **During lexical analysis, syntax analysis, and semantic analysis stages**, the compiler analyzes symbols such as type names, variable names, and function names in the source code and generates an internal symbol table (not .symtab) containing more detailed information. This information is not only used for type safety checks and other analysis processes but also provides a basis for subsequent optimization and code generation.
>
> Note that when the term "symbol" is mentioned in different contexts, readers should not confuse the related meanings and technical details.
