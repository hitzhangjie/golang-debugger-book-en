## How acceptMulti Mode Works

### Why Support Multi-Client Debugging

During the community discussion on how to solve this issue [Extend Delve backend RPC API to be able to make a Delve REPL front-end console in a IDE](https://github.com/go-delve/delve/issues/383), a user reported that during a debugging session, when another client attempts to connect (dlv connect), it would error with: "An existing connection was forcibly closed by the remote host." Because of this issue, the dlv maintainers added the --accept-multiclient option to allow multiple client connections.

Although the discussion about this `--accept-multiclient` option was brief, without this option, it would cause significant inconvenience for developers during debugging. Let me give an example of remote debugging:

1. We set up the execution command `tinydbg exec ./binary --headless -- <args>` to run the program being debugged, or `tinydbg attach <pid>` to track an already running process. If startup parameters need to be specified, this process isn't necessarily simple.
2. Then execute `dlv connect <addr:port>` for debugging;
3. Or, we want to use tinydbg command line together with VSCode and GoLand graphical debugging interfaces;
4. Or, when encountering bottlenecks during debugging, we want others to help debug and locate issues together;
5. Or, after completing this debugging session, we don't want the debugged process to end, hoping to use it for subsequent possible debugging activities;

These debugging scenarios listed require our debugger backend to support the ability to accept multiple debugging clients for connection and joint debugging. This scenario and requirement are real, so while the `--accept-multiclient` support only required a few lines of code changes, it's very important for more convenient debugging.

### Single Client vs Multi-Client Mode

tinydbg supports two debug server modes:
1. Single Client Mode (--headless without --accept-multiclient)
    - The server only accepts one client connection
    - When the first client connects and exits, the debug server automatically closes
    - This mode is suitable for single debugging sessions, automatically cleaning up resources after debugging
2. Multi-Client Mode (--headless --accept-multiclient)
    - The server continues running, waiting for multiple client connections
    - Each client can connect and disconnect independently
    - All clients share the same debugging state (breakpoints, watchpoints, etc.)
    - The debugged program continues running until all clients disconnect

The main difference between these two modes lies in how the server handles client connections and manages the debugging session lifecycle.

The implementation principle is as follows, with the key point being whether to reject or allow subsequent incoming connection requests after accepting one:

```go
go func() {
    defer s.listener.Close()
    for {
        c, err := s.listener.Accept()
        if err != nil {
            select {
            case <-s.stopChan:
                return
            default:
                panic(err)
            }
        }
        go s.serveConnection(c)
        if !s.config.AcceptMulti {
            break
        }
    }
}()
```

### Possible Application Scenarios for Multi-Client Mode

Multi-client mode is particularly suitable for the following scenarios:

1. **Continuous Debugging**
   - Multiple clients can connect sequentially
   - No need to restart the debugged program
   - Suitable for long-running debugging tasks

2. **Multi-Tool Collaboration**
   - Can use command-line UI and VSCode debugging panel simultaneously
   - Different tools can share the same debugging state
   - Facilitates using the advantages of different tools

3. **Team Collaboration**
   - Multiple developers can connect to the same debugging session simultaneously
   - Share breakpoints, watchpoints, and other settings
   - Facilitates team collaboration in solving complex problems

### Notes

1. **API Non-Reentrancy**
   - Although multiple client connections are supported, the API is not reentrant
   - Clients need to coordinate usage to avoid conflicts

2. **Mode Limitations**
   - In non-headless mode, the acceptMulti option is ignored
   - Must use both --headless and --accept-multiclient

3. **Client Disconnection Handling**
   - When a client disconnects, you can choose whether to continue executing the debugged program
   - Use the `quit -c` command to continue program execution when disconnecting

### Summary

The acceptMulti mode is an important feature of tinydbg, enabling the debugger to support multiple client connections, which is very useful for multi-round debugging, multi-client debugging, collaborative debugging, and other scenarios. By sharing debugging state, multiple clients can debug sequentially or collaboratively, improving debugging efficiency. It can be said that `--accept-multiclient` support for multi-client mode is not a major feature, but rather a functional point that must be considered in design and implementation.
