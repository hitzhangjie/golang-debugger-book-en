## DWARF Parsing and Application

Previously, we systematically introduced all aspects of the DWARF debugging information standard: what it is, who generates it, how it describes different data, types, and functions, how it maps instruction addresses to source code locations, how it unwinds the call stack, and the specific design and implementation, etc. We can say that we now have a certain understanding of those high-level designs of DWARF.

Next, we are about to enter the practical stage. Before we start development in the next chapter, let's first understand the current support for reading and writing DWARF data in the mainstream Go debugger go-delve/delve, and then write some test cases to verify what information DWARF can help us obtain.

### DWARF Parsing

Let's introduce the DWARF parsing related code in [go-delve/delve](https://github.com/go-delve/delve). Here is a brief introduction to the purpose and usage of the relevant packages, with more detailed usage in the following sections.

The delve source code version used here is: commit cba1a524. You can check out the corresponding version of delve's source code for further study. Let's quickly get an overview following the author's pace.

#### Directory Structure

Let's first look at the code related to DWARF in delve. This part of the code is located in the pkg/dwarf directory of the project. According to the different types and purposes of DWARF information described, it is further divided into several different packages.

Let's use the tree command to check the directory and file list under the pkg/dwarf package:

```go
${path-to-delve}/pkg/dwarf/
├── dwarfbuilder
│   ├── builder.go
│   ├── info.go
│   └── loc.go
├── frame
│   ├── entries.go
│   ├── entries_test.go
│   ├── expression_constants.go
│   ├── parser.go
│   ├── parser_test.go
│   ├── table.go
│   └── testdata
│       └── frame
├── godwarf
│   ├── addr.go
│   ├── sections.go
│   ├── tree.go
│   ├── tree_test.go
│   └── type.go
├── line
│   ├── _testdata
│   │   └── debug.grafana.debug.gz
│   ├── line_parser.go
│   ├── line_parser_test.go
│   ├── parse_util.go
│   ├── state_machine.go
│   └── state_machine_test.go
├── loclist
│   ├── dwarf2_loclist.go
│   ├── dwarf5_loclist.go
│   └── loclist5_test.go
├── op
│   ├── op.go
│   ├── op_test.go
│   ├── opcodes.go
│   ├── opcodes.table
│   └── regs.go
├── reader
│   ├── reader.go
│   └── variables.go
├── regnum
│   ├── amd64.go
│   ├── arm64.go
│   └── i386.go
└── util
    ├── buf.go
    ├── util.go
    └── util_test.go

11 directories, 37 files
```

#### Function Description

A brief description of the specific functions of the above packages:

