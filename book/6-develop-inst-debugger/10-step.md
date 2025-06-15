## Process Execution Control

### Implementation Goal: Step-by-Step Instruction Execution

After implementing disassembly and breakpoint management functionality, we will now explore how to control the execution of the debugged process, such as step-by-step instruction execution and continuing execution until a breakpoint is hit. In the later chapters on symbol-level debugger development, we will also implement statement-by-statement execution (next).

In this section, we will implement the `step` command to support step-by-step instruction execution.

### Code Implementation

Step-by-step instruction execution can be handled by the kernel through the `ptrace(PTRACE_SINGLESTEP,...)` operation. However, before executing this operation, the step command needs to consider some special factors to ensure proper execution.

The current PC value might be at an address after a breakpoint, for example:

1. For a multi-byte instruction that has been patched, if the first byte is modified to 0xCC, the current PC value is actually at the address of the second byte of the multi-byte instruction, not the first byte. If we don't modify the PC value, the processor will fail to decode the instruction when executing from the second byte;
2. For a single-byte instruction, if we directly decode the instruction at the next address, we would miss the original one-byte instruction at the breakpoint location;

To ensure proper step execution, before `ptrace(PTRACE_SINGLESTEP,...)`, we need to first use `ptrace(PTRACE_PEEKTEXT,...)` to read the data at address `PC-1`. If it's 0xCC, it indicates a breakpoint at this location. We need to restore the original data before the breakpoint was added, set PC=PC-1, and then continue execution.

**file：cmd/debug/step.go**

```go
package debug

import (
	"fmt"
	"syscall"

	"github.com/spf13/cobra"
)

var stepCmd = &cobra.Command{
	Use:   "step",
	Short: "Execute one instruction",
	Annotations: map[string]string{
		cmdGroupKey: cmdGroupCtrlFlow,
	},
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("step")

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

		err = syscall.PtraceSingleStep(TraceePID)
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
		fmt.Printf("single step ok, current PC: %#x\n", regs.PC())
		return nil
	},
}

func init() {
	debugRootCmd.AddCommand(stepCmd)
}

```

The above is the implementation code for the step command, but it's not a very user-friendly implementation:

- It does implement step-by-step instruction execution, achieving this section's goal;
- After each instruction execution, it can print the current PC value, helping us determine the address of the next instruction to be executed;

However, it doesn't print the instructions before and after the current instruction to be executed, nor does it indicate the next instruction with an arrow. A better interaction might look like this:

```
godbg> step

=> address1 assembly_instruction1
   address2 assembly_instruction2
   address3 assembly_instruction3
   ...
```

This affects the debugging experience, which we will improve in subsequent development.

> ps: The above code is from [hitzhangjie/godbg](https://github.com/hitzhangjie/godbg), where we focus on the step implementation. Additionally, in [hitzhangjie/golang-debuger-lessons](https://github.com/hitzhangjie/golang-debugger-lessons)/10_step, we also provide a step execution example in a single source file, independent of other demos. You can modify and test it according to your ideas without worrying about breaking the entire godbg project.

### Code Testing

Start a program, get its process pid, then execute `godbg attach <pid>` to debug the process. Once the debug session is ready, we input `disass` to see the assembly instructions after the current instruction address.

```bash
godbg> disass
0x40ab47 movb $0x0,0x115(%rdx)
0x40ab4e mov 0x18(%rsp),%rcx
0x40ab53 mov 0x38(%rsp),%rdx
0x40ab58 mov (%rdx),%ebx
0x40ab5a test %ebx,%ebx
0x40ab5c jne 0x4c
0x40ab5e mov 0x30(%rax),%rbx
0x40ab62 movb $0x1,0x115(%rbx)
0x40ab69 mov %rdx,(%rsp)
0x40ab6d movl $0x0,0x8(%rsp)
```

Then try executing the `step` command and observe the output.

```bash
godbg> step
step
single step ok, current PC: 0x40ab4e
godbg> step
step
single step ok, current PC: 0x40ab53
godbg> step
step
single step ok, current PC: 0x40ab58
godbg> 
```

We executed the step instruction three times. After each instruction execution, step outputs the PC value after execution, which are 0x40ab4e, 0x40ab53, and 0x40ab58 respectively, each being the starting address of the next instruction.

One might wonder, how does the kernel implement step-by-step instruction execution when we execute the system call `ptrace(PTRACE_SINGLESTEP,...)`? Clearly, it doesn't use the instruction patching method (if it did, the PC values output by the step command should be the current displayed values plus 1 respectively).

### More Related Content: SINGLESTEP

So how does the kernel handle the PTRACE_SINGLESTEP request? SINGLESTEP is indeed special, and the man(2) manual doesn't provide much valuable information:

```bash
   PTRACE_SINGLESTEP stops
       [Details of these kinds of stops are yet to be documented.]
```

There isn't much valuable information in the man(2) manual, but after examining the kernel source code and Intel development manual, we can understand these details.

1. SINGLESTEP debugging on Intel platforms partially relies on the processor's own hardware features. According to the "Intel® 64 and IA-32 Architectures Software Developer's Manual Volume 1: Basic Architecture", Intel architecture processors have a flag register EFLAGS. When the kernel sets the TF flag in this register to 1, the processor automatically enters single-step execution mode, and clears it to exit single-step mode.

   > **System Flags and IOPL Field**
   >
   > The system flags and IOPL field in the **EFLAGS** register control operating-system or executive operations. **They should not be modified by application programs.** The functions of the system flags are as follows:
   >
   > **TF (bit 8) Trap flag** — Set to enable single-step mode for debugging; clear to disable single-step mode.
   >
2. When we execute the system call `syscall.PtraceSingleStep(...)`, it's actually `ptrace(PTRACE_SINGLESTEP, pid...)`. At this point, the kernel sets the flags in the tracee's task_struct register section to flags |= TRAP, then schedules the tracee to execute.
3. When the scheduler executes the tracee, it first restores the hardware context information from the process's task_struct to the processor registers, then executes the tracee's instructions. When the processor detects EFLAGS.TF=1, it will first clear this flag bit when executing an instruction, then execute a single instruction. After execution, the processor automatically generates a trap interrupt, without requiring software-level simulation.

   > **Single-step interrupt**
   > When a system is instructed to single-step, it will execute one instruction and then stop.
   > ...
   > The Intel 8086 trap flag and type-1 interrupt response make it quite easy to implement a single-step feature in an 8086-based system. If the trap flag is set, the 8086 will automatically do a type-1 interrupt after each instruction executes. When the 8086 does a type-1 interrupt, ...
   > The trap flag is reset when the 8086 does a type-1 interrupt, so the single-step mode will be disabled during the interrupt-service procedure.
   >
4. The kernel's interrupt service routine handles this TRAP by pausing the tracee's scheduling (at this time it also saves the hardware context information), then the kernel sends a SIGTRAP signal to the tracer, notifying the debugger that the tracee you're tracking has executed one instruction and stopped, waiting to receive subsequent debug commands.

These are some details about single-step execution on Intel platforms. Readers interested in other hardware platforms can also learn about how they design and implement solutions for single-step debugging.
