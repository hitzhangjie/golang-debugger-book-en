## Viewing Process State (Registers)

### Implementation Goal: pregs Viewing Registers

In this section, we will implement the `pregs` command to facilitate viewing process register data during debugging. For instruction-level debugging, we see the assembly instructions to be executed through disassembly. To understand the operands of the instructions, we need to use `pmem` to view memory data and `pregs` to view register data. This is similar to how a symbol-level debugger needs to know the corresponding variable values after seeing the source code.

In previous chapters, we have used `ptrace(PTRACE_GETREGS,...)` multiple times to obtain register data. Here, we need to support a separate `pregs` debugging command that prints out the current information of all registers each time it is executed. Unlike gdb, we do not support printing the information of a single register.

> ps: Instruction-level debugging has a relatively high threshold; at least, one needs to understand assembly language or be able to understand it with the help of certain tools. Some tools also support restoring the corresponding high-level language source code from instruction data, such as generating a corresponding C program. However, due to issues with variable names and function names, even if generated, the readability is poor, and one can only see the program organization and calling methods. In this process, different processors correspond to different registers, such as i386, amd64, arm64, etc., which requires developers to refer to and understand the relevant details to debug smoothly.

### Code Implementation

To view process register data, we need to use the `ptrace(PTRACE_GETREGS,...)` operation to read the register data of the debugged process.

**file: cmd/debug/pregs.go**

```go
package debug

import (
	"fmt"
	"os"
	"reflect"
	"syscall"
	"text/tabwriter"

	"github.com/spf13/cobra"
)

var pregsCmd = &cobra.Command{
	Use:   "pregs",
	Short: "Print register data",
	Annotations: map[string]string{
		cmdGroupKey: cmdGroupInfo,
	},
	RunE: func(cmd *cobra.Command, args []string) error {
		regsOut := syscall.PtraceRegs{}
		err := syscall.PtraceGetRegs(TraceePID, &regsOut)
		if err != nil {
			return fmt.Errorf("get regs error: %v", err)
		}
		prettyPrintRegs(regsOut)
		return nil
	},
}

func init() {
	debugRootCmd.AddCommand(pregsCmd)
}

func prettyPrintRegs(regs syscall.PtraceRegs) {
	w := tabwriter.NewWriter(os.Stdout, 0, 8, 4, ' ', 0)
	rt := reflect.TypeOf(regs)
	rv := reflect.ValueOf(regs)
	for i := 0; i < rv.NumField(); i++ {
		fmt.Fprintf(w, "Register\t%s\t%#x\t\n", rt.Field(i).Name, rv.Field(i).Uint())
	}
	w.Flush()
}
```

The program first obtains register data through ptrace, then prints the register information using `prettyPrintRegs`. The `prettyPrintRegs` function uses `tabwriter` to format the register data in the style "**Register	Register Name	Register Value**" for easy viewing.

> `tabwriter` is very suitable for scenarios where multiple rows and columns of data need to be output and each column of data needs to be aligned.

### Code Testing

First, start a test program to act as the debugged process, get its pid, then use `godbg attach <pid>` to debug the target process. Once the debug session is ready, enter the `pregs` command to view the register information.

```bash
$ godbg attach 116
process 116 attached succ
process 116 stopped: true
godbg> pregs
Register    R15         0x400             
Register    R14         0x3               
Register    R13         0xa               
Register    R12         0x4be86f          
Register    Rbp         0x7ffc5095bd50    
Register    Rbx         0x555900          
Register    R11         0x286             
Register    R10         0x0               
Register    R9          0x0               
Register    R8          0x0               
Register    Rax         0xfffffffffffffe00  
Register    Rcx         0x464fc3          
Register    Rdx         0x0               
Register    Rsi         0x80              
Register    Rdi         0x555a48          
Register    Orig_rax    0xca              
Register    Rip         0x464fc3          
Register    Cs          0x33              
Register    Eflags      0x286             
Register    Rsp         0x7ffc5095bd08    
Register    Ss          0x2b              
Register    Fs_base     0x555990          
Register    Gs_base     0x0               
Register    Ds          0x0               
Register    Es          0x0               
Register    Fs          0x0               
Register    Gs          0x0               
godbg> 
```

We see that the `pregs` command displays three columns of data:

- The first column is uniformly "Register," which has no special meaning, just for readability and aesthetics;
- The second column is the register name, left-aligned for aesthetics;
- The third column is the current value of the register, printed in hexadecimal, left-aligned for aesthetics;

During debugging, it is sometimes necessary to view and modify register states, such as viewing and modifying return values (return values are usually recorded in the rax register, but Go language supports multiple return values, which has some special handling).

### Summary

So far, we have implemented the `pmem` and `pregs` commands for viewing memory and register data. However, just viewing is not enough; we should also implement operations to modify memory data and register data, which we will introduce in later sections.
