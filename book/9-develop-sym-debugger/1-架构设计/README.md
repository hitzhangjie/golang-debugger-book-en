## Architecture Design

At the beginning of this chapter, we introduced the necessity of debuggers in the software development lifecycle. In this section, we will analyze the various challenges faced by software debugging in real development, testing, and production environments, including multi-platform compatibility, remote debugging, security isolation, performance impact, and more.

To address these challenges, modern debuggers commonly adopt a frontend-backend separation architecture, supporting independent extension and evolution of both ends. We typically divide debuggers into debugger frontend and debugger backend:
- The frontend can be divided into UI layer and service layer:
    - UI layer is extensible: to support different debugging interfaces, such as dlv command-line interface, gdlv graphical interface, or visual debugging plugins in VSCode;
    - Service layer is extensible: to support local debugging (net.Pipe), remote debugging (JSON-RPC), or integration with more IDEs (DAP protocol);
- The backend can be divided into service layer, symbol layer, and target layer:
    - Service layer is extensible: (details omitted)
    - Symbol layer is extensible: can support different file formats (ELF, PE, MachO), different debugging symbol information (DWARF, COFF, Stabs), and different programming languages (Go, C, C++, Rust);
    - Target layer is extensible: can support different operating systems (Windows, Linux, macOS) and different hardware platforms (amd64, arm64, powerpc);

OK, let's explore the challenges faced by modern debuggers and how to solve these problems through reasonable architecture design. Let's Go!