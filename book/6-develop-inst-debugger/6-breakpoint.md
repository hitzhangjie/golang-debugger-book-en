## Dynamic Breakpoints

### Implementation Goal: Adding Breakpoints

Breakpoints can be classified by their "**lifecycle**" into "**static breakpoints**" and "**dynamic breakpoints**".

- Static breakpoints have a lifecycle that spans the entire program execution. They are typically implemented by executing the instruction `int 0x3h` to forcibly insert `0xCC` as a breakpoint. Their implementation is simple, and breakpoints can be inserted during coding, but they lack flexibility;
- Dynamic breakpoints are generated and removed through runtime instruction patching. Their lifecycle is related to operations during debugging activities, with their biggest characteristic being flexibility. They can generally only be generated through a debugger.

Whether static or dynamic, breakpoints work on a similar principle - they both use the one-byte instruction `0xCC` to pause task execution. After the processor executes `0xCC`, it will pause the current task execution.

> ps: In Chapter 4.2, we mentioned how `int 0x3h` (encoded as instruction 0xCC) works. If readers have forgotten its working principle, they can refer to the relevant chapter.

Breakpoints can also be subdivided by their "**implementation method**" into "**software breakpoints**" and "**hardware breakpoints**".

- Hardware breakpoints are typically implemented using hardware-specific debug ports, such as writing the address of the instruction of interest to a debug port (register). When the PC hits this address, it triggers the operation to stop tracee execution and notifies the tracer;
- Software breakpoints are relative to hardware breakpoints. If a breakpoint implementation doesn't rely on hardware debug ports, it can generally be classified as a software breakpoint.

We'll focus only on software breakpoints and specifically dynamic breakpoints. Adding and removing breakpoints is the foundation of the debugging process. After mastering how to add and remove breakpoints at specific addresses, we can study breakpoint applications such as step, next, continue, etc.

After becoming proficient with these operations, we will combine DWARF in later chapters to implement symbol-level breakpoints, which will allow you to add and remove breakpoints at statement lines, functions, and branch controls, further highlighting the value of breakpoints.

### Code Implementation

We use the `break` command to add breakpoints, which can be abbreviated as `b`. The usage is as follows:

```bash
# Note the format of <locspec>
break <locspec>
```

locspec represents a location in the code, which can be an instruction address or a location in a source file. For the latter, we need to query the line number table to convert the source code location into an instruction address. With the instruction address, we can patch the instruction data at that address to add or remove breakpoints.

In this chapter, we'll only consider cases where locspec is an instruction address.

> The formats supported by locspec directly affect the efficiency of adding breakpoints. Delve defines a series of locspec formats. If interested, you can refer to Delve's implementation: https://sourcegraph.com/github.com/go-delve/delve@master/-/blob/pkg/locspec/locations.go

Now let's look at our implementation code:

```go
package debug

import (
	"errors"
	"fmt"
	"strconv"
	"strings"
	"syscall"

	"github.com/spf13/cobra"
)

var breakCmd = &cobra.Command{
	Use:   "break <locspec>",
	Short: "Add breakpoint in source code",
	Long: `Add breakpoint in source code, source location can be specified through locspec format.

Currently supported locspec formats include:
- Instruction address
- [filename:]line number
- [filename:]function name`,
	Aliases: []string{"b", "breakpoint"},
	Annotations: map[string]string{
		cmdGroupKey: cmdGroupBreakpoints,
	},
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Printf("break %s\n", strings.Join(args, " "))

		if len(args) != 1 {
			return errors.New("invalid parameters")
		}

		locStr := args[0]
		addr, err := strconv.ParseUint(locStr, 0, 64)
		if err != nil {
			return fmt.Errorf("invalid locspec: %v", err)
		}

    // Record the original 1-byte data at address addr
		orig := [1]byte{}
		n, err := syscall.PtracePeekData(TraceePID, uintptr(addr), orig[:])
		if err != nil || n != 1 {
			return fmt.Errorf("peek text, %d bytes, error: %v", n, err)
		}
		breakpointsOrigDat[uintptr(addr)] = orig[0]

    // Overwrite the one-byte data at addr with 0xCC
		n, err = syscall.PtracePokeText(TraceePID, uintptr(addr), []byte{0xCC})
		if err != nil || n != 1 {
			return fmt.Errorf("poke text, %d bytes, error: %v", n, err)
		}
		fmt.Printf("Breakpoint added successfully\n")
		return nil
	},
}

func init() {
	debugRootCmd.AddCommand(breakCmd)
}
```

