## Extended Reading: Introduction to the Go Linker

### 1. What is the Go Linker?

The Go linker is a key component of the Go toolchain, responsible for linking the compiled object files (such as .o files) into the final executable, shared library, or static library. In the Go ecosystem, the linker is usually referred to as `go tool link`, and it is the last step in the Go compilation process, ensuring that all modules and dependencies are correctly combined together.

### 2. How the Go Linker Works

#### Basic Process
1. **Input File Processing**: The linker receives multiple object files (`.o` or `.obj`), static libraries (such as `.a` files), and possibly shared libraries.
2. **Symbol Resolution and Relocation**:
   - The linker scans all input files and resolves undefined symbols. These symbols may come from other object files, libraries, or the Go runtime.
   - For each symbol reference, the linker finds its definition and records the relocation operations needed (such as adjusting pointers to correctly point to functions or variables).
3. **Merging Sections and Segments**:
   - All input files' segments of the same type (such as the `text` segment for code, `data` segment for initialized data) are merged together.
   - The linker processes relocation information in each segment to ensure all pointers and offsets are correct.
4. **Output Generation**: The processed segments are combined into the final executable or library.

#### Internal Mechanisms
- **Symbol Table Management**: The linker maintains a global symbol table to track resolved symbols and their addresses, including functions, variables, and other identifiers.
- **Relocation Records**: The object files generated during compilation contain relocation information, telling the linker which locations need to be adjusted to point to the correct symbol or section.
- **Dependency Handling**: Go's module system allows projects to depend on multiple packages. The linker automatically includes these external libraries, ensuring all necessary code and resources are integrated into the final output.

### 3. Collaboration between Compiler and Linker

#### Related Sections
During compilation, the Go compiler generates several key sections:
- **`text`**: Stores executable code.
- **`data`**: For initialized data (such as global variables).
- **`rodata`**: Read-only data, usually containing constant strings and compile-time constants.
- **`bss`**: Uninitialized zero-initialized data segment.

The compiler is responsible for converting source code into the contents of these sections and recording necessary relocation information in the generated object files. The linker's job is to merge the corresponding sections from all object files and resolve symbol dependencies, ensuring the final program or library can execute correctly at runtime.

#### Collaboration Process
1. **Compilation Phase**: Each Go source file is split into multiple sections, and relocation information is generated.
2. **Linking Phase**:
   - The linker reads section information from all object files and libraries.
   - It resolves undefined symbols, possibly looking up implementations in the standard library or other dependencies.
   - It merges sections (such as merging all `text` sections into a single contiguous code section).
   - It applies relocation operations, adjusting pointer addresses to reflect the actual memory layout.

### 4. Program Header Table in ELF Files

In ELF (Executable and Linkable Format) files, the `program header table` is the result of the combined work of the compiler and linker. Specifically:

- **Compiler**: Generates the initial section information and creates the basic program header table structure.
- **Linker**: Adjusts and finalizes the layout of these sections, updating offsets, sizes, and other information in the program header table to ensure the final file can be correctly loaded by the operating system.

In summary, while the compiler lays the foundation for the ELF file, the linker is responsible for transforming it into an executable form, including adjusting section positions and attributes so the program can run in the target environment.

### 5. References

- TODO [Internals of the Go Linker by Jessie Frazelle](https://www.youtube.com/watch?v=NLl5zwl9Hk8)
- [Golang Internals, Part 2: Diving Into the Go Compiler](https://www.altoros.com/blog/golang-internals-part-2-diving-into-the-go-compiler/)
- [Golang Internals, Part 3: The Linker, Object Files, and Relocations](https://www.altoros.com/blog/golang-internals-part-3-the-linker-object-files-and-relocations/)
- [Golang Internals, Part 4: Object Files and Function Metadata](https://www.altoros.com/blog/golang-internals-part-4-object-files-and-function-metadata/)
- TODO [Linkers and Loaders](https://www.amazon.com/Linkers-Kaufmann-Software-Engineering-Programming/dp/1558604960)

Through these references, you can gain a more comprehensive understanding of how the Go linker works and its importance in the compilation process.
