## Further Reading: Make Your Program More Powerful with Starlark

Starlark is a configuration language derived from Python, but simpler and safer. It was originally developed by Google for the Bazel build system. Starlark retains Python's basic syntax and data types while removing some dangerous features like circular references and infinite recursion. This makes Starlark very suitable as a configuration or scripting language to be embedded in other programs.

The main features of Starlark include:

1. Easy to Learn - Uses Python-style syntax, almost no learning curve for developers familiar with Python
2. Deterministic - Same input always produces same output, no randomness or side effects
3. Sandbox Isolation - Cannot access filesystem, network or other external resources, ensuring security
4. Extensible - Easy to expose host language (like Go) functions for use in Starlark
5. Fast Execution - Excellent interpreter performance, suitable for embedded use

These features make Starlark an ideal embedded configuration/scripting language. By integrating Starlark into our Go programs, we can let users extend and customize program functionality using Starlark scripts, while ensuring security and controllability.

For example, in the go-delve/delve debugger, Starlark is used to write automated debugging scripts. Users can use Starlark scripts to automatically execute a series of debug commands, or trigger certain debugging operations based on specific conditions. This greatly enhances the debugger's flexibility and programmability.

Below we'll demonstrate through a simple example how to integrate the Starlark engine into a Go program and implement mutual function calls between Go and Starlark.

### Integrating the Starlark Engine into Go Programs

Let's start with a simple example that demonstrates how to integrate the Starlark engine into a Go program. This example implements a basic REPL (Read-Eval-Print Loop) environment that allows users to input Starlark code and execute it immediately:

```go
package main

import (
    ...

	"go.starlark.net/starlark"
	"go.starlark.net/syntax"
)

func main() {
	// Create a new Starlark thread
	thread := &starlark.Thread{
		Name: "repl",
		Print: func(thread *starlark.Thread, msg string) {
			fmt.Println(msg)
		},
	}

	// Create a new global environment
	globals := starlark.StringDict{}

	// Create a scanner for reading input
	scanner := bufio.NewScanner(os.Stdin)
	fmt.Println("Starlark REPL (type 'exit' to quit)")

	errExit := errors.New("exit")

	for {
		// Print prompt
		fmt.Print(">>> ")

		// Read input
		readline := func() ([]byte, error) {
			if !scanner.Scan() {
				return nil, io.EOF
			}
			line := strings.TrimSpace(scanner.Text())
			if line == "exit" {
				return nil, errExit
			}
			if line == "" {
				return nil, nil
			}
			return []byte(line + "\n"), nil
		}

		// Execute the input
		if err := rep(readline, thread, globals); err != nil {
			if err == io.EOF {
				break
			}
			if err == errExit {
				os.Exit(0)
			}
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		}
	}
}

// rep reads, evaluates, and prints one item.
//
// It returns an error (possibly readline.ErrInterrupt)
// only if readline failed. Starlark errors are printed.
func rep(readline func() ([]byte, error), thread *starlark.Thread, globals starlark.StringDict) error {
	eof := false

	f, err := syntax.ParseCompoundStmt("<stdin>", readline)
	if err != nil {
		if eof {
			return io.EOF
		}
		printError(err)
		return nil
	}

	if expr := soleExpr(f); expr != nil {
		//TODO: check for 'exit'
		// eval
		v, err := evalExprOptions(nil, thread, expr, globals)
		if err != nil {
			printError(err)
			return nil
		}

		// print
		if v != starlark.None {
			fmt.Println(v)
		}
	} else {
		// compile
		prog, err := starlark.FileProgram(f, globals.Has)
		if err != nil {
			printError(err)
			return nil
		}

		// execute (but do not freeze)
		res, err := prog.Init(thread, globals)
		if err != nil {
			printError(err)
		}

		// The global names from the previous call become
		// the predeclared names of this call.
		// If execution failed, some globals may be undefined.
		for k, v := range res {
			globals[k] = v
		}
	}

	return nil
}

var defaultSyntaxFileOpts = &syntax.FileOptions{
	Set:             true,
	While:           true,
	TopLevelControl: true,
	GlobalReassign:  true,
	Recursion:       true,
}

// evalExprOptions is a wrapper around starlark.EvalExprOptions.
// If no options are provided, it uses default options.
func evalExprOptions(opts *syntax.FileOptions, thread *starlark.Thread, expr syntax.Expr, globals starlark.StringDict) (starlark.Value, error) {
	if opts == nil {
		opts = defaultSyntaxFileOpts
	}
	return starlark.EvalExprOptions(opts, thread, expr, globals)
}

func soleExpr(f *syntax.File) syntax.Expr {
	if len(f.Stmts) == 1 {
		if stmt, ok := f.Stmts[0].(*syntax.ExprStmt); ok {
			return stmt.X
		}
	}
	return nil
}

// printError prints the error to stderr,
// or its backtrace if it is a Starlark evaluation error.
func printError(err error) {
	if evalErr, ok := err.(*starlark.EvalError); ok {
		fmt.Fprintln(os.Stderr, evalErr.Backtrace())
	} else {
		fmt.Fprintln(os.Stderr, err)
	}
}

```