The implementation logic here is not complex. Let's go through it.

First, we assume the user input is an instruction address, which can be obtained by viewing the disassembly with the disass command. We first try to convert this instruction address string into a uint64 value. If it fails, we consider it an invalid address.

If the address is valid, we try to read one byte of data starting at the instruction address through the system call `syscall.PtracePeekData(pid, addr, buf)`. This data is the first byte of the encoded assembly instruction. We need to temporarily store it, then write the instruction `0xCC` through `syscall.PtracePokeData(pid, addr, buf)`.

When we're ready to end the debugging session, or when executing `clear` to remove the breakpoint, we need to restore the 0xCC here to the original data.

ps: Under Linux, PEEKDATA, PEEKTEXT, POKEDATA, POKETEXT have the same effect, see `man 2 ptrace`:

```bash
$ man 2 ptrace

PTRACE_PEEKTEXT, PTRACE_PEEKDATA
    Read  a  word  at  the address addr in the tracee's memory, returning the word as the result of the ptrace() call.  
    Linux does not have separate text and data address spaces, so these two requests are currently equivalent.  (data is ignored; but see NOTES.)

PTRACE_POKETEXT, PTRACE_POKEDATA
    Copy the word data to the address addr in the tracee's memory.  As for PTRACE_PEEKTEXT and PTRACE_PEEKDATA, these two requests are currently equivalent.
```

### Code Testing

Let's test it. First, we start a test program and get its pid. This program should preferably run in an infinite loop without exiting, making it convenient for our testing.

Then we execute `godbg attach <pid>` to start debugging. After the debugging session starts, we execute the disass command to view the instruction addresses corresponding to the assembly instructions.

```bash
godbg attach 479
process 479 attached succ
process 479 stopped: true
godbg> 
godbg> disass
.............
0x465326 MOV [RSP+Reg(0)+0x8], RSI
0x46532b MOV [RSP+Reg(0)+0x10], RBX
0x465330 CALL .-400789
0x465335 MOVZX ECX, [RSP+Reg(0)+0x18]
0x46533a MOV RAX, [RSP+Reg(0)+0x38]
0x46533f MOV RDX, [RSP+Reg(0)+0x30]
.............
godbg> 
```

Randomly select an assembly instruction address, enter `break <address>` in the debugging session, and we see a prompt that the breakpoint was added successfully.

```bash
godbg> b 0x46532b
break 0x46532b
Breakpoint added successfully
godbg>
godbg> exit
```

Finally, execute exit to end debugging.

Here we only showed the breakpoint addition logic. The breakpoint removal logic is actually very similar, and we'll introduce it when implementing the clear command. Some readers might wonder why we didn't demonstrate the effect of the tracee pausing execution after adding a breakpoint. This is because it's not the right time yet. Our breakpoint functionality is still at the instruction-level debugging stage (only implementing `break "instruction address"`). We haven't yet implemented the symbol-level debugger's operation of adding breakpoints at specified source code locations (`break "source file:line number"` or `break "function name"`). To demonstrate the tracee stopping at a specific source code location, we first need to use other means to obtain the instruction address corresponding to the source code location, then feed it back into our `break "instruction address"` operation. Even if we do this, we still need the `continue` operation to be fully supported before the tracee can run to the breakpoint location, to show the effect of the tracee pausing execution that readers want to see.

Readers just need to know the reason. We'll first quickly introduce how to implement break (add breakpoint) and clear (remove breakpoint) functions, then we'll look at how to implement debugging commands that control execution flow such as step (single-step instruction execution), next (single-step statement execution), continue (execute to breakpoint location), etc. After all necessary preliminary work is ready, we'll provide a complete demo to demonstrate the breakpoint functionality.