| package      | Purpose and Usage |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| dwarfbuilder | Implements a Builder, which can conveniently generate DWARF debugging information corresponding to different code structures. For example, New() returns a Builder and initially sets the header fields of the DWARF information, then you can use the returned builder to add compilation units, data types, variables, functions, etc. <br> This Builder greatly facilitates the rapid generation of corresponding debugging information for source code. However, this package is not very useful for implementing a debugger, but it is very helpful for verifying how the Go toolchain generates debugging information. Once you understand how the Go toolchain generates DWARF debugging information, you can further understand how to parse and apply the corresponding debugging information. <br> The purpose of this package is more for learning and verifying the generation and application of DWARF debugging information. |
| frame        | The information in .[z]debug_frame can help build CFI (Canonical Frame Information). Given any instruction address, we can use CFI to calculate the current call stack. <br> Each compilation unit in DWARF information may compress multiple Go source files. Each compilation unit starts with a CIE (Common Information Entry), followed by a series of FDEs (Frame Description Entry). <br> Here, the types CommonInformationEntry and FrameDescriptionEntry are defined to represent CIE and FDE, respectively. FDE refers to CIE, CIE contains the initial instruction sequence, and FDE contains its own instruction sequence. Combining CIE and FDE can build a complete CFI table. <br> To facilitate determining whether a certain instruction address is within the range of a certain FDE, the type FrameDescriptionEntry defines the method Cover, and also provides Begin and End to give the range of the FDE. In addition, it defines the method EstablishFrame, which uses a state machine to execute the instruction sequences in CIE and FDE to build all or part of the CFI table as needed, making it easy to calculate the CFA (Canonical Frame Address). With it, you can further calculate the return address of the called function. <br> With this return address, which is actually an instruction address, you can calculate the corresponding source code location (such as file name, line number, function name). By continuing to use this return address as an instruction address for iterative processing, you can calculate the complete call stack. <br><br> **Note: The begin and end in FDE describe the address range of the instruction sequence for creating, destroying the stack frame, and its existence period. See the DWARF v4 standard for details.** <br> In addition, the type FrameDescriptionEntries is defined, which is actually a slice of FDEs, just with some helper functions added, such as FDEForPC for querying the FDE containing a given instruction address. <br> Each function has an FDE, and the instructions of each function are arranged in the order defined, and there is no case where the instruction range of one function's FDE includes that of another function's FDE. |
| godwarf      | This package provides some basic functions. addr.go provides the parsing capability for .[z]debug_addr newly added in DWARF v5. <br> sections.go provides the ability to read debugging information from different file formats, such as GetDebugSectionElf, which can read the specified debugging section data from a given ELF file and automatically decompress the section data if it is compressed. <br> tree.go provides the ability to read the Tree composed of DIEs. If a compilation unit is not continuous, there will be multiple address ranges in Tree.Ranges. When determining whether the address range of a compilation unit contains a specified instruction address, you need to traverse Tree.Ranges for checking. The Tree.ContainsPC method simplifies this operation. The Tree.Type method also supports reading the type information corresponding to the current TreeNode. <br> type.go defines some types corresponding to Go data types, including basic data types BasicType and extended types such as CharType, UcharType, IntType, etc., as well as composite types such as StructType, SliceType, StringType, etc., and other types. These types are all stored in .[z]debug_info as DIEs. tree.go provides a very important function ReadType, which can read the type information defined at a specified offset from DWARF data, and establish the correspondence with Go data types through reflect.Kind in the corresponding type, so that variables can be easily created and assigned using Go's reflect package. |
| line         | Symbolic debugging is important for converting between instruction addresses and source file:line numbers. For example, when adding breakpoints to statements, you need to convert them to instruction address patches, or when stopping at a breakpoint, you should display the current source code location. The line number table is used to achieve this conversion. The line number table is encoded as a bytecode instruction stream and stored in .[z]debug_line. <br> Each compilation unit has a line number table, and the line number table data of different compilation units will eventually be merged by the linker. Each line number table has a fixed structure for parsing, such as the header field, followed by specific data. <br> line_parser.go provides the method ParseAll to parse all line number tables of compilation units in .[z]debug_line. The type DebugLines represents all line number tables, and each compilation unit's line number table corresponds to the type DebugLineInfo. A very important field in DebugLineInfo is the instruction sequence, which is also executed by a line number table state machine. The state machine is implemented in state_machine.go, and after execution, a complete line number table can be built. <br> With a complete line number table, you can look up the corresponding source line by PC. |
| loclist      | The location of an object in memory can be described by a location expression or a location list. If the location of an object may change during its lifetime, a location list is needed. Furthermore, if the storage of an object in memory is not a continuous segment but consists of multiple non-adjacent segments combined, a location list is also needed. <br> In DWARF v2~v4, location list information is stored in .[z]debug_loc, while in DWARF v5, it is stored in .[z]debug_loclist. The loclist package supports location lists in both the old (DWARF v2~v4) and new (DWARF v5) versions. <br> This package defines Dwarf2Reader and Dwarf5Reader for reading location lists from the raw data of the old and new versions, respectively. |
| op           | Looking at op.go, when discussing address expressions in DWARF, it was mentioned that address calculation is done by executing a stack-based program instruction list. The program instructions are all 1-byte opcodes, which are defined in this package. The required operands are in the stack, and each opcode has a corresponding function stackfn, which operates on the data in the stack when executed, takes operands, and pushes the result back onto the stack. The top element of the stack is the result. <br> opcodes.go defines a series of opcodes, opcode-to-name mappings, and the number of operands for each opcode. <br> registers.go defines the information of the register list concerned by DWARF as DwarfRegisters, and also provides some traversal methods, such as returning the register information corresponding to a given number, and returning the values of the current PC/SP/BP registers. |
| reader       | This package defines the type Reader, which embeds the dwarf.Reader from the Go standard library to read DIE information from .[z]debug_info. Each DIE is organized as a tree in DWARF, and each DIE corresponds to a dwarf.Entry, which includes the previously mentioned Tag and []Field (Field records Attr information), as well as the DIE's Offset and whether it contains child DIEs. <br> The Reader also defines some other functions such as Seek, SeekToEntry, AddrFor, SeekToType, NextType, SeekToTypeNamed, FindEntryNamed, InstructionsForEntryNamed, InstructionsForEntry, NextMemberVariable, NextPackageVariable, NextCompileUnit. <br> The package also defines the type Variable, which embeds the tree godwarf.Tree that describes a variable's DIE. It also provides the function Variables to extract the list of variables contained in a specified DIE tree. |
| regnum       | Defines the mapping between register numbers and register names, and provides functions for fast bidirectional lookup. |
| leb128       | Implements several utility functions: reading an int64 from a sleb128-encoded reader; reading a uint64 from a uleb128-encoded reader; writing an int64 to a writer with sleb128 encoding; writing a uint64 to a writer with uleb128 encoding. |
| dwarf        | Implements several utility functions: reading basic information (length, dwarf64, dwarf version, endianness) from DWARF data, reading the list of compilation units and their version information, reading DWARF strings from a buffer, reading Uint16, Uint32, Uint64 from a buffer with specified endianness, encoding a Uint32, Uint64 with specified endianness and writing to a buffer. |

