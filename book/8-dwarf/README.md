## Software Debugging Challenges

<img alt="dwarf-logo" src="assets/dwarf-logo.svg"/>

It would be wonderful if we could write programs that run correctly without needing debugging. But at least until we achieve that goal, the normal programming cycle still includes writing programs, compiling programs, executing programs, and the often headache-inducing debugging process that follows. Then we iterate until the program achieves the desired results.

### Throughout the Lifecycle

Software debugging technology runs through the entire software development lifecycle, not just during development and testing phases. Even after software is delivered and goes live, it still requires long-term maintenance and iteration. Chapter 10 of this book details different problem-solving techniques in the software development lifecycle, hoping to inspire readers' thinking. Different scenarios may require appropriate means (either a single method or a combination of several methods) to achieve better results with less effort. OK, let's return to our topic and focus on software debugging using debuggers.

One method of debugging programs is to insert statements that print the values of selected variables into the code. In some cases, such as debugging kernel drivers, this might be a common approach. Low-level debuggers allow you to execute programs instruction by instruction and display binary information about register and memory contents. However, using source-level debuggers is usually more convenient, allowing you to execute program code line by line, set breakpoints, print variable values, and provide other features, such as calling functions in the program during debugging. The key is how to coordinate the compiler and debugger, two completely different programs, to achieve program debugging.

### The Difficulty of Reconstructing Source Code Perspective

Converting human-readable code into binary form that processors can execute is a rather complex process. It essentially involves transforming source code into increasingly simpler forms, discarding information at each step, ultimately resulting in a series of simple instructions, registers, memory addresses, and binary values that the processor can understand. The processor doesn't really care whether you used object-oriented programming, templates, or smart pointers - it only understands very basic operations performed on a limited number of registers and memory locations.

When reading and parsing source code, the compiler collects information about the program, such as line numbers where variables or functions are declared and used. Semantic analysis then supplements details like variable types and function parameters. The optimization phase might rearrange code structure, merge similar code segments, expand inline functions, or remove redundant parts. Finally, the code generator converts the program's internal representation into actual machine instructions. To further improve efficiency, machine code is usually subjected to "peephole optimization," a local optimization technique that, for example, rewrites several instructions into more efficient ones or eliminates duplicate instructions.

In summary, the compiler's task is to convert carefully written and easily understandable source code into efficient but essentially difficult-to-understand machine language. The more the compiler achieves its goal of creating compact and fast code, the more likely the result will be difficult to understand.

During the transformation process, the compiler collects information about the program that will be very useful for subsequent debugging. There are two challenges in this regard. First, in the later stages of the transformation process, the compiler may find it difficult to connect the changes it made with the source code originally written by the programmer. For example, the peephole optimizer might delete an instruction because it can rearrange the execution order of C++ template code in inline function instantiations. When the optimizer operates on the program, it may find it difficult to connect low-level code operations with the original source code that generated them.

Second, describing the executable program and its relationship with the original source code in sufficient detail while maintaining conciseness, avoiding excessive space usage or processor time consumption, is itself a challenge. This is where the DWARF debugging format comes in, representing the connection between executable programs and source code in a relatively efficient way that's convenient for debuggers to process.

### Software Debugging Process

When developers debug programs, they often need to perform some common operations. The most common is setting breakpoints to pause debugging at specific locations in the source code, which can be done by specifying line numbers or function names. When a breakpoint is triggered, programmers typically want to view the values of local or global variables, or function parameters. Viewing the call stack helps programmers understand how the program reached the breakpoint, especially when there are multiple execution paths. After gathering this information, programmers can instruct the debugger to continue testing the program's execution.

There are other useful operations during debugging. For example, tracking program execution line by line can be helpful, allowing entry into or skipping of called functions. Setting breakpoints at each instance of templates or inline functions is crucial for debugging C++ programs. Stopping before a function returns to view or modify the return value can also be helpful. Sometimes, programmers may need to bypass function execution and directly return a known value instead of letting the function (possibly incorrectly) calculate the result.

Additionally, some data-related operations are useful. For example, directly displaying variable types can avoid searching in source code. Displaying variable values in different formats, or displaying memory or registers in specified formats, can provide convenience.

Some operations can be considered advanced debugging features, such as debugging multi-threaded programs or programs stored in read-only memory. People might want the debugger (or other program analysis tools) to record which parts of the code have been executed. Some debuggers also allow programmers to call functions in the program being tested. In the past, debugging optimized programs was considered an advanced feature.

