## DWARF Data Classification

DWARF (Debugging With Attributed Record Formats) uses a series of data structures to store debugging information, which allows debuggers to provide source-level debugging experience. The core concept is the **Debugging Information Entry (DIE)**, along with key table structures that support these entries.

### DWARF DIEs

#### Tags & Attributes

DWARF uses **Debugging Information Entries (DIE)** to represent various constructs in a program, such as variables, constants, types, functions, compilation units, etc. Each DIE contains the following key elements:

- **Tag:** An identifier (e.g., `DW_TAG_variable`, `DW_TAG_pointer_type`, `DW_TAG_subprogram`) that indicates the type of program construct the DIE represents. These tags define the semantics of the DIE.
- **Attributes:** Key-value pairs that provide additional information about the DIE. For example, a variable's DIE might have attributes like `name` (variable name), `type` (variable type), `location` (variable's location in memory), etc.

#### Relationships between DIEs

- **Children:** A DIE can contain other DIEs as its children. These children form a tree-like hierarchical structure used to describe complex program constructs. For example, a compilation unit contains defined functions, and each function contains function parameters, return values, and its local variables. Children DIEs are stored immediately after their parent DIE, and reading Children DIEs continues until a null DIE object is encountered, indicating the end.
- **Siblings:** References between DIEs can also be implemented through attributes. For example, a DIE describing a variable needs an attribute to specify its data type, namely the `DW_AT_type` attribute, which points to a DIE describing the data type. This hierarchical relationship allows DWARF to describe complex type and scope structures.

DIEs establish reference relationships in two different dimensions: Children and Siblings, effectively forming a huge tree. To reduce storage space, some encoding methods have been designed to handle this.

#### Classification of DIEs

Based on the different data types they describe, DIEs can be roughly divided into: those describing data and data types, and those describing functions and executable code.

- Describing data and data types: such as describing basic types, composite types, such as describing array, struct, class, union, and interface types, such as describing variables, such as location expressions describing where variables are located;
- Describing functions and executable code: such as describing functions (subprogram), such as describing compilation units;

### Important Table Structure Data

To support source-level debugging, symbolic debuggers need two important tables: the Line Number Table and the Call Frame Information.

1. **Line Number Table:** Establishes a mapping relationship between program code instruction addresses and source file locations (file:line:col). It typically includes source file names, line numbers, column numbers, and corresponding instruction addresses. Through this mapping table, the debugger can convert the current execution position (PC) to a position in the source code for display during debugging; the debugger can use this table to convert source code locations to memory instruction addresses and add breakpoints at instruction addresses, allowing us to add breakpoints using source file locations.

   The line number table records the following detailed information, enabling us to do more:

   - For a function, it indicates the instructions for the function prologue and epilogue, which can be used to draw the function's callgraph.
   - For a line of source code, which may contain one or more expressions or statements corresponding to multiple instructions, it can indicate the position of the first instruction to add breakpoints at the exact location.

2. **Call Frame Information:** Allows the debugger to determine its stack frame on the call stack based on the instruction address. This is crucial for tracking function calls and understanding the program's execution flow. It records the instruction address PC during execution, along with the current values of the "Stack Pointer SP" and "Frame Pointer FP", as well as the return address.

To reduce the storage space of these tables, DWARF uses state machines and bytecode instructions to encode them. These instructions tell the state machine how to process line number information and stack frame information, thus avoiding redundant data storage. The debugger loads this encoded data and gives it to the state machine to execute, and the state machine's output is the table needed by the debugger. This encoding method significantly reduces the size of debugging information, making DWARF usable on various platforms.

### Other DWARF Data

In addition, DWARF has other data, such as Accelerated Access data and Macro Information.

### Summary

This article briefly introduces several types of data we most commonly deal with in DWARF debugging information. DIE is a description of different program constructs, while the line number table and call frame information table represent static and dynamic views of program execution. There are also other DWARF data for different purposes. OK, next, we will introduce how to use DIE to describe different program constructs.

### References

1. DWARF, https://en.wikipedia.org/wiki/DWARF
2. DWARFv1, https://dwarfstd.org/doc/dwarf_1_1_0.pdf
3. DWARFv2, https://dwarfstd.org/doc/dwarf-2.0.0.pdf
4. DWARFv3, https://dwarfstd.org/doc/Dwarf3.pdf
5. DWARFv4, https://dwarfstd.org/doc/DWARF4.pdf
6. DWARFv5, https://dwarfstd.org/doc/DWARF5.pdf
7. DWARFv6 draft, https://dwarfstd.org/languages-v6.html
8. Introduction to the DWARF Debugging Format, https://dwarfstd.org/doc/Debugging-using-DWARF-2012.pdf