### Calling Go Functions Directly from Starlark

In this example, we'll demonstrate how to call Go functions from Starlark scripts. The main approach is:

1. Define a Go function map (GoFuncMap) to register Go functions that can be called from Starlark
2. Implement a glue function (callGoFunc) to serve as a bridge between Starlark and Go functions
3. Register the glue function in Starlark's global environment so Starlark code can use it to call Go functions

Here's a simple example showing how to let Starlark call a Go addition function:

```go
package main

import (
    ...

	"go.starlark.net/starlark"
	"go.starlark.net/syntax"
)

// GoFuncMap stores registered Go functions
var GoFuncMap = map[string]interface{}{
	"Add": Add,
}

func Add(a, b int) int {
	fmt.Println("Hey! I'm a Go function!")
	return a + b
}

// callGoFunc is a Starlark function that calls registered Go functions
func callGoFunc(thread *starlark.Thread, fn *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
	if len(args) < 1 {
		return nil, fmt.Errorf("call_gofunc requires at least one argument (function name)")
	}

	funcName, ok := args[0].(starlark.String)
	if !ok {
		return nil, fmt.Errorf("first argument must be a string (function name)")
	}

	goFunc, ok := GoFuncMap[string(funcName)]
	if !ok {
		return nil, fmt.Errorf("function %s not found", funcName)
	}

	// Convert Starlark arguments to Go values
	goArgs := make([]interface{}, len(args)-1)
	for i, arg := range args[1:] {
		switch v := arg.(type) {
		case starlark.Int:
			if v, ok := v.Int64(); ok {
				goArgs[i] = int(v)
			} else {
				return nil, fmt.Errorf("integer too large")
			}
		case starlark.Float:
			goArgs[i] = float64(v)
		case starlark.String:
			goArgs[i] = string(v)
		case starlark.Bool:
			goArgs[i] = bool(v)
		default:
			return nil, fmt.Errorf("unsupported argument type: %T", arg)
		}
	}

	// Call the Go function
	switch f := goFunc.(type) {
	case func(int, int) int:
		if len(goArgs) != 2 {
			return nil, fmt.Errorf("Add function requires exactly 2 arguments")
		}
		a, ok1 := goArgs[0].(int)
		b, ok2 := goArgs[1].(int)
		if !ok1 || !ok2 {
			return nil, fmt.Errorf("Add function requires integer arguments")
		}
		result := f(a, b)
		return starlark.MakeInt(result), nil
	default:
		return nil, fmt.Errorf("unsupported function type: %T", goFunc)
	}
}

func main() {
	go func() {
		// Create a new Starlark thread
		thread := &starlark.Thread{
			Name: "repl",
			Print: func(thread *starlark.Thread, msg string) {
				fmt.Println(msg)
			},
		}

		// Create a new global environment with call_gofunc
		globals := starlark.StringDict{
			"call_gofunc": starlark.NewBuiltin("call_gofunc", callGoFunc),
		}

		// Create a scanner for reading input
		scanner := bufio.NewScanner(os.Stdin)
		fmt.Println("Starlark REPL (type 'exit' to quit)")
		fmt.Println("Example1: starlark exprs and stmts")
		fmt.Println("Example2: call_gofunc('Add', 1, 2)")

		errExit := errors.New("exit")

		for {
			// Print prompt
			fmt.Print(">>> ")

			// Read input
			readline := func() ([]byte, error) {
                ...
			}

			// Execute the input
			if err := rep(readline, thread, globals); err != nil {
                ...
			}
		}
	}()

	select {}
}

```

### Integrating Starlark into the Debugger

go-delve/delve integrates Starlark and uses the method described in this article to support calling certain internal debugger functions, such as:

```go
//go:generate go run ../../../_scripts/gen-starlark-bindings.go go ./starlark_mapping.go
const (
	dlvCommandBuiltinName        = "dlv_command"
	readFileBuiltinName          = "read_file"
	writeFileBuiltinName         = "write_file"
	commandPrefix                = "command_"
	dlvContextName               = "dlv_context"
	curScopeBuiltinName          = "cur_scope"
	defaultLoadConfigBuiltinName = "default_load_config"
	helpBuiltinName              = "help"
)
```

For example, let's look at the following Go program and use go-delve/delve for automated debugging:

file: main.go (line numbers are preserved here to correspond with the starlark script)

```go
     1 package main                                                                                                        
     2 
     3 import (
     4     "fmt"
     5     "time"
     6 )
     7 
     8 type Person struct {
     9     Name string
    10     Age  int
    11 }
    12 
    13 func main() {
    14     people := []Person{
    15         {Name: "Alice", Age: 25},
    16         {Name: "Bob", Age: 30},
    17         {Name: "Charlie", Age: 35},
    18     }
    19 
    20     for i, p := range people {
    21         fmt.Printf("Processing person %d: %s\n", i, p.Name)
    22         time.Sleep(time.Second) // 添加一些延迟以便于调试
    23         processPerson(p)
    24     }
    25 }
    26 
    27 func processPerson(p Person) {
    28     fmt.Printf("Name: %s, Age: %d\n", p.Name, p.Age)
    29 }
```