`github.com/go-delve/delve/pkg/dwarf` accumulates delve's support for reading and writing DWARF data. Writing a complete DWARF parsing library by hand requires proficiency in the DWARF debugging information standard, as well as understanding the various adjustments made by the Go toolchain in the evolution from DWARF v4 to DWARF v5, which is a lot of work. To avoid making the learning process too tedious, we will not write a new DWARF support library by hand, but will reuse the implementation in go-delve/delve (possibly with some trimming and emphasis when necessary).

### DWARF Application

The relevant code for this section can be found here: https://github.com/hitzhangjie/codemaster/tree/master/dwarf/test.

#### ELF Reading DWARF

Read the DWARF-related debug sections from an ELF file and print the section names and data sizes:

```go
func Test_ElfReadDWARF(t *testing.T) {
	f, err := elf.Open("fixtures/elf_read_dwarf")
	assert.Nil(t, err)

	sections := []string{
		"abbrev",
		"line",
		"frame",
		"pubnames",
		"pubtypes",
		//"gdb_script",
		"info",
		"loc",
		"ranges",
	}

	for _, s := range sections {
		b, err := godwarf.GetDebugSection(f, s)
		assert.Nil(t, err)
		t.Logf(".[z]debug_%s data size: %d", s, len(b))
	}
}
```

fixtures/elf_read_dwarf is compiled from the following source program:

```go
package main

import "fmt"

func main() {
        fmt.Println("vim-go")
}
```

The result of running `go test -v` is as follows:

```bash
$ go test -v

=== RUN   Test_ElfReadDWARF
    dwarf_test.go:31: .[z]debug_abbrev data size: 486
    dwarf_test.go:31: .[z]debug_line data size: 193346
    dwarf_test.go:31: .[z]debug_frame data size: 96452
    dwarf_test.go:31: .[z]debug_pubnames data size: 13169
    dwarf_test.go:31: .[z]debug_pubtypes data size: 54135
    dwarf_test.go:31: .[z]debug_info data size: 450082
    dwarf_test.go:31: .[z]debug_loc data size: 316132
    dwarf_test.go:31: .[z]debug_ranges data size: 76144
--- PASS: Test_ElfReadDWARF (0.01s)
PASS
ok      github.com/hitzhangjie/codemaster/dwarf/test    0.015s

```

#### Reading Type Definitions

Still using the above elf_read_dwarf as an example, read all the types defined in it:

```go
func Test_DWARFReadTypes(t *testing.T) {
	f, err := elf.Open("fixtures/elf_read_dwarf")
	assert.Nil(t, err)

	dat, err := f.DWARF()
	assert.Nil(t, err)

	rd := reader.New(dat)

	for {
		e, err := rd.NextType()
		if err != nil {
			break
		}
		if e == nil {
			break
		}
		t.Logf("read type: %s", e.Val(dwarf.AttrName))
	}
}
```

The result of running `go test -run Test_DWARFReadTypes -v` is as follows:

