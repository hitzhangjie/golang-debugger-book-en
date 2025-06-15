## Dynamic Breakpoints

### Implementation Goal: Clearing All Breakpoints

The `clearall` command is designed to quickly remove all breakpoints at once, rather than using `clear -n <breakNo>` to delete them one by one. This is particularly useful when you have added many breakpoints and want to clear them all quickly.

### Code Implementation

The implementation logic of `clearall` is similar to that of `clear`, but the processing logic is simpler.

> The clearall operation implementation is relatively simple. We haven't provided a separate example directory in [hitzhangjie/golang-debug-lessons](https://github.com/hitzhangjie/golang-debug-lessons), but instead implemented it in [hitzhangjie/godbg](https://github.com/hitzhangjie/godbg). Readers can check the godbg source code.
>
> TODO Code example can be optimized, see: https://github.com/hitzhangjie/golang-debugger-book/issues/15

**file: cmd/debug/clearall.go**

```go
package debug

import (
	"fmt"
	"syscall"

	"godbg/target"

	"github.com/spf13/cobra"
)

var clearallCmd = &cobra.Command{
	Use:   "clearall <n>",
	Short: "Clear all breakpoints",
	Long:  `Clear all breakpoints`,
	Annotations: map[string]string{
		cmdGroupKey: cmdGroupBreakpoints,
	},
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("clearall")

		for _, brk := range breakpoints {
			n, err := syscall.PtracePokeData(TraceePID, brk.Addr, []byte{brk.Orig})
			if err != nil || n != 1 {
				return fmt.Errorf("failed to clear breakpoints: %v", err)
			}
		}

		breakpoints = map[uintptr]*target.Breakpoint{}
		fmt.Println("All breakpoints cleared successfully")
		return nil
	},
}

func init() {
	debugRootCmd.AddCommand(clearallCmd)
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

Then we execute `clearall` to clear all breakpoints:

```bash
godbg> clearall
clearall 
All breakpoints cleared successfully
```

Next, execute `breakpoints` again to view the remaining breakpoints:

```bash
godbg> bs
godbg> 
```

Now there are no remaining breakpoints, and our breakpoint addition and clearing functionality is working correctly.

OK, up to this point, we have implemented the functionality for adding breakpoints, listing breakpoints, deleting specific breakpoints, and clearing all breakpoints. However, we haven't demonstrated the effect of breakpoints (stopping execution at the breakpoint location). Next, we will implement the step (execute one instruction) and continue (run until breakpoint) operations.
