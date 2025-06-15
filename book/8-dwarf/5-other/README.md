## Other Debug Data

In section 8.3, we discussed describing variables, data types, and executable code through DIE. Section 8.4 will describe debug information that cannot be described by DIE, and this information does not appear in the .debug_info section. This information is also crucial for symbolic debugging.

These important types of debug information include: 1) Accelerated Access Tables 2) Line Number Tables 3) Macro Information 4) Call Frame Information. Similar to the challenges faced in storing DIE data, these table data also have large volumes and require certain encoding strategies for storage optimization. Besides the specific encoding methods for each table, we will also introduce some common encoding methods for DWARF data.

### Important Table Data

#### Accelerated Access

Debuggers often need to quickly locate corresponding DIE or source code positions based on symbol names, type names, and instruction addresses. A naive approach would be to traverse all DIEs, checking if the query key symbol name or type name matches what the DIEs describe, or checking if the instruction address is contained within the address range represented by the corresponding DIEs. This is a method, but it's too inefficient and would affect the debugging experience and efficiency.

To accelerate query efficiency, DWARF creates three accelerated query tables when generating debug information:

- .debug_pubnames: Input a global object or function symbol name to quickly locate the corresponding DIE. For example, entering "main" can directly find the DIE of the main function without traversing all DIEs.
- .debug_pubtypes: Input a type name to quickly locate the DIE describing that type. For example, entering "struct point" can directly find the DIE for that structure type.
- .debug_aranges: Input an instruction address to quickly locate the compilation unit containing that address. This is very helpful for finding the corresponding source code location based on the program counter (PC).

#### Line Number Table

The DWARF line number table (.debug_line) contains the mapping relationship between machine instruction memory addresses in the executable program and corresponding source code lines. Debuggers need this mapping to convert the current executing machine instruction address to the corresponding source code line when users step through the program, thus displaying the current execution position in the source code. The line number table is typically stored in the form of bytecode instructions, which are executed by the line number table state machine to generate the complete line number table. This design allows the line number table to efficiently represent a large number of address-to-line mappings while saving storage space.

The mapping relationship between PC and source code positions in the line number table is not a simple one-to-one relationship, but rather quite complex. First, a source code line may correspond to multiple machine instructions, which may not be contiguous in memory; second, due to compilation optimizations, the execution order of machine instructions may not match the order of source code lines, such as loop unrolling and instruction reordering optimizations that can cause this inconsistency; additionally, features like inline functions, template instantiation, and macro expansion can make one source code position correspond to multiple PC addresses, or one PC address correspond to multiple source code positions. The DWARF line number table uses a state machine approach, using a series of instructions to describe these complex mapping relationships, including operations like setting files, setting line numbers, setting column numbers, and setting instruction addresses, thus accurately recording these complex correspondences.

#### Macro Information

Most debuggers have difficulty displaying and debugging code with macros. For example, a common problem is that users see the original source file with macros, while the code corresponds to the expanded macro content. DWARF debug information includes descriptions of macros defined in the program. Macro information is typically stored in the .debug_macro section, which records macro definitions, parameters, expanded content, and macro definition locations. Debuggers can use this information to display the actual expanded content of macros during debugging, helping developers understand macro behavior and debug macro-related issues. This is particularly important for codebases that use many macros, as macro expansion can introduce complex logic and potential errors.

C/C++ are programming languages that support macros, so debugging C/C++ programs relies heavily on this part of debug information support. Go language designers intentionally abandoned macros, instead providing corresponding capabilities through go generate, interfaces and composition, reflection, and generics, so we won't need to focus too much on this part later.

#### Call Frame Information

Call Frame Information (CFI) is part of DWARF debug information, typically stored in the .debug_frame or .eh_frame section. It describes the layout and changes of stack frames during program execution, including register preservation, stack pointer adjustments, and how to restore the caller's stack frame. CFI is stored in the form of tables or instruction sequences, which are interpreted by the debugger to rebuild the call stack.

During debugging, the debugger needs to know how the currently executing function was called and how to access the function's parameters and local variables. CFI provides this information, allowing the debugger to correctly unwind the call stack, display the function call chain, and help developers understand the program's execution flow. This is particularly important for debugging complex programs, especially those involving recursion or exception handling.

CFI describes stack frame changes through a series of instructions, including:

- **CFA (Canonical Frame Address)**: Defines the base address of the current stack frame, typically pointing to the top of the caller's stack frame.
- **Register Rules**: Describe how to restore register values, for example, certain registers may be saved on the stack.
- **Stack Pointer Adjustments**: Describe how the stack pointer changes to reflect stack frame adjustments during function calls and returns.

By interpreting these instructions, the debugger can rebuild the call stack, determine the stack frame position of each function, and thus access function parameters and local variables. This mechanism allows the debugger to dynamically unwind the call stack during program execution, providing accurate debug information.

### Common Encoding Methods

Different types of DWARF data need to consider encoding methods to reduce storage usage. Besides the DIE data encoding and several important information table data encodings that need to be introduced separately, there are also some common encoding methods.

#### Variable Length Data

Throughout the DWARF debug information representation, integer values are used extensively, from offsets in data segments to array lengths, structure sizes, etc. Since most integer values may be relatively small, requiring only a few bits to represent, this means many high-order bits of integer values consist of zeros. Can we optimize the encoding method to save storage space? Protobuf uses zigzag encoding for integers, which should be familiar to readers who know protobuf. Let's see how DWARF debug information implements this.

DWARF defines a variable-length integer called **Little Endian Base 128** (LEB128 for signed integers or ULEB128 for unsigned integers). LEB128 can compress the bytes used to represent integer values, which undoubtedly saves storage space when there are many small integer values. For more information about LEB128, you can refer to Wiki: https://en.wikipedia.org/wiki/LEB128.

#### Shrinking DWARF Data

Compared to DWARF v1, the encoding scheme used in newer DWARF versions has greatly reduced the size of debug information. Unfortunately, the debug information generated by compilers is still large, typically larger than the storage usage of executable code and data. Newer DWARF versions provide methods to further reduce debug data size, such as using zlib data compression.

### Other Debug Sections

DWARF debug information is categorized and stored in different places based on the objects being described. Taking the ELF file format as an example, DWARF debug information is stored in different sections, with section names all prefixed with '.debug_'. For example, .debug_frame contains call frame information, .debug_info contains core DWARF data (such as variables and executable code described by DIE), .debug_types contains defined types, and .debug_line contains line number table programs (bytecode instructions executed by the line number table state machine to generate the complete line number table).

Due to space limitations, it's difficult to cover all the details of the DWARF debug information standard in one chapter. Just the DWARF v4 content alone is 325 pages. To gain a more in-depth and detailed understanding of this content, you'll need to read the DWARF debug information standard.