```
$ go test -run Test_DWARFReadTypes -v

=== RUN   Test_DWARFReadTypes
    dwarf_test.go:54: read type: <unspecified>
    dwarf_test.go:54: read type: unsafe.Pointer
    dwarf_test.go:54: read type: uintptr
    dwarf_test.go:54: read type: runtime._type
    dwarf_test.go:54: read type: runtime._type
    dwarf_test.go:54: read type: uint32
    dwarf_test.go:54: read type: runtime.tflag
    dwarf_test.go:54: read type: uint8
    dwarf_test.go:54: read type: func(unsafe.Pointer, unsafe.Pointer) bool
    dwarf_test.go:54: read type: func(unsafe.Pointer, unsafe.Pointer) bool
    dwarf_test.go:54: read type: bool
    dwarf_test.go:54: read type: *bool
    dwarf_test.go:54: read type: *uint8
    dwarf_test.go:54: read type: runtime.nameOff
    dwarf_test.go:54: read type: runtime.typeOff
    ...
    dwarf_test.go:54: read type: waitq<int>
    dwarf_test.go:54: read type: *sudog<int>
    dwarf_test.go:54: read type: hchan<int>
    dwarf_test.go:54: read type: *hchan<int>
--- PASS: Test_DWARFReadTypes (0.06s)
PASS
ok      github.com/hitzhangjie/codemaster/dwarf/test    0.067s
```

Here, we did not display the type definition in which it was defined. If you want to get the source file, you need to combine the DIE of the compilation unit.

We added a custom type `type Student struct{}` in elf_read_dwarf.go and compiled it. Then we modified the test code:

```go
func Test_DWARFReadTypes2(t *testing.T) {
	f, err := elf.Open("fixtures/elf_read_dwarf")
	assert.Nil(t, err)

	dat, err := f.DWARF()
	assert.Nil(t, err)

	var cuName string
	var rd = reader.New(dat)
	for {
		entry, err := rd.Next()
		if err != nil {
			break
		}
		if entry == nil {
			break
		}

		switch entry.Tag {
		case dwarf.TagCompileUnit:
			cuName = entry.Val(dwarf.AttrName).(string)
			t.Logf("- CompilationUnit[%s]", cuName)
		case dwarf.TagArrayType,
			dwarf.TagBaseType,
			dwarf.TagClassType,
			dwarf.TagStructType,
			dwarf.TagUnionType,
			dwarf.TagConstType,
			dwarf.TagVolatileType,
			dwarf.TagRestrictType,
			dwarf.TagEnumerationType,
			dwarf.TagPointerType,
			dwarf.TagSubroutineType,
			dwarf.TagTypedef,
			dwarf.TagUnspecifiedType:
			t.Logf("  cu[%s] define [%s]", cuName, entry.Val(dwarf.AttrName))
		}
	}
}
```

The result of running `go test -run Test_DWARFReadTypes2` is as follows:

```bash
$ go test -run Test_DWARFReadTypes2
    dwarf_test.go:80: - CompilationUnit[sync]
    dwarf_test.go:80: - CompilationUnit[internal/cpu]
    dwarf_test.go:80: - CompilationUnit[runtime/internal/sys]
    dwarf_test.go:80: - CompilationUnit[fmt]
    dwarf_test.go:80: - CompilationUnit[runtime/internal/atomic]
    ...
    dwarf_test.go:94:   cu[runtime] define [fmt.Stringer]
    dwarf_test.go:94:   cu[runtime] define [main.Student]
    dwarf_test.go:94:   cu[runtime] define [[]strconv.leftCheat]
    ...
```

We can see that the output result shows that the type main.Student is defined in the compilation unit runtime, which is strange because the source code in the package main is named main.Student. The compilation unit may merge multiple go source files corresponding to target files, so this problem is easy to understand.

We can also locate the type DIE corresponding to the type name:

```go
func Test_DWARFReadTypes3(t *testing.T) {
	f, err := elf.Open("fixtures/elf_read_dwarf")
	assert.Nil(t, err)

	dat, err := f.DWARF()
	assert.Nil(t, err)

	var rd = reader.New(dat)

	entry, err := rd.SeekToTypeNamed("main.Student")
	assert.Nil(t, err)
	fmt.Println(entry)
}
```

The result of running the test command `go test -v -run Test_DWARFReadTypes3` is as follows:

```bash
go test -run Test_DWARFReadTypes3 -v

=== RUN   Test_DWARFReadTypes3
&{275081 StructType true [{Name main.Student ClassString} {ByteSize 0 ClassConstant} {Attr(10496) 25 ClassConstant} {Attr(10500) 59904 ClassAddress}]}
--- PASS: Test_DWARFReadTypes3 (0.02s)
PASS
ok      github.com/hitzhangjie/codemaster/dwarf/test    0.020s
```

The type information in the type information, we need to understand the DWARF how to describe data types related knowledge slowly. Don't worry, we will still encounter this knowledge later, when we will explain it again in conjunction with related knowledge.

