## Guess SubstitutePath Automatically

During the debugging process, source code path mapping is an important issue. This article explains in detail how the substitutePath functionality works in the Delve debugger.

### Path Mapping Challenges

During debugging, we face two main path mapping challenges:

#### Go Standard Library Source Code Mapping

- **Problem**: The Go source code path on the client debugging machine is inconsistent with the Go source code path used when building the target program on the server
- **Solution**:
  - First check if the Go versions match
  - If versions don't match, disable source code display
  - If versions match, attempt path mapping

#### Debug Program Source Code Mapping

- **Problem**: The program source code path on the client machine is inconsistent with the source code path used when building the program on the target machine
- **Solution**:
  - Maintain source code consistency as much as possible
  - Map through module paths and package paths

### How Mapping Guessing Works

#### Input Parameters

```go
type GuessSubstitutePathIn struct {
    ClientModuleDirectories map[string]string  // Client module directory mapping
    ClientGOROOT           string             // Client Go installation path
    ImportPathOfMainPackage string            // Main package import path
}
```

#### Core Algorithm

1. **Information Collection**:
   - Extract all function information from the binary file
   - Get package name and compilation unit information for each function
   - Record the server-side GOROOT path

2. **Module Path Analysis**:
   - For each function, analyze its package and module
   - Establish mapping relationships between package names and module names
   - Exclude interference from inline functions

3. **Path Matching**:
   - Use statistical methods to determine the most likely path mapping
   - Set minimum evidence count (minEvidence = 10)
   - Set decision threshold (decisionThreshold = 0.8)

4. **Mapping Generation**:
   - Generate server-to-client path mappings for each module
   - Handle special GOROOT mapping

#### Key Code Logic

```go
// Count each possible server-side directory
serverMod2DirCandidate[fnmod][dir]++

// Make decisions when sufficient evidence is collected
if n > minEvidence && float64(serverMod2DirCandidate[fnmod][best])/float64(n) > decisionThreshold {
    serverMod2Dir[fnmod] = best
}
```

### Practical Application Examples

#### Go Standard Library Mapping

```
Server-side: /usr/local/go/src/runtime/main.go
Client-side: /home/user/go/src/runtime/main.go
Mapping: /usr/local/go -> /home/user/go
```

#### Project Source Code Mapping

```
Server-side: /build/src/github.com/user/project/main.go
Client-side: /home/user/project/main.go
Mapping: /build/src/github.com/user/project -> /home/user/project
```

### Best Practices

1. **Version Consistency**:
   - Ensure the client and target program use the same Go version
   - Disable source code display when versions differ

2. **Source Code Management**:
   - Maintain consistent source code structure between client and target program
   - Use version control to ensure source code synchronization

3. **Module Path**:
   - Set module paths correctly
   - Ensure accurate client module directory mapping

### Summary

The SubstitutePath functionality intelligently analyzes debug information in binary files to automatically establish path mapping relationships between the server and client. This feature is particularly important for remote debugging and cross-environment debugging, as it ensures the debugger correctly locates and displays source code files.

Through proper configuration and source code management, we can fully utilize this functionality to improve debugging efficiency. 
