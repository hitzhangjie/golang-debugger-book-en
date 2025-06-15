## Dynamic Breakpoints

### Implementation Goal: Listing Breakpoints

In the previous section, we implemented dynamic breakpoint addition. To support breakpoint removal, we must provide some descriptive information for breakpoints, such as breakpoint numbers, so users can remove breakpoints using their numbers.

For example, if three breakpoints are added in sequence, numbered `1, 2, 3` respectively, when a user wants to remove breakpoint 2, they can do so by executing the command `clear -n 2`.

Of course, after adding many breakpoints, it becomes difficult to remember how many breakpoints we've added, what instruction addresses they correspond to, and their order (numbers). Therefore, we must also provide a function to list all added breakpoints, such as executing `breakpoints` to list all breakpoints.

The display format should look something like this, showing at least the breakpoint number, corresponding instruction address, and source code location.

```bash
godbg> breakpoints
breakpoint[1] 0x4000001 main.go:10
breakpoint[2] 0x5000001 hello.go:20
breakpoint[3] 0x5000101 world.go:30
```

### Code Implementation

#### Code Adjustment: Recording Number and Location When Adding Breakpoints

We need to make appropriate modifications to the breakpoint addition code from the previous section to record the breakpoint number, instruction address, and source code location (we'll use an empty string for source location for now) when adding a breakpoint.

**file: cmd/debug/break.go**

```go
package debug

var breakCmd = &cobra.Command{
	RunE: func(cmd *cobra.Command, args []string) error {
		...
		breakpoint, err := target.NewBreakpoint(addr, orig[0], "")
		if err != nil {
			return fmt.Errorf("add breakpoint error: %v", err)
		}
		breakpoints[addr] = &breakpoint
    ...
	},
}

func init() {
	debugRootCmd.AddCommand(breakCmd)
}
```

**file: target/breakpoint.go**

```go
func NewBreakpoint(addr uintptr, orig byte, location string) (Breakpoint, error) {
	b := Breakpoint{
		ID:       seqNo.Add(1),
		Addr:     addr,
		Orig:     orig,
		Location: location,
	}
	return b, nil
}
```

#### New Command: breakpoints to Display Breakpoint List

We add a new debugging command `breakpoints`, using the plural noun form to imply querying all breakpoints. The implementation logic is quite simple - we just need to iterate through all added breakpoints and output their information.

> The `breakpoints` operation is relatively simple to implement. We haven't provided a separate example directory in [hitzhangjie/golang-debug-lessons](https://github.com/hitzhangjie/golang-debug-lessons), but instead implemented it in [hitzhangjie/godbg](https://github.com/hitzhangjie/godbg). Readers can check the source code of godbg.
> TODO Code example can be optimized, see: https://github.com/hitzhangjie/golang-debugger-book/issues/15

**file: cmd/debug/breakpoints.go**

```go
package debug

import (
	"fmt"
	"sort"

	"godbg/target"

	"github.com/spf13/cobra"
)

var breaksCmd = &cobra.Command{
	Use:     "breaks",
	Short:   "List all breakpoints",
	Long:    "List all breakpoints",
	Aliases: []string{"bs", "breakpoints"},
	Annotations: map[string]string{
		cmdGroupKey: cmdGroupBreakpoints,
	},
	RunE: func(cmd *cobra.Command, args []string) error {

		bs := target.Breakpoints{}
		for _, b := range breakpoints {
			bs = append(bs, *b)
		}
		sort.Sort(bs)

		for _, b := range bs {
			fmt.Printf("breakpoint[%d] %#x %s\n", b.ID, b.Addr, b.Location)
		}
		return nil
	},
}

func init() {
	debugRootCmd.AddCommand(breaksCmd)
}
```

New breakpoints are recorded in a `map[uintptr]*breakpoint` structure. We use a map here mainly considering the scenarios of insertion, deletion, and querying, which helps improve query efficiency. For example, when executing `break main.go:10` multiple times, we first convert main.go:10 to an instruction address, then query this map structure, which allows us to determine if this breakpoint already exists in O(1) time complexity.

In the above map, the key is the breakpoint's instruction address, and the value is the breakpoint description struct. If we directly iterate through the map's key-value pairs using for-range and output their information, the breakpoint display order might not be according to the breakpoint numbers.

To ensure that breakpoints are displayed in order by their numbers, we need to implement the `sort.Interface{}` interface for the breakpoint slice Breakpoints, allowing it to be sorted by number.

**file: target/breakpoint.go**

```go
package target

import (
	"go.uber.org/atomic"
)

var (
  // Breakpoint number
	seqNo = atomic.NewUint64(0)
)

// Breakpoint represents a breakpoint
type Breakpoint struct {
	ID       uint64
	Addr     uintptr
	Orig     byte
	Location string
}

// Breakpoints is a slice of breakpoints that implements the sorting interface
type Breakpoints []Breakpoint

func (b Breakpoints) Len() int {
	return len(b)
}

func (b Breakpoints) Less(i, j int) bool {
	if b[i].ID <= b[j].ID {
		return true
	}
	return false
}

func (b Breakpoints) Swap(i, j int) {
	b[i], b[j] = b[j], b[i]
}
```

This way, we can sort existing breakpoints by number using `sort.Sort(bs)`, then iterate through and output the breakpoint information.

Based on actual debugging experience with command-line debuggers, viewing the breakpoint list, adding breakpoints, and deleting breakpoints are relatively frequent operations. Using a map and slice to store all breakpoint information makes adding, deleting, and querying more convenient, and the coding is also easier :)

### Code Testing

First, we run a test program, check its pid, then use `godbg attach <pid>` to debug the target process. After the debugging session is ready, we use `disass` to view the assembly instruction list and instruction addresses, then add multiple breakpoints using `break <locspec>`, and display the list of added breakpoints using `breakpoints` or `breaks`.

```bash
godbg> disass
...
0x4653a6 INT 0x3                                          ; add breakpoint here
0x4653a7 MOV [RSP+Reg(0)+0x40], AL
0x4653ab MOV RCX, RSP                                     ; add breakpoint here
0x4653ae INT 0x3
0x4653af AND [RAX-0x7d], CL
0x4653b2 Prefix(0xc4) Prefix(0x28) Prefix(0xc3) INT 0x3
0x4653b6 MOV EAX, [RSP+Reg(0)+0x30]
0x4653ba ADD RAX, 0x8
0x4653be INT 0x3
0x4653bf MOV [RSP+Reg(0)], EAX
0x4653c2 REX.W Op(0)
...
godbg> b 0x4653a6
break 0x4653a6
Breakpoint added successfully
godbg> b 0x4653ab
break 0x4653ab
Breakpoint added successfully
godbg> breakpoints
breakpoint[1] 0x4653a6 
breakpoint[2] 0x4653ab 
godbg> 
```

We can see that after adding breakpoints, the breakpoints command correctly displays the breakpoint list.

```bash
godbg> breakpoints
breakpoint[1] 0x4653a6 
breakpoint[2] 0x4653ab 
```

The numbers 1 and 2 here will be used as breakpoint identifiers for removing breakpoints, which we'll describe in the clear command.

> ps: Similar to the previous section, currently adding breakpoints `break <locspec>` and listing breakpoints `breakpoints`, the locspec format only supports memory addresses and doesn't yet support source code locations. We'll solve this issue when implementing the symbol-level debugger later.