#### Reading Variable Definitions

Now reading variable definitions is not difficult for us, we can look at an example:

```go
package main

import "fmt"

type Student struct{}

func main() {
    s := Student{}
    fmt.Println(s)
}
```

Now we try to get the information about the variable s in the above main:

```go
func Test_DWARFReadVariable(t *testing.T) {
	f, err := elf.Open("fixtures/elf_read_dwarf")
	assert.Nil(t, err)

	dat, err := f.DWARF()
	assert.Nil(t, err)

	var rd = reader.New(dat)
	for {
		entry, err := rd.Next()
		if err != nil {
			break
		}
		if entry == nil {
			break
		}
		// 只查看变量
		if entry.Tag != dwarf.TagVariable {
			continue
		}
		// 只查看变量名为s的变量
		if entry.Val(dwarf.AttrName) != "s" {
			continue
		}
		// 通过offset限制，只查看main.main中定义的变量名为s的变量
        // 这里的0x432b9是结合`objdump --dwarf=info`中的结果来硬编码的
		if entry.Val(dwarf.AttrType).(dwarf.Offset) != dwarf.Offset(0x432b9) {
			continue
		}

		// 查看变量s的DIE
		fmt.Println("found the variable[s]")
		fmt.Println("DIE variable:", entry)

		// 查看变量s对应的类型的DIE
		ee, err := rd.SeekToType(entry, true, true)
		assert.Nil(t, err)
		fmt.Println("DIE type:", ee)

		// 查看变量s对应的地址 [lowpc, highpc, instruction]
		fmt.Println("location:", entry.Val(dwarf.AttrLocation))
  
		// 最后在手动校验下main.Student的类型与上面看到的变量的类型是否一致
		// 应该满足：main.Student DIE的位置 == 变量的类型的位置偏移量
		typeEntry, err := rd.SeekToTypeNamed("main.Student")
		assert.Nil(t, err)
		assert.Equal(t, typeEntry.Val(dwarf.AttrType), variableTypeEntry.Offset)
		break
	}
}
```

We looked at the DIE of the variable, the DIE of the corresponding type, and the memory address of the variable. Running `go test -run Test_DWARFReadVariable -v` to view the result:

```bash
$ go test -run Test_DWARFReadVariable -v

=== RUN   Test_DWARFReadVariable
found the variable[s]
DIE variable: &{324895 Variable false [{Name s ClassString} {DeclLine 11 ClassConstant} {Type 275129 ClassReference} {Location [145 168 127] ClassExprLoc}]}
DIE type: &{275081 StructType true [{Name main.Student ClassString} {ByteSize 24 ClassConstant} {Attr(10496) 25 ClassConstant} {Attr(10500) 74624 ClassAddress}]}
location: [145 168 127]
--- PASS: Test_DWARFReadVariable (0.02s)
PASS
ok      github.com/hitzhangjie/codemaster/dwarf/test    0.023s

```

Note that at the end of the test case, we also verified the position offset of the type definition of the variable `s:=main.Student{}` with the position of the type `main.Student` defined.

#### Reading Function Definitions

Now let's read the function, method, and anonymous function definitions in the program:

```go
func Test_DWARFReadFunc(t *testing.T) {
	f, err := elf.Open("fixtures/elf_read_dwarf")
	assert.Nil(t, err)

	dat, err := f.DWARF()
	assert.Nil(t, err)

	rd := reader.New(dat)
	for {
		die, err := rd.Next()
		if err != nil {
			break
		}
		if die == nil {
			break
		}
		if die.Tag == dwarf.TagSubprogram {
			fmt.Println(die)
		}
	}
}
```

Running the command `go test -v -run Test_DWARFReadFunc` to test, we see that some functions are defined in the program, including the function main.main in our main package.

