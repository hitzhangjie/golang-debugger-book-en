## Viewing Process State (Memory)

### Implementation Goal: pmem Memory Data Reading

In this section, we will implement the pmem command to facilitate viewing process memory data during debugging.

### Basic Knowledge

We know that data in memory is a sequence of 0s and 1s. To correctly display memory data, we need to pay attention to these basic considerations:

- The sequence of 0s and 1s is not the final form; data has types, and we need to interpret the data in memory according to its data type;
- Data storage in different machines has byte order: little-endian (lower bits at lower addresses) or big-endian (lower bits at higher addresses);

pmem reads a segment of data starting from a specified memory address, groups it into integers according to the specified number of bytes, and prints it in binary, octal, decimal, or hexadecimal format. Unlike the common variable viewing operation `print <var>`, it doesn't consider what data type the data at the specified location is (such as a `struct{...}`, `slice`, or `map`). pmem is similar to the `x/fmt` operation in gdb.

To view process memory data, we need to use the `ptrace(PTRACE_PEEKDATA,...)` operation to read the memory data of the debugged process.

### Code Implementation

#### Step 1: Implement Process Memory Data Reading

First, we implement memory data reading through the `ptrace(PTRACE_PEEKDATA,...)` system call. The amount of data read each time can be calculated from count and size:

- size represents how many bytes each data item to be read and displayed includes;
- count represents how many such data items to read and display consecutively;

For example, an int data item might contain 4 bytes, and to display 8 int numbers, you would specify `-size=4 -count=8`.

The following program reads memory data and prints the read byte data in hexadecimal format.

**file: cmd/debug/pmem.go**

```go
package debug

import (
	"errors"
	"fmt"
	"strconv"
	"syscall"

	"github.com/spf13/cobra"
)

var pmemCmd = &cobra.Command{
	Use:   "pmem ",
	Short: "Print memory data",
	Annotations: map[string]string{
		cmdGroupKey: cmdGroupInfo,
	},
	RunE: func(cmd *cobra.Command, args []string) error {

		count, _ := cmd.Flags().GetUint("count")
		format, _ := cmd.Flags().GetString("fmt")
		size, _ := cmd.Flags().GetUint("size")
		addr, _ := cmd.Flags().GetString("addr")

		// check params
		err := checkPmemArgs(count, format, size, addr)
		if err != nil {
			return err
		}

		// calculate size of memory to read
		readAt, _ := strconv.ParseUint(addr, 0, 64)
		bytes := count * size

		buf := make([]byte, bytes, bytes)
		n, err := syscall.PtracePeekData(TraceePID, uintptr(readAt), buf)
		if err != nil || n != int(bytes) {
			return fmt.Errorf("read %d bytes, error: %v", n, err)
		}

		// print result
		fmt.Printf("read %d bytes ok:", n)
		for _, b := range buf[:n] {
			fmt.Printf("%x", b)
		}
		fmt.Println()

		return nil
	},
}

func init() {
	debugRootCmd.AddCommand(pmemCmd)
	// Similar to gdb's x/FMT command, where FMT=repeat number+format modifier+size
	pmemCmd.Flags().Uint("count", 16, "Number of values to view")
	pmemCmd.Flags().String("fmt", "hex", "Value print format: b(binary), o(octal), x(hex), d(decimal), ud(unsigned decimal)")
	pmemCmd.Flags().Uint("size", 4, "Bytes per value")
	pmemCmd.Flags().String("addr", "", "Memory address to read")
}

func checkPmemArgs(count uint, format string, size uint, addr string) error {
	if count == 0 {
		return errors.New("invalid count")
	}
	if size == 0 {
		return errors.New("invalid size")
	}
	formats := map[string]struct{}{
		"b":  {},
		"o":  {},
		"x":  {},
		"d":  {},
		"ud": {},
	}
	if _, ok := formats[format]; !ok {
		return errors.New("invalid format")
	}
	// TODO make it compatible
	_, err := strconv.ParseUint(addr, 0, 64)
	return err
}
```

#### Step 2: Determine Byte Order and Value Parsing

```go
// Check if the system is little-endian
func isLittleEndian() bool {
	buf := [2]byte{}
	*(*uint16)(unsafe.Pointer(&buf[0])) = uint16(0xABCD)

	switch buf {
	case [2]byte{0xCD, 0xAB}:
		return true
	case [2]byte{0xAB, 0xCD}:
		return false
	default:
		panic("Could not determine native endianness.")
	}
}

// Convert byte slice to uint64 value, considering byte order
func byteArrayToUInt64(buf []byte, isLittleEndian bool) uint64 {
	var n uint64
	if isLittleEndian {
		for i := len(buf) - 1; i >= 0; i-- {
			n = n<<8 + uint64(buf[i])
		}
	} else {
		for i := 0; i < len(buf); i++ {
			n = n<<8 + uint64(buf[i])
		}
	}
	return n
}
```

