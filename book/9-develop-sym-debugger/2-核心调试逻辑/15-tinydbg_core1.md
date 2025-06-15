## Core (Part1): ELF Core Dump File Analysis

The Executable and Linkable Format (ELF) 🧝 is used for compiled output (`.o` files), executables, shared libraries, and core dump files. The first few uses are well documented in the [System V ABI specification](http://www.sco.com/developers/devspecs/gabi41.pdf) and [Tool Interface Standard (TIS) ELF specification](http://refspecs.linuxbase.org/elf/elf.pdf), but there seems to be less documentation about the use of ELF format in core dumps.

Before we introduce `tinydbg core [executable] [corefile]` for debugging core files, we must first understand the de facto specification of Core files - what to record, in what format, and how to be compatible with different debuggers. Understanding how Core file content is generated also helps us understand how debuggers should read Core files to reconstruct the problem scene.

This article [Anatomy of an ELF core file](https://www.gabriel.urdhr.fr/2015/05/29/core-file/) summarizes the de facto specification of Core files. Here are some excerpts about Core files from this article.

ps: This section assumes you have read and understood the composition of ELF files, which we introduced in Chapter 7. Additionally, if you want to quickly review ELF file content, you can also refer to this article [knowledge about ELF files](https://www.gabriel.urdhr.fr/2015/09/28/elf-file-format/), which provides a very detailed introduction.

OK, let's first create a core dump file as an example to help with our explanation.

```bash
    pid=$(pgrep xchat)
    gcore $pid
    readelf -a core.$pid
```

### ELF header

The ELF header in Core files is not particularly special. `e_type=ET_CORE` marks this as a core file:

```bash
    ELF Header:
      Magic:   7f 45 4c 46 02 01 01 00 00 00 00 00 00 00 00 00
      Class:                             ELF64
      Data:                              2's complement, little endian
      Version:                           1 (current)
      OS/ABI:                            UNIX - System V
      ABI Version:                       0
      Type:                              CORE (Core file)
      Machine:                           Advanced Micro Devices X86-64
      Version:                           0x1
      Entry point address:               0x0
      Start of program headers:          64 (bytes into file)
      Start of section headers:          57666560 (bytes into file)
      Flags:                             0x0
      Size of this header:               64 (bytes)
      Size of program headers:           56 (bytes)
      Number of program headers:         344
      Size of section headers:           64 (bytes)
      Number of section headers:         346
      Section header string table index: 345
```

### Program headers

The program header table in Core files has some differences in field meanings compared to executable programs, which we'll explain next.

```bash
    Program Headers:
      Type           Offset             VirtAddr           PhysAddr
                     FileSiz            MemSiz              Flags  Align
      NOTE           0x0000000000004b80 0x0000000000000000 0x0000000000000000
                     0x0000000000009064 0x0000000000000000  R      1
      LOAD           0x000000000000dbe4 0x0000000000400000 0x0000000000000000
                     0x0000000000000000 0x000000000009d000  R E    1
      LOAD           0x000000000000dbe4 0x000000000069c000 0x0000000000000000
                     0x0000000000004000 0x0000000000004000  RW     1
      LOAD           0x0000000000011be4 0x00000000006a0000 0x0000000000000000
                     0x0000000000004000 0x0000000000004000  RW     1
      LOAD           0x0000000000015be4 0x0000000001872000 0x0000000000000000
                     0x0000000000ed4000 0x0000000000ed4000  RW     1
      LOAD           0x0000000000ee9be4 0x00007f248c000000 0x0000000000000000
                     0x0000000000021000 0x0000000000021000  RW     1
      LOAD           0x0000000000f0abe4 0x00007f2490885000 0x0000000000000000
                     0x000000000001c000 0x000000000001c000  R      1
      LOAD           0x0000000000f26be4 0x00007f24908a1000 0x0000000000000000
                     0x000000000001c000 0x000000000001c000  R      1
      LOAD           0x0000000000f42be4 0x00007f24908bd000 0x0000000000000000
                     0x00000000005f3000 0x00000000005f3000  R      1
      LOAD           0x0000000001535be4 0x00007f2490eb0000 0x0000000000000000
                     0x0000000000000000 0x0000000000002000  R E    1
      LOAD           0x0000000001535be4 0x00007f24910b1000 0x0000000000000000
                     0x0000000000001000 0x0000000000001000  R      1
      LOAD           0x0000000001536be4 0x00007f24910b2000 0x0000000000000000
                     0x0000000000001000 0x0000000000001000  RW     1
      LOAD           0x0000000001537be4 0x00007f24910b3000 0x0000000000000000
                     0x0000000000060000 0x0000000000060000  RW     1
      LOAD           0x0000000001597be4 0x00007f2491114000 0x0000000000000000
                     0x0000000000800000 0x0000000000800000  RW     1
      LOAD           0x0000000001d97be4 0x00007f2491914000 0x0000000000000000
                     0x0000000000000000 0x00000000001a8000  R E    1
      LOAD           0x0000000001d97be4 0x00007f2491cbc000 0x0000000000000000
                     0x000000000000e000 0x000000000000e000  R      1
      LOAD           0x0000000001da5be4 0x00007f2491cca000 0x0000000000000000
                     0x0000000000003000 0x0000000000003000  RW     1
      LOAD           0x0000000001da8be4 0x00007f2491ccd000 0x0000000000000000
                     0x0000000000001000 0x0000000000001000  RW     1
      LOAD           0x0000000001da9be4 0x00007f2491cd1000 0x0000000000000000
                     0x0000000000008000 0x0000000000008000  R      1
      LOAD           0x0000000001db1be4 0x00007f2491cd9000 0x0000000000000000
                     0x000000000001c000 0x000000000001c000  R      1
    [...]
```

The `PT_LOAD` entries in the program header describe the process's virtual memory areas (VMAs):

* `VirtAddr` is the starting virtual address of the VMA;
* `MemSiz` is the size of the VMA in virtual address space;
* `Flags` are the permissions (read, write, execute) for this VMA;
* `Offset` is the offset of the corresponding data in the core dump file. This is **not** the offset in the original mapped file.
* `FileSiz` is the size of the corresponding data in this core file. VMA mappings of "**read-only files**" that are identical to the source file content are not duplicated in the core file. Their `FileSiz` is 0, and we need to look at the original file to get the content;
* The names of files associated with Non-Anonymous VMAs and their offsets in those files are not described here, but in the `PT_NOTE` segment (whose content will be introduced later).

Since these are VMAs (vm_area), they are all aligned to page boundaries.

We can compare with `cat /proc/$pid/maps` and find the same information:

```bash
    00400000-0049d000 r-xp 00000000 08:11 789936          /usr/bin/xchat
    0069c000-006a0000 rw-p 0009c000 08:11 789936          /usr/bin/xchat
    006a0000-006a4000 rw-p 00000000 00:00 0
    01872000-02746000 rw-p 00000000 00:00 0               [heap]
    7f248c000000-7f248c021000 rw-p 00000000 00:00 0
    7f248c021000-7f2490000000 ---p 00000000 00:00 0
    7f2490885000-7f24908a1000 r--p 00000000 08:11 1442232 /usr/share/icons/gnome/icon-theme.cache
    7f24908a1000-7f24908bd000 r--p 00000000 08:11 1442232 /usr/share/icons/gnome/icon-theme.cache
    7f24908bd000-7f2490eb0000 r--p 00000000 08:11 1313585 /usr/share/fonts/opentype/ipafont-gothic/ipag.ttf
    7f2490eb0000-7f2490eb2000 r-xp 00000000 08:11 1195904 /usr/lib/x86_64-linux-gnu/gconv/CP1252.so
    7f2490eb2000-7f24910b1000 ---p 00002000 08:11 1195904 /usr/lib/x86_64-linux-gnu/gconv/CP1252.so
    7f24910b1000-7f24910b2000 r--p 00001000 08:11 1195904 /usr/lib/x86_64-linux-gnu/gconv/CP1252.so
    7f24910b2000-7f24910b3000 rw-p 00002000 08:11 1195904 /usr/lib/x86_64-linux-gnu/gconv/CP1252.so
    7f24910b3000-7f2491113000 rw-s 00000000 00:04 1409039 /SYSV00000000 (deleted)
    7f2491113000-7f2491114000 ---p 00000000 00:00 0
    7f2491114000-7f2491914000 rw-p 00000000 00:00 0      [stack:1957]
    [...]
```

The first three `PT_LOAD` entries in the core dump map to the VMAs of the `xchat` ELF file:

* `00400000-0049d000`, corresponding to the read-only executable segment VMA;
* `0069c000-006a0000`, corresponding to the read-write segment initialized part VMA;
* `006a0000-006a4000`, the part of the read-write segment not in the `xchat` ELF file (zero-initialized `.bss` segment).

We can compare this with the program headers of the `xchat` program:

```bash
    Program Headers:
      Type           Offset             VirtAddr           PhysAddr
                     FileSiz            MemSiz              Flags  Align
      PHDR           0x0000000000000040 0x0000000000400040 0x0000000000400040
                     0x00000000000001c0 0x00000000000001c0  R E    8
      INTERP         0x0000000000000200 0x0000000000400200 0x0000000000400200
                     0x000000000000001c 0x000000000000001c  R      1
          [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]
      LOAD           0x0000000000000000 0x0000000000400000 0x0000000000400000
                     0x000000000009c4b4 0x000000000009c4b4  R E    200000
      LOAD           0x000000000009c4b8 0x000000000069c4b8 0x000000000069c4b8
                     0x0000000000002bc9 0x0000000000007920  RW     200000
      DYNAMIC        0x000000000009c4d0 0x000000000069c4d0 0x000000000069c4d0
                     0x0000000000000360 0x0000000000000360  RW     8
      NOTE           0x000000000000021c 0x000000000040021c 0x000000000040021c
                     0x0000000000000044 0x0000000000000044  R      4
      GNU_EH_FRAME   0x0000000000086518 0x0000000000486518 0x0000000000486518
                     0x0000000000002e64 0x0000000000002e64  R      4
      GNU_STACK      0x0000000000000000 0x0000000000000000 0x0000000000000000
                     0x0000000000000000 0x0000000000000000  RW     10

     Section to Segment mapping:
      Segment Sections...
       00
       01     .interp
       02     .interp .note.ABI-tag .note.gnu.build-id .gnu.hash .dynsym .dynstr .gnu.version .gnu.version_d .gnu.version_r .rela.dyn .rela.plt .init .plt .text .fini .rodata .eh_frame_hdr .eh_frame
       03     .init_array .fini_array .jcr .dynamic .got .got.plt .data .bss
       04     .dynamic
       05     .note.ABI-tag .note.gnu.build-id
       06     .eh_frame_hdr
       07
```

### Sections

ELF core dump files typically don't contain section headers. The Linux kernel doesn't generate section headers when creating core dump files. GDB generates section headers that match the program header information:

* Sections of type `SHT_NOBITS` don't exist in the core file but reference parts of other existing files;
* Sections of type `SHT_PROGBITS` exist in the core file;
* Section headers of type `SHT_NOTE` map to the `PT_NOTE` program header.

```bash
    Section Headers:
      [Nr] Name              Type             Address           Offset
           Size              EntSize          Flags  Link  Info  Align
      [ 0]                   NULL             0000000000000000  00000000
           0000000000000000  0000000000000000           0     0     0
      [ 1] note0             NOTE             0000000000000000  00004b80
           0000000000009064  0000000000000000   A       0     0     1
      [ 2] load              NOBITS           0000000000400000  0000dbe4
           000000000009d000  0000000000000000  AX       0     0     1
      [ 3] load              PROGBITS         000000000069c000  0000dbe4
           0000000000004000  0000000000000000  WA       0     0     1
      [ 4] load              PROGBITS         00000000006a0000  00011be4
           0000000000004000  0000000000000000  WA       0     0     1
      [ 5] load              PROGBITS         0000000001872000  00015be4
           0000000000ed4000  0000000000000000  WA       0     0     1
      [ 6] load              PROGBITS         00007f248c000000  00ee9be4
           0000000000021000  0000000000000000  WA       0     0     1
      [ 7] load              PROGBITS         00007f2490885000  00f0abe4
           000000000001c000  0000000000000000   A       0     0     1
      [ 8] load              PROGBITS         00007f24908a1000  00f26be4
           000000000001c000  0000000000000000   A       0     0     1
      [ 9] load              PROGBITS         00007f24908bd000  00f42be4
           00000000005f3000  0000000000000000   A       0     0     1
      [10] load              NOBITS           00007f2490eb0000  01535be4
           0000000000002000  0000000000000000  AX       0     0     1
      [11] load              PROGBITS         00007f24910b1000  01535be4
           0000000000001000  0000000000000000   A       0     0     1
      [12] load              PROGBITS         00007f24910b2000  01536be4
           0000000000001000  0000000000000000  WA       0     0     1
      [13] load              PROGBITS         00007f24910b3000  01537be4
           0000000000060000  0000000000000000  WA       0     0     1
    [...]
      [345] .shstrtab         STRTAB           0000000000000000  036febe4
           0000000000000016  0000000000000000           0     0     1
    Key to Flags:
      W (write), A (alloc), X (execute), M (merge), S (strings), l (large)
      I (info), L (link order), G (group), T (TLS), E (exclude), x (unknown)
      O (extra OS processing required) o (OS specific), p (processor specific
```

Note that tinydbg also doesn't generate section headers here, only program headers, because when implementing related functionality, we also referenced some implementation logic from the Linux kernel, and the Linux kernel doesn't generate sections when creating Core files.

### Notes

The `PT_NOTE` program header records additional information, such as CPU register contents for different threads, mapped files associated with each VMA, etc. It consists of a series of [PT_NOTE entries](http://refspecs.linuxbase.org/elf/elf.pdf#page=42), which are [`ElfW(Nhdr)`](https://github.com/lattera/glibc/blob/895ef79e04a953cac1493863bcae29ad85657ee1/include/link.h#L351) structures (i.e., `Elf32_Nhdr` or `Elf64_Nhdr`):

* Originator name;
* Originator-specific ID (4-byte value);
* Binary content.

```bash
    typedef struct elf32_note {
      Elf32_Word    n_namesz;       /* Name size */
      Elf32_Word    n_descsz;       /* Content size */
      Elf32_Word    n_type;         /* Content type */
    } Elf32_Nhdr;

    typedef struct elf64_note {
      Elf64_Word n_namesz;  /* Name size */
      Elf64_Word n_descsz;  /* Content size */
      Elf64_Word n_type;    /* Content type */
    } Elf64_Nhdr;
```

These are the contents in the notes:

```bash
    Displaying notes found at file offset 0x00004b80 with length 0x00009064:
      Owner                 Data size       Description
      CORE                 0x00000088       NT_PRPSINFO (prpsinfo structure)

      CORE                 0x00000150       NT_PRSTATUS (prstatus structure)
      CORE                 0x00000200       NT_FPREGSET (floating point registers)
      LINUX                0x00000440       NT_X86_XSTATE (x86 XSAVE extended state)
      CORE                 0x00000080       NT_SIGINFO (siginfo_t data)

      CORE                 0x00000150       NT_PRSTATUS (prstatus structure)
      CORE                 0x00000200       NT_FPREGSET (floating point registers)
      LINUX                0x00000440       NT_X86_XSTATE (x86 XSAVE extended state)
      CORE                 0x00000080       NT_SIGINFO (siginfo_t data)

      CORE                 0x00000150       NT_PRSTATUS (prstatus structure)
      CORE                 0x00000200       NT_FPREGSET (floating point registers)
      LINUX                0x00000440       NT_X86_XSTATE (x86 XSAVE extended state)
      CORE                 0x00000080       NT_SIGINFO (siginfo_t data)

      CORE                 0x00000150       NT_PRSTATUS (prstatus structure)
      CORE                 0x00000200       NT_FPREGSET (floating point registers)
      LINUX                0x00000440       NT_X86_XSTATE (x86 XSAVE extended state)
      CORE                 0x00000080       NT_SIGINFO (siginfo_t data)

      CORE                 0x00000130       NT_AUXV (auxiliary vector)
      CORE                 0x00006cee       NT_FILE (mapped files)
```

Most data structures (like `prpsinfo`, `prstatus`, etc.) are defined in C header files (such as `linux/elfcore.h`).

#### General Process Information

The `CORE/NT_PRPSINFO` entry defines general process information, such as process state, UID, GID, filename, and (partial) arguments.

The `CORE/NT_AUXV` entry describes the [AUXV auxiliary vector](https://refspecs.linuxfoundation.org/LSB_1.3.0/IA64/spec/auxiliaryvector.html).

#### Thread Information

Each thread has the following entries:

* `CORE/NT_PRSTATUS` (PID, PPID, general register contents, etc.);
* `CORE/NT_FPREGSET` (floating point register contents);
* `CORE/NT_X86_STATE`;
* `CORE/SIGINFO`.

For multi-threaded processes, there are two approaches:

* Either put all thread information in the same `PT_NOTE`, where consumers must guess which thread each entry belongs to (in practice, a new thread is defined by an `NT_PRSTATUS`);
* Or put each thread in a separate `PT_NOTE`.

See the explanation in [LLDB source code](https://github.com/llvm-mirror/lldb/blob/f7adf4b988da7bd5e13c99af60b6f030eb1beefe/source/Plugins/Process/elf-core/ProcessElfCore.cpp#L465):

> If a core file contains multiple thread contexts, there are two forms of data
>
> 1. Each thread context (2 or more NOTE entries) is contained in its own segment (PT_NOTE)
> 2. All thread contexts are stored in a single segment (PT_NOTE). This case is slightly more complex because we must find the start of new threads when parsing. The current implementation marks the start of a new thread when it finds an NT_PRSTATUS or NT_PRPSINFO NOTE entry.

In our `tinydbg> dump [output]` when generating core files, we handle multi-thread information in a single PT_NOTE.

#### File Associations

The `CORE/NT_FILE` entry describes the association between virtual memory areas (VMAs) and files. Each non-anonymous VMA has an entry containing:

* The VMA's location in virtual address space (start address, end address);
* The VMA's offset in the file (page offset);
* The associated filename.

```bash
        Page size: 1
                     Start                 End         Page Offset
        0x0000000000400000  0x000000000049d000  0x0000000000000000
            /usr/bin/xchat
        0x000000000069c000  0x00000000006a0000  0x000000000009c000
            /usr/bin/xchat
        0x00007f2490885000  0x00007f24908a1000  0x0000000000000000
            /usr/share/icons/gnome/icon-theme.cache
        0x00007f24908a1000  0x00007f24908bd000  0x0000000000000000
            /usr/share/icons/gnome/icon-theme.cache
        0x00007f24908bd000  0x00007f2490eb0000  0x0000000000000000
            /usr/share/fonts/opentype/ipafont-gothic/ipag.ttf
        0x00007f2490eb0000  0x00007f2490eb2000  0x0000000000000000
            /usr/lib/x86_64-linux-gnu/gconv/CP1252.so
        0x00007f2490eb2000  0x00007f24910b1000  0x0000000000002000
            /usr/lib/x86_64-linux-gnu/gconv/CP1252.so
        0x00007f24910b1000  0x00007f24910b2000  0x0000000000001000
            /usr/lib/x86_64-linux-gnu/gconv/CP1252.so
        0x00007f24910b2000  0x00007f24910b3000  0x0000000000002000
            /usr/lib/x86_64-linux-gnu/gconv/CP1252.so
        0x00007f24910b3000  0x00007f2491113000  0x0000000000000000
            /SYSV00000000 (deleted)
        0x00007f2491914000  0x00007f2491abc000  0x0000000000000000
            /usr/lib/x86_64-linux-gnu/libtcl8.6.so
        0x00007f2491abc000  0x00007f2491cbc000  0x00000000001a8000
            /usr/lib/x86_64-linux-gnu/libtcl8.6.so
        0x00007f2491cbc000  0x00007f2491cca000  0x00000000001a8000
            /usr/lib/x86_64-linux-gnu/libtcl8.6.so
        0x00007f2491cca000  0x00007f2491ccd000  0x00000000001b6000
            /usr/lib/x86_64-linux-gnu/libtcl8.6.so
        0x00007f2491cd1000  0x00007f2491cd9000  0x0000000000000000
            /usr/share/icons/hicolor/icon-theme.cache
        0x00007f2491cd9000  0x00007f2491cf5000  0x0000000000000000
            /usr/share/icons/oxygen/icon-theme.cache
        0x00007f2491cf5000  0x00007f2491d11000  0x0000000000000000
            /usr/share/icons/oxygen/icon-theme.cache
        0x00007f2491d11000  0x00007f2491d1d000  0x0000000000000000
            /usr/lib/xchat/plugins/tcl.so
    [...]
```

As far as I know (from binutils' `readelf` source code), the format of `CORE/NT_FILE` entries is as follows:

1. Number of mapping entries like NT_FILE (32-bit or 64-bit);
2. pagesize (GDB sets this to 1 instead of actual page size, 32-bit or 64-bit);
3. Format of each mapping entry:
  1. Start address
  2. End address
  3. File offset
4. Path strings for each entry in sequence (null-terminated).

#### Other Information

Custom debugging tools can also generate some customized information, such as reading environment variable information, reading `/proc/<pid>/cmdline` to read process-related startup parameters, executing `go version -m /proc/<pid>/exe` to record the go buildid, vcs.branch, vcs.version, and go compiler version. Recording this information is helpful when analyzing core files offline, as it helps determine matching build artifacts, build environment, and code version, which also aids in troubleshooting.

### Summary

This article introduced the general information structure of core dump files in Linux systems and explained the core dump generation practices of the Linux kernel, gdb, and lldb debuggers. After understanding these, we can begin to introduce our tinydbg's debugging session command `tinydbg> dump [output]` and the core file debugging command `tinydbg core [executable] [core]`. Let's continue.

### References
* [Anatomy of an ELF core file](https://www.gabriel.urdhr.fr/2015/05/29/core-file/)
* [A brief look into core dumps](https://uhlo.blogspot.com/2012/05/brief-look-into-core-dumps.html)
* [linux/fs/binfmt_elf.c](https://elixir.bootlin.com/linux/v4.20.17/source/fs/binfmt_elf.c)
* [The ELF file format](https://www.gabriel.urdhr.fr/2015/09/28/elf-file-format/)