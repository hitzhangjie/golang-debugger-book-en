## godbg> funcs `<regexp>`

### Implementation Goal

The previous section introduced the implementation of the debugger backend ListFunctions. This section will cover the implementation of `godbg> funcs <expr>` based on that foundation.

### Basic Knowledge

We previously discussed how communication between the frontend and backend works in a debug session, and also covered the implementation of ListFunctions. Now, implementing the debug session command `godbg> funcs <expr>` becomes straightforward - it's simply a matter of calling the remote procedure ListFunctions through the JSON-RPC client.

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

This allows users to search for functions using patterns like:
- `main.*` - All functions starting with "main"
- `.*Handler` - All functions ending with "Handler"
- `[A-Z].*` - All exported functions

#### Function Call Traversal

The Go function call path is roughly as follows:

```bash
// clientside execution of debug command
tinydbg> funcs <expr>
    \--> funcsCmd.cmdFn()
            \--> funcs(s *Session, ctx callContext, args string)
                    \--> t.printSortedStrings(t.client.ListFunctions(...))
                            \--> rpc2.(*RPCClient).ListFunctions(...)
```

Let's look at how the clientside is implemented:

```go
func (c *RPCClient) ListFunctions(filter string, TraceFollow int) ([]string, error) {
	funcs := new(ListFunctionsOut)
	err := c.call("ListFunctions", ListFunctionsIn{filter, TraceFollow}, funcs)
	return funcs.Funcs, err
}
```

Now let's see how the serverside is implemented:

`t.client.ListFunctions(...)` corresponds to the server-side ListFunctions handler:

```go
// ListFunctions lists all functions in the process matching filter.
func (s *RPCServer) ListFunctions(arg ListFunctionsIn, out *ListFunctionsOut) error {
	fns, err := s.debugger.Functions(arg.Filter, arg.FollowCalls)
	if err != nil {
		return err
	}
	out.Funcs = fns
	return nil
}
```

The server side calls this function (*RPCServer).ListFunctions(...), which then calls debugger.Functions. Let's look at `s.debugger.Functions(filter, followCalls)`:

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
```

The above code demonstrates how to add multi-agent intelligence, which is not impossible.

### Summary

This section introduced the implementation of the debugger command `godbg> funcs <expr>`. The command calls the remote ListFunctions procedure through JSON-RPC, supports regular expression filtering of function names, and allows setting the function call tracking depth. The implementation shows the key code handling logic between the debugger's frontend and backend.
