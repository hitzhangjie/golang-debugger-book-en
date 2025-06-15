## Process Execution Control

### Implementation Goal: Continue Until Next Breakpoint

Running until the next breakpoint means letting the tracee execute subsequent instructions normally until it hits and executes an instruction that has been patched with 0xCC, triggering an int3 interrupt, after which the kernel's interrupt service routine pauses the tracee's execution.

How is this implemented? The operating system provides the `ptrace(PTRACE_COND,...)` operation, which allows us to run directly until the next breakpoint. However, before executing this call, we need to check if the data at the current `PC-1` address is `0xCC`. If it is, we need to replace it with the original instruction data.

### Code Implementation

When the continue command is executed, it first checks if the data at PC-1 is 0xCC. If it is, this indicates that PC-1 is a patched instruction (which could be either a single-byte or multi-byte instruction). We need to restore the data at the breakpoint location to its original state before it was patched. Then set PC=PC-1 and execute the `ptrace(PTRACE_COND, ...)` operation to request the operating system to resume tracee execution, allowing it to run until it hits a breakpoint and stops. When it reaches the breakpoint, it will trigger an int3 interrupt again and stop, and the tracee's state change will be notified to the tracer.

Finally, our tracer waits for the tracee to stop using `syscall.Wait4(...)`, then checks its register information, where we first only get the PC value. Note that the current PC value is the address after executing the 0xCC instruction, so PC = breakpoint address + 1.

**file: cmd/debug/continue.go**

```go
package debug

import (
	"fmt"
	"syscall"

	"github.com/spf13/cobra"
)

var continueCmd = &cobra.Command{
	Use:   "continue",
	Short: "Run until next breakpoint",
	Annotations: map[string]string{
		cmdGroupKey: cmdGroupCtrlFlow,
	},
	Aliases: []string{"c"},
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("continue")

		// Read PC value
		regs := syscall.PtraceRegs{}
		err := syscall.PtraceGetRegs(TraceePID, &regs)
		if err != nil {
			return fmt.Errorf("get regs error: %v", err)
		}

		buf := make([]byte, 1)
		n, err := syscall.PtracePeekText(TraceePID, uintptr(regs.PC()-1), buf)
		if err != nil || n != 1 {
			return fmt.Errorf("peek text error: %v, bytes: %d", err, n)
		}

		// read a breakpoint
		if buf[0] == 0xCC {
			regs.SetPC(regs.PC() - 1)
			// TODO refactor breakpoint.Disable()/Enable() methods
			orig := breakpoints[uintptr(regs.PC())].Orig
			n, err := syscall.PtracePokeText(TraceePID, uintptr(regs.PC()), []byte{orig})
			if err != nil || n != 1 {
				return fmt.Errorf("poke text error: %v, bytes: %d", err, n)
			}
		}

		err = syscall.PtraceCont(TraceePID, 0)
		if err != nil {
			return fmt.Errorf("single step error: %v", err)
		}

		// MUST: After initiating certain ptrace requests that control tracee execution, call syscall.Wait to wait for and get tracee state changes
		var wstatus syscall.WaitStatus
		var rusage syscall.Rusage
		_, err = syscall.Wait4(TraceePID, &wstatus, syscall.WALL, &rusage)
		if err != nil {
			return fmt.Errorf("wait error: %v", err)
		}

		// display current pc
		regs = syscall.PtraceRegs{}
		err = syscall.PtraceGetRegs(TraceePID, &regs)
		if err != nil {
			return fmt.Errorf("get regs error: %v", err)
		}
		fmt.Printf("continue ok, current PC: %#x\n", regs.PC())
		return nil
	},
}

func init() {
	debugRootCmd.AddCommand(continueCmd)
}
```

The continue operation can be implemented by making simple modifications to cmd/debug/step.go. See the source file cmd/debug/continue.go for details.

> ps: The above code is from [hitzhangjie/godbg](https://github.com/hitzhangjie/godbg), where we focus on the continue implementation. Additionally, in [hitzhangjie/golang-debuger-lessons](https://github.com/hitzhangjie/golang-debugger-lessons)/11_continue, we also provide a continue execution example in a single source file, independent of other demos. You can modify and test it according to your ideas without worrying about breaking the entire godbg project.

### Code Testing

First, start a process, get its pid, then use `godbg attach <pid>` to debug the target process. Once the debug session is ready, we input `dis` (dis is an alias for the disass command) to perform disassembly.

To verify the continue command's functionality, we first need to use dis to view instruction addresses, then add breakpoints with break, and finally use continue to run until the breakpoint.

Note that when adding breakpoints, we should briefly look at the meaning of the assembly instructions, because considering the branch control logic during code execution, the breakpoints we add might not be on the actual execution path of the code. Therefore, we might not be able to verify the continue functionality (but we can still verify running until process execution ends).

To verify running to the next breakpoint, I ran dis and step multiple times until I found a sequence of instructions that could execute continuously without any jumps, as shown below:

```bash
godbg> dis
...
godbg> dis
...
godbg> dis
0x42e2e0 cmp $-0x4,%eax                 ; Start execution from this instruction
0x42e2e3 jne 0x24c
0x42e2e9 mov 0x20(%rsp),%eax
0x42e2ed test %eax,%eax                 ; First byte overwritten with 0xCC, PC=0x42e2ed+1
0x42e2ef jle 0xffffffffffffffbe
0x42e2f1 movq $0x0,0x660(%rsp)
0x42e2fd mov 0x648(%rsp),%rbp
0x42e305 add $0x650,%rsp
0x42e30c retq
0x42e30d movq $0x0,0x30(%rsp)
godbg> 
```

Then we try to add a breakpoint with break and continue to run until the breakpoint:

```bash
godbg> b 0x42e2ed
break 0x42e2ed
Breakpoint added successfully
godbg> c
continue
continue ok, current PC: 0x42e2ee
```

We added a breakpoint at the 4th instruction `0x42e2ed test %eax,%eax`. After the breakpoint was successfully added, we executed `c` (c is an alias for continue) to run until the breakpoint. After reaching the breakpoint, it outputs the current PC value. As we analyzed earlier, PC=0x42e2ee=0x42e2ed+1, because the debugged process stopped after executing the instruction `0xCC` at 0x42e2ed, which is exactly as expected.

### More Related Content

How important is the continue command? It's very important, especially for symbol-level debuggers.

During the conversion from source code to assembly instructions, a single source code statement might correspond to multiple machine instructions. When we:

- Execute statement by statement;
- Enter or exit a function (functions have prologue and epilogue);
- Enter or exit a loop body;
- And so on;

To implement the above source-level debugging, we must rely on understanding of the source code and instructions to set breakpoints at the correct addresses, then use continue to implement the functionality.

We will study these topics in more detail in the symbol-level debugger chapter.
