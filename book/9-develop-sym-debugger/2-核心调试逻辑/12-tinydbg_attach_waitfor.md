## How Attach WaitFor Works

### Introduction

When debugging processes, we often need to wait for the target process to start before attaching the debugger. The `waitfor` mechanism provides a flexible way to wait for process startup by matching process name prefixes. This article explains in detail how this functionality works in the debugger.

```bash
$ tinydbg help attach
Attach to an already running process and begin debugging it.

This command will cause Delve to take control of an already running process, and
begin a new debug session.  When exiting the debug session you will have the
option to let the process continue or kill it.

Usage:
  tinydbg attach pid [executable] [flags]

Flags:
      --continue                 Continue the debugged process on start.
  -h, --help                     help for attach
      --waitfor string           Wait for a process with a name beginning with this prefix
      --waitfor-duration float   Total time to wait for a process
      --waitfor-interval float   Interval between checks of the process list, in millisecond (default 1)
      ...
```

### Why WaitFor is Needed

We need to wait for processes in the following scenarios:

1. **Process Startup Timing**:
   - Debugging requires ensuring the target process is running
   - Directly attaching to a non-existent process will fail
   - WaitFor ensures attachment only occurs when the process is ready

2. **Process Name Matching**:
   - Sometimes we only know the process name prefix, not the specific PID
   - WaitFor allows matching processes by name prefix
   - This provides a more flexible way to select processes

3. **Timeout Control**:
   - Waiting for process startup requires setting reasonable timeout periods
   - WaitFor provides check interval and maximum wait time parameters
   - This prevents infinite waiting and provides fine-grained control

### Implementation Details

#### Core Data Structure

The WaitFor mechanism is implemented using a simple struct:

```go
type WaitFor struct {
    Name               string        // Process name prefix to match
    Interval, Duration time.Duration // Check interval and maximum wait time
}
```

#### Main Implementation

The core functionality is implemented in the `native` package:

```go
func WaitFor(waitFor *proc.WaitFor) (int, error) {
    t0 := time.Now()
    seen := make(map[int]struct{})
    for (waitFor.Duration == 0) || (time.Since(t0) < waitFor.Duration) {
        pid, err := waitForSearchProcess(waitFor.Name, seen)
        if err != nil {
            return 0, err
        }
        if pid != 0 {
            return pid, nil
        }
        time.Sleep(waitFor.Interval)
    }
    return 0, errors.New("waitfor duration expired")
}
```

#### Process Search Implementation

Process search is implemented through the following steps:

1. Traverse the `/proc` directory to find matching processes
2. Read the process's `cmdline` file to get its name
3. Use a map to record already checked processes
4. Match processes by name prefix

Here's the key part of the implementation:

```go
func waitForSearchProcess(pfx string, seen map[int]struct{}) (int, error) {
    des, err := os.ReadDir("/proc")
    if err != nil {
        return 0, nil
    }
    for _, de := range des {
        if !de.IsDir() {
            continue
        }
        name := de.Name()
        if !isProcDir(name) {
            continue
        }
        pid, _ := strconv.Atoi(name)
        if _, isseen := seen[pid]; isseen {
            continue
        }
        seen[pid] = struct{}{}
        buf, err := os.ReadFile(filepath.Join("/proc", name, "cmdline"))
        if err != nil {
            continue
        }
        // Convert null bytes to spaces for string comparison
        for i := range buf {
            if buf[i] == 0 {
                buf[i] = ' '
            }
        }
        if strings.HasPrefix(string(buf), pfx) {
            return pid, nil
        }
    }
    return 0, nil
}
```

#### Integration with Debugger

The WaitFor mechanism is integrated into the debugger's attach functionality:

```go
func Attach(pid int, waitFor *proc.WaitFor) (*proc.TargetGroup, error) {
    if waitFor.Valid() {
        var err error
        pid, err = WaitFor(waitFor)
        if err != nil {
            return nil, err
        }
    }
    // ... other parts of attach implementation
}
```

### Command Line Support

The debugger provides several command line options for WaitFor:

- `--waitfor`: Specify the process name prefix to wait for
- `--waitfor-interval`: Set the check interval (milliseconds)
- `--waitfor-duration`: Set the maximum wait time

Usage example:
```bash
## Wait for a process named "myapp" to start
debugger attach --waitfor myapp --waitfor-interval 100 --waitfor-duration 10
```

### Code Example

Here's a complete example of using WaitFor:

```go
// Create WaitFor configuration
waitFor := &proc.WaitFor{
    Name: "myapp",
    Interval: 100 * time.Millisecond,
    Duration: 10 * time.Second,
}

// Wait for process and attach
pid, err := native.WaitFor(waitFor)
if err != nil {
    return err
}

// Attach to target process
target, err := native.Attach(pid, nil)
if err != nil {
    return err
}
```

### Summary

The WaitFor mechanism provides a reliable way to attach to processes in debugging scenarios. It ensures we only attach to actually running processes and provides flexibility in how we identify target processes. The implementation is efficient and well-integrated with other debugger features.

### References

1. Linux `/proc` filesystem documentation
2. Go standard library `os` package documentation
3. Debugger source code `pkg/proc/native` package 