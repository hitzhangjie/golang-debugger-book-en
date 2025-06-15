## Macro Information

Most debuggers have difficulty displaying and debugging code with macros. Users see the original source file with macros, while the code corresponds to the expanded macro content.

The DWARF debugging information includes descriptions of macros defined in the program. This is very basic information, but debuggers can use it to display macro values or translate macros into the corresponding source language.

Programming languages like C/C++ that need to support macros require this information (.debug_macro). Since Go language doesn't use macros, we won't elaborate on this here.