#### Step 3: Implement Data "Type" Parsing

The data read from memory should be grouped and parsed according to the number of bytes per data item `-size` and the display format `-fmt`. We also need to consider the terminal column width issues when displaying binary, octal, decimal, and hexadecimal numbers. With limited columns per line, the number of numbers that can be displayed per line varies depending on the number system used.

```go
package debug
...

var pmemCmd = &cobra.Command{
	Use:   "pmem ",
	Short: "Print memory data",
	Annotations: map[string]string{
		cmdGroupKey: cmdGroupInfo,
	},
	RunE: func(cmd *cobra.Command, args []string) error {
		...
  
		// This function prints data with beautiful tab+padding alignment
		s := prettyPrintMem(uintptr(readAt), buf, isLittleEndian(), format[0], int(size))
		fmt.Println(s)

		return nil
	},
}

...

// prettyPrintMem uses tabwriter to control alignment.
//
// Note that after appropriate formatting for binary, octal, decimal, and hexadecimal display,
// the output will look more aesthetically pleasing
func prettyPrintMem(address uintptr, memArea []byte, littleEndian bool, format byte, size int) string {

	var (
		cols      int 		// Number of columns per line for different number systems (e.g., cols=4, 1 2 3 4)
		colFormat string 	// Format for each column number in different number systems (e.g., %08b, 00000001)
		colBytes  = size    // Bytes per column number (e.g., 2, needs 2 bytes, considering byte order)

		addrLen int
		addrFmt string
	)

	switch format {
	case 'b':
		cols = 4 // Avoid emitting rows that are too long when using binary format
		colFormat = fmt.Sprintf("%%0%db", colBytes*8)
	case 'o':
		cols = 8
		colFormat = fmt.Sprintf("0%%0%do", colBytes*3) // Always keep one leading zero for octal.
	case 'd':
		cols = 8
		colFormat = fmt.Sprintf("%%0%dd", colBytes*3)
	case 'x':
		cols = 8
		colFormat = fmt.Sprintf("0x%%0%dx", colBytes*2) // Always keep one leading '0x' for hex.
	default:
		return fmt.Sprintf("not supprted format %q\n", string(format))
	}
	colFormat += "\t"

	// the number of rows to print
	l := len(memArea)
	rows := l / (cols * colBytes)
	if l%(cols*colBytes) != 0 {
		rows++
	}

	// We should print memory address in the beginnning of every line.
	// And we should use fixed length bytes to print the address for 
	// better readability.
	if l != 0 {
		addrLen = len(fmt.Sprintf("%x", uint64(address)+uint64(l)))
	}
	addrFmt = "0x%0" + strconv.Itoa(addrLen) + "x:\t"

	// use tabwriter to print lines with columns aligned vertically.
	var b strings.Builder
	w := tabwriter.NewWriter(&b, 0, 0, 3, ' ', 0)

	for i := 0; i < rows; i++ {
		fmt.Fprintf(w, addrFmt, address)

		for j := 0; j < cols; j++ {
			offset := i*(cols*colBytes) + j*colBytes
			if offset+colBytes <= len(memArea) {
				n := byteArrayToUInt64(memArea[offset:offset+colBytes], littleEndian)
				fmt.Fprintf(w, colFormat, n)
			}
		}
		fmt.Fprintln(w, "")
		address += uintptr(cols)
	}
	w.Flush()
	return b.String()
}



```

Read file: book/6-develop-inst-debugger/12-pmem.md
Here is the English translation for the remainder of `12-pmem.md`, maintaining the structure, formatting, and technical accuracy:

---

The above code keeps the memory reading logic unchanged, but mainly adds two parts:

- Correctly parses the data read from memory according to the machine's endianness and converts it into the corresponding value;
- Formats the value according to the display base (binary, octal, decimal, hexadecimal), and uses `tabwriter` for tab+padding alignment to output the result more aesthetically;

With this, the development of the `pmem` command is basically complete. Let's test the execution of `pmem`.

### Code Testing

#### Test: Memory Data Reading

First, run a test program to get its pid, then run `godbg attach <pid>` to trace the target process. Once the debug session is ready, use `disass` to check the disassembly. You will see many `int3` instructions, whose corresponding byte data is `0xCC`. We can read one byte at the address of such an instruction to quickly verify if `pmem` works correctly.

