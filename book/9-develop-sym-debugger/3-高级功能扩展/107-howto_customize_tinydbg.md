## tinydbg Configuration System Design and Implementation

tinydbg provides a flexible configuration system that allows users to customize the debugger's behavior according to their preferences. This article details the design and implementation of the configuration system.

### Configuration Command Usage

tinydbg provides the following configuration commands:

1. `config -list`: List all available configuration items and their current values
2. `config -save`: Save current configuration to the config file
3. `config <name> <value>`: Set the value of a specified configuration item

### Supported Configuration Items

tinydbg supports the following configuration items:

1. **Command Aliases (aliases)**
   - Allows creating aliases for commands
   - Example: `config alias print p` sets `p` as an alias for the `print` command

2. **Source Path Substitution Rules (substitute-path)**
   - Used to rewrite source code paths stored in program debug information
   - Particularly useful when source code is moved between compilation and debugging
   - Supports the following operations:
     - `config substitute-path <from> <to>`: Add a substitution rule
     - `config substitute-path <from>`: Delete a specified rule
     - `config substitute-path -clear`: Clear all rules
     - `config substitute-path -guess`: Automatically guess substitution rules

3. **String Length Limit (max-string-len)**
   - Controls the maximum string length read when using print, locals, args, and vars commands
   - Default value: 64

4. **Array Value Limit (max-array-values)**
   - Controls the maximum number of array items read when using print, locals, args, and vars commands
   - Default value: 64

5. **Variable Recursion Depth (max-variable-recurse)**
   - Controls the output evaluation depth for nested struct members, array and slice items, and dereferenced pointers
   - Default value: 1

6. **Disassembly Style (disassemble-flavor)**
   - Allows users to specify the syntax style for assembly output
   - Available values: "intel"(default), "gnu", "go"

7. **Location Expression Display (show-location-expr)**
   - Controls whether the whatis command prints DWARF location expressions for its arguments

8. **Source Code List Color Settings**
   - `source-list-line-color`: Source code line number color
   - `source-list-arrow-color`: Source code arrow color
   - `source-list-keyword-color`: Source code keyword color
   - `source-list-string-color`: Source code string color
   - `source-list-number-color`: Source code number color
   - `source-list-comment-color`: Source code comment color
   - `source-list-tab-color`: Source code tab color

9. **Other Display Settings**
   - `prompt-color`: Prompt line color
   - `stacktrace-function-color`: Function name color in stack trace
   - `stacktrace-basename-color`: Path basename color in stack trace
   - `source-list-line-count`: Number of lines to display above and below cursor when calling printfile()
   - `position`: Controls how program current position is displayed (source/disassembly/default)
   - `tab`: Controls what is printed when encountering '\t' in source code

### Configuration File Storage

Configuration files are stored in the following locations:

1. If `XDG_CONFIG_HOME` environment variable is set:
   - `$XDG_CONFIG_HOME/tinydbg/config.yml`

2. On Linux systems:
   - `$HOME/.config/tinydbg/config.yml`

3. Other systems:
   - `$HOME/.tinydbg/config.yml`

### Configuration Implementation Details

#### Configuration Loading

The configuration system loads configurations through the `LoadConfig()` function in `pkg/config/config.go`:

1. First checks and creates the configuration directory
2. Checks for existence of old version configuration files and migrates to new location if found
3. Opens the configuration file, creates default configuration if it doesn't exist
4. Uses YAML parser to parse configuration file content into the `Config` struct

#### Configuration Application

Main application points of configuration in the debugger:

1. **Command Aliases**
   - Merged into the command system during `DebugSession` initialization via `cmds.Merge(conf.Aliases)`
   - Allows users to use custom short commands

2. **Path Substitution**
   - Applied through the `substitutePath()` method
   - Used when finding source code locations to ensure the debugger can find the correct source files

3. **Variable Loading Configuration**
   - Converts configuration to `api.LoadConfig` through the `loadConfig()` method
   - Affects behavior of variable viewing commands (such as print, locals, args, etc.)
   - Controls limits for string length, array size, and recursion depth

4. **Display Settings**
   - Affects debugger output format and colors
   - Applied through terminal output functions
   - Controls display method for source code listing and stack traces

#### Configuration Saving

Configuration is saved through the `SaveConfig()` function:

1. Serializes the `Config` struct to YAML format
2. Writes to the configuration file
3. Maintains persistence of user custom settings

### Usage Examples

1. Setting command aliases:
```
config alias print p
config alias next n
```

2. Configuring source path substitution:
```
config substitute-path /original/path /new/path
```

3. Adjusting variable display limits:
```
config max-string-len 128
config max-array-values 100
config max-variable-recurse 2
```

4. Customizing display settings:
```
config source-list-line-count 10
config disassemble-flavor gnu
```

These configurations help users optimize their debugging experience and improve debugging efficiency according to their needs. 