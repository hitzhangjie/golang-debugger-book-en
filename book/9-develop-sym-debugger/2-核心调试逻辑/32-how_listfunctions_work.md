## ListFunctions

### Implementation Goals

`ListFunctions` is a powerful feature in tinydbg that allows users to list functions defined in the target process and query functions matching specific patterns using regular expressions.

The core logic of `funcs <expr>` corresponds to ListFunctions. Additionally, the debugger command `tinydbg trace` also relies on ListFunctions to find matching functions and set breakpoints at these locations.

### Basic Knowledge

The main reason is to obtain function definitions, where does this data come from? We can get it from DWARF data, which we introduced earlier. This is not difficult, and even supporting regular expression search is not challenging.

However, if we want to recursively expand the function call graph of a function, this becomes more challenging. Think back to the function call graph we introduced earlier with go-ftrace, and you'll understand where the challenges lie in our ListFunctions implementation.

There are roughly two ways to analyze function call graphs:
1. Analyze source code, build AST, analyze FuncDecl.Body to find all function call type Exprs, then analyze and record them... However, relying on source code for tracing is not very convenient, it's better to work with just the executable;
2. Disassemble machine instructions, find all CALL <targetFuncName> instructions, and find the corresponding targetFuncName... This indeed builds the function call graph, but if we want to get input/output parameter information, it's not easy to determine;

Building on approach 2), to more easily obtain input/output parameters, we need to read the DWARF debug information of the binary file when the program starts, record all function definitions, such as map[pc]Function, where Function contains name, pc, lowpc, highpc, length, dwarfregisters information. Since we already know the pc corresponding to this function name, we can add breakpoints. When execution reaches the breakpoint, we can execute the function definition information at that pc, such as knowing how to get function parameters, and extract parameters according to corresponding rules. This achieves the operation of `tracking function execution -> printing function name -> printing function parameter list + printing function return value list`.

### Code Implementation

Let's look at the key code logic for this part.

#### Request and Response Parameter Types

The `ListFunctions` RPC call accepts two parameters:

```go
type ListFunctionsIn struct {
    Filter      string  // Regular expression pattern for filtering function names
    FollowCalls int     // Depth for tracking function calls (0 means no tracking)
}

type ListFunctionsOut struct {
    Funcs []string      // List of matching function names
}
```

#### Regular Expression Filtering

Function name filtering is implemented using regular expressions. When a filter pattern is provided, it is compiled into a regular expression object:

```go
regex, err := regexp.Compile(filter)
if err != nil {
    return nil, fmt.Errorf("invalid filter argument: %s", err.Error())
}
```

This allows users to search for functions using patterns like:
- `main.*` - All functions starting with "main"
- `.*Handler` - All functions ending with "Handler"
- `[A-Z].*` - All exported functions

#### Binary Information Reading

Function information is read from the debug information (DWARF) of the target binary file. This information is loaded during debugger initialization and stored in the `BinaryInfo` structure. Main components include:

- `Functions` slice, containing all functions in the binary file
- `Sources` slice, containing all source files
- DWARF debug information, for detailed function metadata

#### Function Information Extraction

Function information is extracted from DWARF debug information during debugger initialization. For each function, the following information is stored:

```go
type Function struct {
    Name       string
    Entry, End uint64    // Function address range
    offset     dwarf.Offset
    cu         *compileUnit
    trampoline bool
    InlinedCalls []InlinedCall
}
```

#### Getting Function List

#### Function Call Traversal

When `FollowCalls` is greater than 0, the debugger performs a breadth-first traversal of function calls. This is implemented in the `traverse` function:

