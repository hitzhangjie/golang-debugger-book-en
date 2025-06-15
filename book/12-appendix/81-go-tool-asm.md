## Extended Reading: Introduction to Go Assembler

### 1. Relationship between Plan9 Project and Go Language

Plan9 is a research-oriented distributed operating system from Bell Labs. Many of Go's early core developers came from this project group, bringing their experience from designing and implementing Plan9 to Go, particularly in the areas of a.out file format, plan9 assembly, and toolchain.

see: https://man.cat-v.org/plan_9/6/a.out, for example:

- The object file format after assembly output, and the symtab+pclntab that the runtime depends on;
- The assembly language used, pseudo-registers (fp,sb,sp,pc);

  - `FP`: Frame pointer: arguments and locals.
  - `PC`: Program counter: jumps and branches.
  - `SB`: Static base pointer: global symbols.
  - `SP`: Stack pointer: the highest address within the local stack frame.

  in Go, all user-defined symbols are written as offsets to the pseudo-registers `FP` (arguments and locals) and `SB` (globals).

### 2. Differences between Plan9 and Other Operating Systems

Plan9 itself is an experimental operating system, and it has some design and implementation aspects that differ from conventional operating systems:

- Everything is a file, including operations on network sockets and even remote computers. The API is through a unified programming interface, taking the Unix/Linux operating system design to an extreme;
- Some unusual toolchain naming:
  - 2c,3c,4c...8c, these are compilers that compile .c source code into plan9 assembly files;
  - 2a,3a,4a...8a, these are assemblers that assemble .s source code into object files;
    Note: object file, is it better to translate as "object file" or "target file"? @gemini suggests "target file" is better, ok! Part of the target program.
  - 2l,3l,4l...8l, these are loaders that perform symbol resolution and relocation operations typically done by a linker before loading the executable into memory;
    Note: There is no dedicated linker, the plan9 loader includes some conventional linker functionality, well, ok!
- Assembly instructions are a semi-abstract instruction set, not strictly corresponding to specific platform instructions. For example, the MOV operation, during the instruction selection phase, will choose platform-specific machine instructions. This is true for both plan9 and go;

> **Plan9 loaders**: Questions about Plan9 loaders 2l,3l,..8l, why is there no dedicated linker? Do Plan9 loaders have conventional linker functionality?
> In the Plan 9 operating system, the role of "loaders" (such as `8l` for Intel 386) overlaps significantly with what is traditionally considered a "linker".

Explanation of Plan9 loader functionality:

* **Compilers and Loaders:**
  * Plan 9's compilers (like `8c`) generate object files.
  * Then, the loader takes these object files and produces the final executable.
* **Loader Functions:**
  * Plan 9's loader does more than just perform typical runtime "loading" operations. It also performs crucial linking tasks, including:
    * **Symbol Resolution:** Resolving references between different object files and libraries.
    * **Machine Code Generation:** In plan9, the loader is the program that actually generates the final machine code.
    * **Instruction Selection:** Choosing the most efficient machine instructions.
    * **Branch Folding and Instruction Scheduling:** Optimizing the executable.
    * **Library Linking:** Automatically linking necessary libraries.
* **Key Differences:**
  * A significant difference is that the Plan 9 loader handles most of the final machine code generation, while in many other systems, this work is done earlier in the compilation process. This means plan9 compilers produce an abstract assembly, which the loader converts into final machine code.
* **Essentially:**
  * The Plan 9 loader's functionality goes beyond just loading; it includes core linking responsibilities.

### 3. Similarities and Differences between Plan9 and Go Assemblers

To fully master Go assembly, one must understand its predecessor and its own evolution, meaning understanding the Plan9 assembler and Go's special aspects.

- [a manual for plan9 assembler, rob pike](https://doc.cat-v.org/plan_9/4th_edition/papers/asm)
- [a quick guide to Go&#39;s assembler](https://go.dev/doc/asm)

If there's an opportunity later, I can summarize the use of the Go assembler in my blog. In this e-book, we won't expand too much on this topic. We'll just introduce the main work of the Go assembler. We won't consider special support for Go assembly during debugging... this is not in our plan unless we have plenty of time.

### References

- plan9 a.out object file format, https://man.cat-v.org/plan_9/6/a.out
- plan9 assemblers, https://man.cat-v.org/plan_9/1/2a
- plan9 compilers, https://man.cat-v.org/plan_9/1/2c
- plan9 loaders, https://man.cat-v.org/plan_9/1/2l
- plan9 used compilers, https://doc.cat-v.org/bell_labs/new_c_compilers/new_c_compiler.pdf

  > "*This paper describes yet another series of C compilers. These compilers were developed over the last several years and are now in use on Plan 9. These compilers are experimental in nature and were developed to try out new ideas. Some of the ideas were good and some not so good.*"
  >
- how to use plan9 c compiler, rob pike, https://doc.cat-v.org/plan_9/4th_edition/papers/comp
- a manual for plan9 assembler, rob pike, https://doc.cat-v.org/plan_9/4th_edition/papers/asm
- a quick guide to Go's assembler, https://go.dev/doc/asm