The debugger's goal is to present the executing program to the programmer in as natural and understandable a way as possible, while providing broad control permissions. This means the debugger needs to reverse the complex transformations made by the compiler as much as possible, converting the program's internal state back to the form used in the source code originally written by the programmer.

The challenge for debugging data formats like DWARF is to achieve this reversal while making it simple and easy to do.

### Debug Information Formats

In the field of software debugging, several debugging formats have emerged, but they all had various issues, such as stabs, COFF, PE-COFF, OMF, and IEEE-695. DWARF can be considered a latecomer.

The name "stabs" comes from symbol table strings, as the original debugging data was stored in the Unix a.out object file symbol table in string form. Stabs uses text strings to encode program information. It was initially very simple but evolved into a rather complex, sometimes difficult to understand, and somewhat inconsistent debugging format. Stabs was neither standardized nor well-documented. Sun Microsystems made many extensions to stabs, and GCC made other extensions, attempting to reverse engineer Sun's extensions. Despite this, stabs was widely used.

COFF stands for Common Object File Format, originating from Unix System V Release 3. Basic debugging information was defined in the COFF format, but because COFF supported named sections, various different debugging formats, such as stabs, were used with COFF. The main problem with COFF was that despite having "Common" in its name, it wasn't entirely consistent across different architectures. COFF had many variants, including XCOFF (for IBM RS/6000), ECOFF (for MIPS and Alpha), and Windows PE-COFF. Documentation availability for these variants varied, but neither the object module format nor debugging information was standardized.

PE-COFF is the object module format used by Microsoft Windows starting from Windows 95. It's based on the COFF format and includes COFF debugging data along with Microsoft's own proprietary CodeView or CV4 debugging data format. Documentation about the debugging format was both incomplete and difficult to obtain.

OMF stands for Object Module Format, used by CP/M, DOS, and OS/2 systems, as well as a few embedded systems. OMF defined common names and line number information used by debuggers and could include debugging data in Microsoft CV, IBM PM, or AIX format. OMF only provided the most basic support for debuggers.

IEEE-695 is a standard object file and debugging format jointly developed by Microtec Research and HP in the late 1980s for embedded environments. It became an IEEE standard in 1990. This was a very flexible specification designed to work with almost any machine architecture. The debugging format used a block structure that better reflected the organization of source code. Although it was an IEEE standard, in many ways it was more like a proprietary format. While the original standard could be obtained from IEEE, Microtec Research extended it to support C++ and optimized code, with poorly documented extensions. The IEEE standard was never modified to incorporate Microtec Research or other changes. Despite being an IEEE standard, its use was limited to a few small processors.

**DWARF** is now the widely used debugging information format (although initially designed for ELF files). The word "DWARF" comes from medieval fantasy novels and has no official meaning. Later, "**Debugging With Attributed Record Formats**" was proposed as an alternative definition for DWARF debugging information. DWARF uses **DIE + Attributes** to describe types and data, code, and other program constructs. DWARF also defines data such as **Line Number Table** and **Call Frame Information**, which enable developers to dynamically set breakpoints from a source code perspective, display the source code location corresponding to the current PC, and track call stack information.

### Summary

This article briefly introduces the necessity and importance of software debugging in the entire software development lifecycle, and also introduces the deliberate removal of information during the transformation from source code to executable programs. There are significant difficulties and challenges in reconstructing the source code perspective from executable programs. Then it lists the problems with common debugging information formats, which all once focused on implementing source code perspective reconstruction. The DWARF standard contains many ingenious designs and is now the most widely used debugging information format, used by languages such as C, C++, and Go. If you're interested in symbolic debugging of high-level languages, it's recommended to study this chapter.

### References

1. DWARF, https://en.wikipedia.org/wiki/DWARF
2. DWARFv1, https://dwarfstd.org/doc/dwarf_1_1_0.pdf
3. DWARFv2, https://dwarfstd.org/doc/dwarf-2.0.0.pdf
4. DWARFv3, https://dwarfstd.org/doc/Dwarf3.pdf
5. DWARFv4, https://dwarfstd.org/doc/DWARF4.pdf
6. DWARFv5, https://dwarfstd.org/doc/DWARF5.pdf
7. DWARFv6 draft, https://dwarfstd.org/languages-v6.html
8. Introduction to the DWARF Debugging Format, https://dwarfstd.org/doc/Debugging-using-DWARF-2012.pdf
