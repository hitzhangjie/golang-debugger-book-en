## Dynamic Breakpoints

### Design Goal: Removing Breakpoints

We've previously covered how to add breakpoints and display the breakpoint list. Now let's look at how to remove breakpoints.

Both adding and removing breakpoints require the use of ptrace. Recall that adding a breakpoint first uses PTRACEPEEKDATA/PTRACEPOKEDATA to backup and overwrite instruction data. The logic for removing a breakpoint is somewhat the opposite - first overwrite the original backed-up instruction data back to the breakpoint's instruction address, then remove it from the set of added breakpoints.

> ps: Under Linux, PTRACE_PEEKTEXT/PTRACE_PEEKDATA and PTRACE_POKETEXT/PTRACE_POKEDATA are not different, so when executing ptrace operations, you can choose any ptrace request.
>
> For readability, PTRACE_PEEKTEXT/PTRACE_POKETEXT are preferred when reading/writing instructions, while PTRACE_PEEKDATA/PTRACE_POKEDATA are preferred when reading/writing data.

### Code Implementation

First, parse the breakpoint number parameter `-n <breakNo>` and check if a breakpoint with number n exists in the set of added breakpoints. If not, then `<breakNo>` is an invalid parameter.

If the breakpoint does exist, execute ptrace(PTRACE_POKEDATA,...) to overwrite the original backed-up 1-byte instruction data back to the original instruction address, effectively removing the breakpoint. Then, remove this breakpoint from the set of added breakpoints.

The clear operation implementation is relatively simple and is implemented in [hitzhangjie/godbg](https://github.com/hitzhangjie/godbg). Readers can check the godbg source code (which is actually the part listed here). However, as we've emphasized, the above repo provides a relatively complete debugger with a large amount of code. Therefore, we also provide an example in [hitzhangjie/golang-debugger-lessons](https://github.com/hitzhangjie/golang-debugger-lessons))/8_clear, where we've extracted and demonstrated the implementation code for the closely related debugging commands break, breakpoints, continue, and clear in a single source file.

Each example in the golang-debugger-lessons repo is completely independent, so you can freely modify and test without worrying about breaking the entire godbg project, making it run incorrectly, or having trouble troubleshooting issues. This might be more suitable for beginners to learn and test. You can look at the godbg project after gaining some experience.

TODO Code example can be optimized, see: https://github.com/hitzhangjie/golang-debugger-book/issues/15

```go
package debug

import (
	"errors"
	"fmt"
	"strings"
	"syscall"

	"godbg/target"

	"github.com/spf13/cobra"
)

var clearCmd = &cobra.Command{
	Use:   "clear <n>",
	Short: "Clear breakpoint with specified number",
	Long:  `Clear breakpoint with specified number`,
	Annotations: map[string]string{
		cmdGroupKey: cmdGroupBreakpoints,
	},
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Printf("clear %s\n", strings.Join(args, " "))

		id, err := cmd.Flags().GetUint64("n")
		if err != nil {
			return err
		}

		// Find breakpoint
		var brk *target.Breakpoint
		for _, b := range breakpoints {
			if b.ID != id {
				continue
			}
			brk = b
			break
		}

		if brk == nil {
			return errors.New("breakpoint does not exist")
		}

		// Remove breakpoint
		n, err := syscall.PtracePokeData(TraceePID, brk.Addr, []byte{brk.Orig})
		if err != nil || n != 1 {
			return fmt.Errorf("failed to remove breakpoint: %v", err)
		}
		delete(breakpoints, brk.Addr)

		fmt.Println("Breakpoint removed successfully")
		return nil
	},
}

func init() {
	debugRootCmd.AddCommand(clearCmd)

	clearCmd.Flags().Uint64P("n", "n", 1, "breakpoint number")
}
```

### Code Testing

First, run a program to be debugged, get its pid, then use `godbg attach <pid>` to debug the target process. First, use the `disass` command to display the assembly instruction list, then execute the `b <locspec>` command to add several breakpoints.

```bash
godbg> b 0x4653af
break 0x4653af
Breakpoint added successfully
godbg> b 0x4653b6
break 0x4653b6
Breakpoint added successfully
godbg> b 0x4653c2
break 0x4653c2
Breakpoint added successfully
```

Here we executed 3 breakpoint addition operations. `breakpoints` shows the list of added breakpoints:

```bash
godbg> breakpoints
breakpoint[1] 0x4653af 
breakpoint[2] 0x4653b6 
breakpoint[3] 0x4653c2 
```

Then we execute `clear -n 2` to remove the second breakpoint:

```bash
godbg> clear -n 2
clear 
Breakpoint removed successfully
```

Next, execute `breakpoints` again to view the remaining breakpoints:

```bash
godbg> bs
breakpoint[1] 0x4653af 
breakpoint[3] 0x4653c2
```

Now breakpoint 2 has been removed, and our breakpoint addition and removal functionality is working correctly.