```go
// Functions returns a list of functions in the target process.
func (d *Debugger) Functions(filter string, followCalls int) ([]string, error) {
	d.targetMutex.Lock()
	defer d.targetMutex.Unlock()

	regex, err := regexp.Compile(filter)
	if err != nil {
		return nil, fmt.Errorf("invalid filter argument: %s", err.Error())
	}

	funcs := []string{}
	t := proc.ValidTargets{Group: d.target}
	for t.Next() {
		for _, f := range t.BinInfo().Functions {
			if regex.MatchString(f.Name) {
				if followCalls > 0 {
					newfuncs, err := traverse(t, &f, 1, followCalls)
					if err != nil {
						return nil, fmt.Errorf("traverse failed with error %w", err)
					}
					funcs = append(funcs, newfuncs...)
				} else {
					funcs = append(funcs, f.Name)
				}
			}
		}
	}
	// uniq = sort + compact
	sort.Strings(funcs)
	funcs = slices.Compact(funcs)
	return funcs, nil
}

func traverse(t proc.ValidTargets, f *proc.Function, depth int, followCalls int) ([]string, error) {
    type TraceFunc struct {
        Func    *proc.Function
        Depth   int
        visited bool
    }
    
    // Use map to track visited functions, avoiding cycles
    TraceMap := make(map[string]TraceFuncptr)
    queue := make([]TraceFuncptr, 0, 40)
    funcs := []string{}
    
    // Start from root function
    rootnode := &TraceFunc{Func: f, Depth: depth, visited: false}
    TraceMap[f.Name] = rootnode
    queue = append(queue, rootnode)
    
    // BFS traversal
    for len(queue) > 0 {
        parent := queue[0]
        queue = queue[1:]
        
        // Skip if exceeding call depth
        if parent.Depth > followCalls {
            continue
        }
        
        // Skip if already visited
        if parent.visited {
            continue
        }
        
        funcs = append(funcs, parent.Func.Name)
        parent.visited = true
        
        // Disassemble function to find calls
        text, err := proc.Disassemble(t.Memory(), nil, t.Breakpoints(), t.BinInfo(), f.Entry, f.End)
        if err != nil {
            return nil, err
        }
        
        // Process each instruction
        for _, instr := range text {
            if instr.IsCall() && instr.DestLoc != nil && instr.DestLoc.Fn != nil {
                cf := instr.DestLoc.Fn
                // Skip most runtime functions, except specific ones
                if (strings.HasPrefix(cf.Name, "runtime.") || strings.HasPrefix(cf.Name, "runtime/internal")) &&
                    cf.Name != "runtime.deferreturn" && cf.Name != "runtime.gorecover" && cf.Name != "runtime.gopanic" {
                    continue
                }
                
                // If not visited, add new function to queue
                if TraceMap[cf.Name] == nil {
                    childnode := &TraceFunc{Func: cf, Depth: parent.Depth + 1, visited: false}
                    TraceMap[cf.Name] = childnode
                    queue = append(queue, childnode)
                }
            }
        }
    }
    return funcs, nil
}
```

Traversal algorithm:
1. Use map to track visited functions, avoiding duplicates
2. Use queue for breadth-first traversal
3. For each function:
   - Disassemble its code
   - Find all CALL instructions
   - Extract called function information
   - If not visited, add new function to queue
4. Skip most runtime functions to reduce noise
5. Respect maximum call depth parameter

ps: Why not use AST here? Finding all function calls in FuncDecl.Body is also a method, and indeed it is one approach. However, the AST approach would likely be less efficient, and due to inlining, the structure in AST may not reflect the final optimized instructions after compilation, such as inlining optimizations. When using AST to trace a function location and get its parameters, errors might occur because it's been inlined, and getting parameters through BP register + parameter offset might not give the real parameters. Using CALL instructions here avoids these oversights and is more efficient.

#### Result Processing

Final step in processing results:

```go
// Sort and remove duplicates
sort.Strings(funcs)
funcs = slices.Compact(funcs)
```

This ensures the returned function list:
- Is alphabetically sorted
- Has no duplicates
- Only contains functions matching the filter pattern

#### Usage Scenarios

The `ListFunctions` feature is mainly used in two debugger commands:

1. `funcs <regexp>` - List all functions matching the pattern
2. `trace <regexp>` - Set trace points on matching functions and their called functions

For example:
```
tinydbg> funcs main.*
main.main
main.init
main.handleRequest

tinydbg> trace main.*
```

The trace command uses `ListFunctions` with `FollowCalls` set greater than 0 to find all functions that might be called by matching functions, thus achieving comprehensive function call tracing.

### Summary

This article introduced the design and implementation of ListFunctions, which filters function names using regular expressions and finds function call relationships through breadth-first search + disassembling code and analyzing CALL instructions. Compared to using AST analysis, this approach better handles the impact of inlining optimizations, and this method is more convenient and efficient than analyzing source code. In tinydbg, ListFunctions mainly serves two debugger commands: 1) funcs for listing functions matching patterns, and 2) trace for setting trace points on these functions and getting their parameters. This article only covered how to ListFunctions; in the `tinydbg trace` section, we will further introduce how to get the input parameter list and return value list of traced functions.