```bash
$ go test -v -run Test_DWARFReadFunc

=== RUN   Test_DWARFReadFunc
&{73 Subprogram true [{Name sync.newEntry ClassString} {Lowpc 4725024 ClassAddress} {Highpc 4725221 ClassAddress} {FrameBase [156] ClassExprLoc} {DeclFile 3 ClassConstant} {External true ClassFlag}]}
&{149 Subprogram true [{Name sync.(*Map).Load ClassString} {Lowpc 4725248 ClassAddress} {Highpc 4726474 ClassAddress} {FrameBase [156] ClassExprLoc} {DeclFile 3 ClassConstant} {External true ClassFlag}]}
&{272 Subprogram true [{Name sync.(*entry).load ClassString} {Lowpc 4726496 ClassAddress} {Highpc 4726652 ClassAddress} {FrameBase [156] ClassExprLoc} {DeclFile 3 ClassConstant} {External true ClassFlag}]}
&{368 Subprogram true [{Name sync.(*Map).Store ClassString} {Lowpc 4726656 ClassAddress} {Highpc 4728377 ClassAddress} {FrameBase [156] ClassExprLoc} {DeclFile 3 ClassConstant} {External true ClassFlag}]}
...
&{324861 Subprogram true [{Name main.main ClassString} {Lowpc 4949568 ClassAddress} {Highpc 4949836 ClassAddress} {FrameBase [156] ClassExprLoc} {DeclFile 2 ClassConstant} {External true ClassFlag}]}
...
&{450220 Subprogram true [{Name reflect.methodValueCall ClassString} {Lowpc 4856000 ClassAddress} {Highpc 4856091 ClassAddress} {FrameBase [156] ClassExprLoc} {DeclFile 1 ClassConstant} {External true ClassFlag}]}
--- PASS: Test_DWARFReadFunc (41.67s)
PASS
ok      github.com/hitzhangjie/codemaster/dwarf/test    41.679s
```

In addition to the tag DW_TAG_subprogram DIE in the go program, DW_TAG_subroutine_type, DW_TAG_inlined_subroutine_type, DW_TAG_inlined_subroutine are also related. We will expand on this later.

#### Reading Line Number Table Information

Now let's try to read the line number table information in the program:

```go
func Test_DWARFReadLineNoTable(t *testing.T) {
	f, err := elf.Open("fixtures/elf_read_dwarf")
	assert.Nil(t, err)

	dat, err := godwarf.GetDebugSection(f, "line")
	assert.Nil(t, err)

	lineToPCs := map[int][]uint64{10: nil, 12: nil, 13: nil, 14: nil, 15: nil}

	debuglines := line.ParseAll(dat, nil, nil, 0, true, 8)
	fmt.Println(len(debuglines))
	for _, line := range debuglines {
		//fmt.Printf("idx-%d\tinst:%v\n", line.Instructions)
		line.AllPCsForFileLines("/root/dwarftest/dwarf/test/fixtures/elf_read_dwarf.go", lineToPCs)
	}

	for line, pcs := range lineToPCs {
		fmt.Printf("lineNo:[elf_read_dwarf.go:%d] -> PC:%#x\n", line, pcs)
	}
}
```

We first read the test program fixtures/elf_read_dwarf, then extract the .[z]debug_line section from it, and then call `line.ParseAll(...)` to parse the data in .[z]debug_line. This function only parses the line number table preface and reads out the line number table bytecode instruction, it does not actually execute the bytecode instruction to build the line number table.

When does the line number table build? When we query it as needed, line.DebugLines inside will execute the bytecode instruction through the internal state machine to complete the virtual line number table.

In the above test file fixtures/elf_read_dwarf, the corresponding go source file is:

```go
1:package main
2:
3:import "fmt"
4:
5:type Student struct {
6:    Name string
7:    Age  int
8:}
9:
10:type Print func(s string, vals ...interface{})
11:
12:func main() {
13:    s := Student{}
14:    fmt.Println(s)
15:}
```

We take the above source file's lines 10, 12, 13, 14, 15 to query their corresponding PC values. The `line.AllPCsForFileLines` will help complete this operation and store the result in the map passed in. Then we print out this map.

Running the test command `go test -run Test_DWARFReadLineNoTable -v`, the result is as follows:

```bash
$ go test -run Test_DWARFReadLineNoTable -v

=== RUN   Test_DWARFReadLineNoTable
41
lineNo:[elf_read_dwarf.go:12] -> PC:[0x4b8640 0x4b8658 0x4b8742]
lineNo:[elf_read_dwarf.go:13] -> PC:[0x4b866f]
lineNo:[elf_read_dwarf.go:14] -> PC:[0x4b8680 0x4b86c0]
lineNo:[elf_read_dwarf.go:15] -> PC:[0x4b8729]
lineNo:[elf_read_dwarf.go:10] -> PC:[]
--- PASS: Test_DWARFReadLineNoTable (0.00s)
PASS

Process finished with the exit code 0
```

We can see that the lineno in the source code is mapped to the corresponding PC slice, because a source code statement may correspond to multiple machine instructions, and the instruction address is naturally multiple, which is easy to understand, and we don't delve into it.