```bash
$ godbg attach 7764
process 7764 attached succ
process 7764 stopped: true
godbg> disass
0x4651e0 mov %eax,0x20(%rsp)
0x4651e4 retq
0x4651e5 int3
0x4651e6 int3
0x4651e7 int3
0x4651e8 int3
0x4651e9 int3
0x4651ea int3
0x4651eb int3
0x4651ec int3
godbg> pmem --addr 0x4651e5 --count 1 --fmt x --size 1
read 1 bytes ok:cc
godbg> pmem --addr 0x4651e5 --count 4 --fmt x --size 1
read 4 bytes ok:cccccccc
godbg> 
```

As you can see, the program first reads 1 byte from address 0x4561e5, which is the hexadecimal 0xCC for one `int3` instruction, and then reads 4 bytes from the same address, which are four consecutive `int3` instructions corresponding to 0xCCCCCCCC.

The results are as expected, indicating that the basic memory data reading function of `pmem` works correctly.

#### Test: Data "Type" Parsing

View hexadecimal numbers, each as 1 byte or 2 bytes, note the little-endian byte order:

```bash
godbg> pmem --addr 0x464fc3 --count 16 --fmt x --size 1
read 16 bytes ok:
0x464fc3:   0x89   0x44   0x24   0x30   0xc3   0xcc   0xcc   0xcc   
0x464fcb:   0xcc   0xcc   0xcc   0xcc   0xcc   0xcc   0xcc   0xcc   

godbg> pmem --addr 0x464fc3 --count 16 --fmt x --size 2
read 32 bytes ok:
0x464fc3:   0x4489   0x3024   0xccc3   0xcccc   0xcccc   0xcccc   0xcccc   0xcccc   
0x464fcb:   0xcccc   0xcccc   0xcccc   0xcccc   0xcccc   0xcccc   0x8bcc   0x247c 
```

View octal numbers, each as 1 byte or 2 bytes, note the little-endian byte order:

```bash
godbg> pmem --addr 0x464fc3 --count 16 --fmt o --size 1
read 16 bytes ok:
0x464fc3:   0211   0104   0044   0060   0303   0314   0314   0314   
0x464fcb:   0314   0314   0314   0314   0314   0314   0314   0314   

godbg> pmem --addr 0x464fc3 --count 16 --fmt o --size 2
read 32 bytes ok:
0x464fc3:   0042211   0030044   0146303   0146314   0146314   0146314   0146314   0146314   
0x464fcb:   0146314   0146314   0146314   0146314   0146314   0146314   0105714   0022174
```

View binary numbers, each as 1 byte or 2 bytes, note the little-endian byte order:

```bash
godbg> pmem --addr 0x464fc3 --count 16 --fmt b --size 1
read 16 bytes ok:
0x464fc3:   10001001   01000100   00100100   00110000   
0x464fc7:   11000011   11001100   11001100   11001100   
0x464fcb:   11001100   11001100   11001100   11001100   
0x464fcf:   11001100   11001100   11001100   11001100   

godbg> pmem --addr 0x464fc3 --count 16 --fmt b --size 2
read 32 bytes ok:
0x464fc3:   0100010010001001   0011000000100100   1100110011000011   1100110011001100   
0x464fc7:   1100110011001100   1100110011001100   1100110011001100   1100110011001100   
0x464fcb:   1100110011001100   1100110011001100   1100110011001100   1100110011001100   
0x464fcf:   1100110011001100   1100110011001100   1000101111001100   0010010001111100 
```

Finally, view decimal numbers, each as 1 byte or 2 bytes, note the little-endian byte order:

```bash
godbg> pmem --addr 0x464fc3 --count 16 --fmt d --size 1
read 16 bytes ok:
0x464fc3:   137   068   036   048   195   204   204   204   
0x464fcb:   204   204   204   204   204   204   204   204   

godbg> pmem --addr 0x464fc3 --count 16 --fmt d --size 2
read 32 bytes ok:
0x464fc3:   017545   012324   052419   052428   052428   052428   052428   052428   
0x464fcb:   052428   052428   052428   052428   052428   052428   035788   009340 
```

The `pmem` command can now correctly parse memory data of different formats, sizes, and endianness.

The results are as expected, indicating that the data reading, parsing, and display functions of `pmem` all work correctly.

> ps: The logic of `prettyPrintMem` here is actually taken from the `examinemem(x)` command contributed to `go-delve/delve`. If you are interested in data conversion caused by endianness, you can verify the correctness of the data, and it may be more convenient to check with hexadecimal data.

### Summary

This article introduced how to read data from a specified memory address, how to efficiently determine machine endianness, how to parse values under different endianness, and how to format and display them in different number systems. Here, we also used the handy `tabwriter` package from the Go standard library, which supports column-aligned output, making the output clearer and easier to read.

In the subsequent symbol-level debugging section, we will also need to implement the function of printing arbitrary variable values. After reading memory data, we will need other techniques to help parse it into the corresponding data types in high-level languages. Next, let's see how to read register-related data.