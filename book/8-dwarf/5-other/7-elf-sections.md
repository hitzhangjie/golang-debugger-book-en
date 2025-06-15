## ELF Sections

Although DWARF is designed to work with any object file format, it is most often used with ELF, and the examples provided by the author are mainly based on Linux.

DWARF debugging information is categorized and stored in different sections according to the type of object being described. All section names start with the prefix `.debug_`. To improve efficiency, most references to DWARF data are made using offsets relative to the current compilation unit, rather than inefficient operations like repeated storage or traversal.

Common ELF sections and their contents are as follows:

1. .debug_abbrev: Stores abbreviation information used in .debug_info;
2. .debug_aranges: Stores an accelerated access lookup table for querying compilation unit information by memory address;
3. .debug_frame: Stores call stack frame information;
4. .debug_info: Stores core DWARF data, including DIEs describing variables, code, etc.;
5. .debug_line: Stores the line number program (the program instructions are executed by the line number table state machine, which builds the complete line number table);
6. .debug_loc: Stores location description information;
7. .debug_macinfo: Stores macro-related description information;
8. .debug_pubnames: Stores an accelerated access lookup table for querying global objects and functions by name;
9. .debug_pubtypes: Stores an accelerated access lookup table for querying global types by name;
10. .debug_ranges: Stores address ranges referenced in DIEs;
11. .debug_str: Stores the string table referenced in .debug_info, also accessed by offset;
12. .debug_types: Stores DIEs describing data types;

All this information is stored in sections with the .debug_ prefix. The relationships between these sections are shown in the diagram below (DWARFv4 Appendix B) for an intuitive understanding. Note that there are some changes in DWARF v5, such as .debug_types being deprecated, and .debug_pubnames and .debug_pubtypes being replaced by .debug_names, but since Go has mainly used DWARF v4 since version 1.12, we only need to be aware of the changes from v4 to v5.

<img alt="dwarfv4-sections" src="assets/dwarfv4-sections.jpg" width="480px"/>

Newer versions of compilers and linkers aim to reduce the size of binary files when generating DWARF debugging information, and may enable data compression accordingly. For example, new versions of Go support compressing debugging information, such as with `-ldflags='-dwarfcompress=true'` (the default is true). Initially, compressed debug sections were written to sections with the `.zdebug_` prefix instead of `.debug_`, but now new versions of Go have adjusted this so that compressed data is also written to `.debug_` sections by default. Whether compression is enabled and the specific compression algorithm used are set via Section Flags.

To better support debuggers that do not support decompression:

- Old versions of Go: Compressed DWARF data is written to sections with the `.zdebug_` prefix, such as `.zdebug_info`, and not to `.debug_` sections, to avoid parsing or debugging errors;
- New versions of Go: Usually provide an option to disable compression, such as specifying the linker option `-ldflags=-dwarfcompress=false` to prevent compression of debugging information;

To better learn and master DWARF (or ELF), it is essential to be familiar with some common tools, such as `readelf --debug-dump=<section>`, `objdump --dwarf=<section>`, dwarfdump, and nm. Additionally, I have personally written a visualization tool: [hitzhangjie/dwarfviewer](https://github.com/hitzhangjie/dwarfviewer), which currently supports navigation-style browsing of DIE information and viewing the line number information table of compilation units, among other features. I recommend using this tool to assist with learning.

> ps: I also found some other DWARF visualization tools on Github, such as dwex, dwarftree, dwarfexplorer, and dwarfview, but the user experience was not great—many lacked updates, had dependency management issues making them hard to install, or had limited functionality. None of them worked smoothly for me, which is why I ended up writing dwarfviewer myself.