However, according to our previous understanding of the line number table design, each lineno should only retain one instruction address, why are there multiple PC values here?

We first disassemble to see what is at the above elf_read_dwarf.go:12, and search for the corresponding instruction position in the figure (marked with symbols >).

```bash
func main() {
> 4b8640:       64 48 8b 0c 25 f8 ff    mov    %fs:0xfffffffffffffff8,%rcx
  4b8647:       ff ff 
  4b8649:       48 8d 44 24 e8          lea    -0x18(%rsp),%rax
  4b864e:       48 3b 41 10             cmp    0x10(%rcx),%rax
  4b8652:       0f 86 ea 00 00 00       jbe    4b8742 <main.main+0x102>
> 4b8658:       48 81 ec 98 00 00 00    sub    $0x98,%rsp
  4b865f:       48 89 ac 24 90 00 00    mov    %rbp,0x90(%rsp)
  4b8666:       00 
  4b8667:       48 8d ac 24 90 00 00    lea    0x90(%rsp),%rbp
  4b866e:       00 
        s := Student{}
  4b866f:       0f 57 c0                xorps  %xmm0,%xmm0
  4b8672:       0f 11 44 24 48          movups %xmm0,0x48(%rsp)
  4b8677:       48 c7 44 24 58 00 00    movq   $0x0,0x58(%rsp)
  4b867e:       00 00 
        fmt.Println(s)
  4b8680:       0f 57 c0                xorps  %xmm0,%xmm0
  ...
  ...
  4b873e:       66 90                   xchg   %ax,%ax
  4b8740:       eb ac                   jmp    4b86ee <main.main+0xae>
func main() {
> 4b8742:       e8 b9 36 fb ff          callq  46be00 <runtime.morestack_noctxt>
  4b8747:       e9 f4 fe ff ff          jmpq   4b8640 <main.main>
  4b874c:       cc                      int3   
  4b874d:       cc                      int3 
```

These instruction addresses are indeed special:

- 0x4b8640, this address is the entry address of the function;
- 0x4b8742, this address corresponds to the position of runtime.morestack_noctxt, for those who are familiar with go goroutine stack, this function will check whether the stack frame needs to be expanded;
- 0x4b8658, this address is the stack frame allocation action after the stack frame is expanded as needed;

Although these addresses are special and seem important, why are they related to 3 PC values? We continue to look at elf_read_dwarf.go:14 and search for the corresponding instruction position (marked with symbols > in the figure).

```bash
        fmt.Println(s)
> 4b8680:       0f 57 c0                xorps  %xmm0,%xmm0
  4b8683:       0f 11 44 24 78          movups %xmm0,0x78(%rsp)
  4b8688:       48 c7 84 24 88 00 00    movq   $0x0,0x88(%rsp)
  4b868f:       00 00 00 00 00 
  4b8694:       0f 57 c0                xorps  %xmm0,%xmm0
  4b8697:       0f 11 44 24 38          movups %xmm0,0x38(%rsp)
  4b869c:       48 8d 44 24 38          lea    0x38(%rsp),%rax
  4b86a1:       48 89 44 24 30          mov    %rax,0x30(%rsp)
  4b86a6:       48 8d 05 d3 2c 01 00    lea    0x12cd3(%rip),%rax        # 4cb380 <type.*+0x12380>
  4b86ad:       48 89 04 24             mov    %rax,(%rsp)
  4b86b1:       48 8d 44 24 78          lea    0x78(%rsp),%rax
  4b86b6:       48 89 44 24 08          mov    %rax,0x8(%rsp)
  4b86bb:       0f 1f 44 00 00          nopl   0x0(%rax,%rax,1)
> 4b86c0:       e8 3b 27 f5 ff          callq  40ae00 <runtime.convT2E>
  4b86c5:       48 8b 44 24 30          mov    0x30(%rsp),%rax
  4b86ca:       84 00                   test   %al,(%rax)

```

Let's look at these two instruction addresses:

- 0x4b8680, this address is the instruction that prepares to call the function fmt.Println(s) before the call;
- 0x4b86c0, this address is the instruction that prepares to call the runtime function runtime.convT2E, which should convert the string variable s to eface, and then pass it to fmt.Println to print;

So, the analysis shows that a lineno may correspond to multiple PC values, which is not a big problem. We can use any one of them as a breakpoint to set, which seems reasonable, but why are there multiple PC values?