Starlark automated debugging script:

file: debug.star

```starlark
# Define a function to print current scope information
def print_scope():
    scope = cur_scope()
    print("Current scope:", scope)
    dlv_command("locals")

# Define a function to set breakpoints and execute debug commands
def debug_person():
    # Print current scope
    print_scope()
    
    # Print value of variable p
    dlv_command("print p")
    
    # Single step execution
    dlv_command("next")
    
    # Print scope again
    print_scope()

# Define a function to save debug information to file
def save_debug_info():
    # Get current scope
    scope = cur_scope()
    
    # Write debug info to file
    debug_info = "Debug session at " + str(time.time()) + "\n"
    debug_info += "Current scope: " + str(scope) + "\n"
    
    # Save to file
    write_file("debug_info.txt", debug_info)

# Main function
def main():
    print("Starting debug session...")
    
    # Set breakpoints
    dlv_command("break main.main")
    dlv_command("break main.processPerson")
    
    # Continue to main.main
    dlv_command("continue")
    
    # Continue to main.processPerson
    dlv_command("continue")
 
    # Execute debug operations
    debug_person()
    
    # Save debug information
    save_debug_info()
    
    print("Debug session completed.")

# Directly call main function (source command will automatically call the defined 'main' function)
#main()
```

Run the debugger with `dlv debug main.go`, and once the debug session is ready, execute `source debug.star`.

```bash
$ tinydbg debug main.go
Type 'help' for list of commands.
(dlv) source debug.star
Starting debug session...
Breakpoint 1 set at 0x49d0f6 for main.main() ./main.go:13
Breakpoint 2 set at 0x49d40e for main.processPerson() ./main.go:27
> [Breakpoint 1] main.main() ./main.go:13 (hits goroutine(1):1 total:1) (PC: 0x49d0f6)
     8: type Person struct {
     9:         Name string
    10:         Age  int
    11: }
    12:
=>  13: func main() {
    14:         people := []Person{
    15:                 {Name: "Alice", Age: 25},
    16:                 {Name: "Bob", Age: 30},
    17:                 {Name: "Charlie", Age: 35},
    18:         }
Processing person 0: Alice
> [Breakpoint 2] main.processPerson() ./main.go:27 (hits goroutine(1):1 total:1) (PC: 0x49d40e)
    22:                 time.Sleep(time.Second) // Add some delay to help with debugging
    23:                 processPerson(p)
    24:         }
    25: }
    26:
=>  27: func processPerson(p Person) {
    28:         fmt.Printf("Name: %s, Age: %d\n", p.Name, p.Age)
    29: }
Current scope: api.EvalScope{GoroutineID:-1, Frame:0, DeferredCall:0}
(no locals)
main.Person {Name: "Alice", Age: 25}
> main.processPerson() ./main.go:28 (PC: 0x49d42a)
    23:                 processPerson(p)
    24:         }
    25: }
    26:
    27: func processPerson(p Person) {
=>  28:         fmt.Printf("Name: %s, Age: %d\n", p.Name, p.Age)
    29: }
Current scope: api.EvalScope{GoroutineID:-1, Frame:0, DeferredCall:0}
(no locals)
Debug session completed.
```

tinydbg currently retains the Starlark implementation from go-delve/delve, with pkg/terminal/starlark.go + pkg/terminal/starlark_test.go containing about 300 lines of code, and starbind/ containing nearly 3000 lines of code, though this part is auto-generated by scripts. Since this code is relatively self-contained and doesn't affect many areas like ebpf-based tracing does, we've decided to keep this code for now. You can find the source code and star scripts used in the above tests in the tinydbg/examples/starlark_demo directory.

### Summary

I first learned about the Starlark language while studying bazelbuild, and gained a deeper understanding of it while learning go-delve/delve. If we are writing a tool or analysis tool and want to expose our underlying capabilities to allow users to freely exercise their creativity, such as how go-delve/delve enables users to perform automated debugging as needed, we can integrate the Starlark interpreter engine into our program. Then through some glue code connecting Starlark with our program, we can enable the Starlark interpreter to call Starlark functions to execute functions defined in our program. This undoubtedly unleashes our program's underlying capabilities, allowing users to further explore and utilize them while maintaining controlled access to those low-level capabilities.

This article demonstrates how to easily integrate Starlark into your Go program. For more usage of Starlark, please refer to [bazelbuild/starlark](https://github.com/bazelbuild/starlark).

The article also introduces debugger integration with Starlark and usage examples. When you need automated testing or want to share your debugging sessions, you can achieve this through this approach.
