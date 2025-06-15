## Connect

### Implementation Goal: `tinydbg connect <addr>`

In remote debugging mode, the connect command is used to connect to a debugger backend, initialize the network communication layer, and then initialize a frontend debugging session, allowing developers to debug interactively.

```bash
$ tinydbg help connect
Connect to a running headless debug server with a terminal client. Prefix with 'unix:' to use a unix domain socket.

Usage:
  tinydbg connect <addr> [flags]

Flags:
  -h, --help   help for connect

Global Flags:
      --init string         Init file, executed by the terminal client.
      --log                 Enable debugging server logging.
      --log-dest string     Writes logs to the specified file or file descriptor (see 'dlv help log').
      --log-output string   Comma separated list of components that should produce debug output (see 'dlv help log')
```

### Basic Knowledge

Compared to attach, exec, debug (or test), and core debugging commands, connect is specifically designed for remote debugging. Since it's remote debugging, it involves the debugger frontend and backend running independently.

The debugger backend can be started using attach, exec, debug (or test), or core commands, combined with the `--headless` parameter to launch a debugger backend that waits for the debugger frontend to communicate via TCPConn or UnixConn using JSON RPC or DAP RPC protocols. In our demo tinydbg, we only support JSON-RPC communication. Regarding DAP (Debug Adapter Protocol), we'll introduce it in the "3-Advanced Feature Extensions" section.

When running the debugger backend, you can specify a listening address using the `-l | --listen` parameter:

```bash
-l, --listen string                    Debugging server listen address. Prefix with 'unix:' to use a unix domain socket. (default "127.0.0.1:0")
```

- default: 127.0.0.1:0, when the port is not specified, a port will be automatically assigned, and the debugger process will print out the listening address for the debugger frontend to connect;
  After integration with VSCode, to make debugging more convenient, the frontend and backend need to agree on the listening address to facilitate VSCode debugger frontend connection;
- Specify a specific IP:PORT if you have planned to use a particular IP:PORT for RPC communication;
- Specify unix:/path-to/socket to use Unix Domain Socket for communication;

If we consider VSCode remote development, container development, and WebIDE remote development, we need to discuss VSCode's C/S separation architecture and plugin running methods (extensionKind, in UI/Local Extension Host, Remote/Workspace Extension Host, or both). If we have time, we'll share how VSCode (C/S), VSCode debugger plugins (local/remote extension host), and debugger frontend/backend (C/S) interact with each other.

OK, let's get back to the main topic and introduce the code implementation of the connect command.

### Code Implementation

In the previous debugger session section, we mentioned the general implementation approach of connect. Let's briefly review it again. The code path for establishing a debugging session is:

```bash
main.go:main.main
    \--> cmds.New(false).Execute()
            \--> connectCommand.Run()
                    \--> connectCmd(...)
                            \--> connect(addr, nil, conf)
                                    \--> conn := netDial(addr)
                                            \--> if isTCPAddress, conn, _ := net.Dial("tcp", addr) 
                                            \--> if isUnixAddress, conn, _ := net.Dial("unix", addr)
                                    \--> client := rpc2.NewClientFromConn(conn)
                                    \--> session := debug.New(client, conf)
                                    \--> session.Run()
                                            \--> forloop
                                                    \--> read input
                                                    \--> parse debugcmd flags args
                                                    \--> session.client.Call('RPCServer.'+method, req, rsp)
                                                            \--> json-rpc over tcpconn or unixconn
                                                    \--> update UI based on rsp
```

When executing the connect command, it roughly follows the above code path. Connect determines whether the parameter addr is a TCP listening address or a Unix domain socket, then establishes the corresponding connection. Once the connection is established, the RPC client can be initialized. Then a debugging session is initialized, and when the debugging session runs, it becomes a REPL-like loop that reads input, parses commands, parameters, and options, then executes them. However, here the execution requires interaction with the debugger server, and almost all debugging commands work this way. The debugging session and debugger server communicate through the established communication link to complete request sending and response receiving. Then, based on the response, the debugger frontend updates the display, such as showing variable values, instruction lists, printing type details, displaying the current program execution instruction address and source code location, etc.

We have already detailed the debugging session initialization, network communication layer initialization process, and the detailed interaction process between the debugger frontend and backend in the debugging session section, so we won't repeat it here.

It's worth mentioning that the debugger backend only accepts multiple incoming client connection requests during execution if `--accept-multiclient` is specified when starting the debugger:
- Client 1 is debugging, and Client 2 wants to connect;
- Client 2 has finished debugging and has disconnected from the debug server, but hasn't killed the process instance, and a client wants to connect;

In both cases, if you want to allow Client 2 to connect, you need to explicitly specify the `--accept-multiclient` option when starting the debugger backend. So why isn't the `--accept-multiclient` option enabled by default?

For common `tinydbg debug ...` operations, since the program is automatically built and started by us, the default expectation after debugging is that this process has been used up and doesn't need to continue existing, so it will prompt the debugger whether to automatically kill the process, and in most cases, people will click "Yes". This is the most common scenario. For cases where debugging is completed once and then initiated again, but in this case, it means the problem can't be determined immediately and requires multiple debugging sessions to track, in this case with a clear requirement, you can directly add the `--accept-multiclient` option when starting. Additionally, if we add this option, during our debugging session, if someone really connects, their debugging actions might affect us. However, allowing multiple clients to log in simultaneously also adds some flexibility, such as allowing multiple people to debug and locate exceptions together.

### Execution Testing

Omitted

### Section Summary

This section introduced the implementation of the connect command, which allows the debugger frontend to connect to an independently running debugger backend process. We detailed the connection establishment process, debugging session initialization, and considerations regarding multi-client connection support. This provides a foundation for understanding how debuggers work in distributed debugging scenarios.