- Is this a bug? I don't think so. I think this is intentional by the go compiler and linker.
- Why is this generated? First, it can be confirmed that `line.AllPCsForFileLines` has already been the lineno to PC slice mapping calculated based on the line number table bytecode instruction. The result calculated is not necessarily all lineno to PC values. In this case, consider why there are multiple PC. Assuming we want to analyze the program more thoroughly, in addition to the user program, there may also be go runtime details, such as runtime.convT2E, runtime.morestack_noctxt, if the compiler and linker know that there are such bytecode instructions in the generated DWARF, and intentionally let the same lineno correspond to multiple PC, I think it is only possible to facilitate more fine-grained debugging, allowing the debugger not only to debug the user code but also to debug the go runtime itself.

About line number table reading and explanation is first to this, we will further expand on it when we use it.

#### Reading CFI Table Information

Next, let's read the CFI (Call Frame Information) table:

```go
func Test_DWARFReadCFITable(t *testing.T) {
	f, err := elf.Open("fixtures/elf_read_dwarf")
	assert.Nil(t, err)

	// 解析.[z]debug_frame中CFI信息表
	dat, err := godwarf.GetDebugSection(f, "frame")
	assert.Nil(t, err)
	fdes, err := frame.Parse(dat, binary.LittleEndian, 0, 8, 0)
	assert.Nil(t, err)
	assert.NotEmpty(t, fdes)

	//for idx, fde := range fdes {
	//	fmt.Printf("fde[%d], begin:%#x, end:%#x\n", idx, fde.Begin(), fde.End())
	//}

	for _, fde := range fdes {
		if !fde.Cover(0x4b8640) {
			continue
		}
		fmt.Printf("address 0x4b8640 is covered in FDE[%#x,%#x]\n", fde.Begin(), fde.End())
		fc := fde.EstablishFrame(0x4b8640)
		fmt.Printf("retAddReg: %s\n", regnum.AMD64ToName(fc.RetAddrReg))
		switch fc.CFA.Rule {
		case frame.RuleCFA:
			fmt.Printf("cfa: rule:RuleCFA, CFA=(%s)+%#x\n", regnum.ARM64ToName(fc.CFA.Reg), fc.CFA.Offset)
		default:
		}
	}
}
```
First, we read the .[z]debug_frame section from the elf file, then use the `frame.Parse(...)` method to complete parsing of the CFI information table. The parsed data is stored in the variable fdes of type `FrameDescriptionEntries`, which is actually `type FrameDescriptionEntries []*FrameDescriptionEntry`, but with some convenient methods added to this type, such as the commonly used `FDEForPC(pc)` which returns the FDE whose instruction address range contains the given pc.

We can iterate through fdes to print out the instruction address range of each fde.

When reading the line number table information, we learned that address 0x4b8640 is the entry address for main.main. Let's use this instruction for further testing. We iterate through all FDEs to check which FDE's instruction address range contains the main.main entry instruction 0x4b8640.

> ps: Actually, this iteration + fde.Cover(pc) could be replaced by fdes.FDEForPC, but we're showing here that FrameDescriptionEntry provides the Cover method.

When found, we check to calculate the CFA (Canonical Frame Address) corresponding to the current pc 0x4b8640. In case the concept of CFA is unclear, let's explain it again:

> **DWARFv5 Call Frame Information L8:L12**:
>
> An area of memory that is allocated on a stack called a "call frame." The call frame is identified by an address on the stack. We refer to this address as the Canonical Frame Address or CFA. Typically, the CFA is defined to be the value of the stack pointer at the call site in the previous frame (which may be different from its value on entry to the current frame).

With this CFA, we can find the stack frame corresponding to the current pc and the caller's stack frame, and the caller's caller's stack frame... Each function call's corresponding stack frame contains a return address, which is actually an instruction address. Using the line number table, we can map instruction addresses to file names and line numbers in the source code, allowing us to intuitively display the call stack information for the current pc.

Of course, the CFI information table provides more than just CFA calculation. It also records the effects of instruction execution on other registers, so it can display register values in different stack frames. By walking through different stack frames, we can also see the values of local variables defined in the stack frames.

We'll keep the introduction to CFI usage brief for now, and explain further when implementing symbolic debugging later.

### Section Summary

In this section, we introduced some DWARF support in `github.com/go-delve/delve/pkg/dwarf`, then wrote some test cases using these packages to test reading type definitions, variables, function definitions, line number tables, and call stack information tables. Through writing these test cases, we deepened our understanding of DWARF parsing and application.
