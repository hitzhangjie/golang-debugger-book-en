## Discussion: why load buildid sections

### Some conclusions first

There are two main sections related to the build id concept: .note.go.buildid and .note.gnu.build-id. The former is the buildid shown by go tool buildid `<binary>`, and the latter is used by more tools in the Linux ecosystem.

When discussing the ELF file program header table, a question arises: why are .note.go.build and .note.gnu.build-id loaded into memory? Some guesses:

- The program wants to obtain these buildid infos at runtime without reading the ELF file directly;
- When generating a memory dump, the program wants to include this information in the core file, so that other tools can extract the buildid from the core file and match it with symbols.

.note.gnu.build-id is used to track the code version, code directory, and build environment at build time. Some build systems record this buildid and related information, artifacts, separate debug symbols, symbol tables, etc., so that when troubleshooting, these can be loaded as needed.
.note.go.buildid is mainly for internal use by the Go toolchain; external tools should not use this buildid.

### Exploration: pprof profile wants to record the GNU build-id

After reading the Go source code, it seems that pprof wants to record the buildid in the profile info, to help track version, build environment, and symbol info during analysis. This info may be maintained by the build system in a database. But after checking, the buildid here is from .note.gnu.build-id, not the go buildid; the former is more general for tools.

The code to get the GNU build-id from /proc/pid/maps is roughly as follows:

```go
// newProfileBuilder returns a new profileBuilder.
// CPU profiling data obtained from the runtime can be added
// by calling b.addCPUData, and then the eventual profile
// can be obtained by calling b.finish.
func newProfileBuilder(w io.Writer) *profileBuilder {
	zw, _ := gzip.NewWriterLevel(w, gzip.BestSpeed)
	b := &profileBuilder{
		...
	}
	b.readMapping()
	return b
}

// readMapping reads /proc/self/maps and writes mappings to b.pb.
// It saves the address ranges of the mappings in b.mem for use
// when emitting locations.
func (b *profileBuilder) readMapping() {
	data, _ := os.ReadFile("/proc/self/maps")
	parseProcSelfMaps(data, b.addMapping)
	...
}

func parseProcSelfMaps(data []byte, addMapping func(lo, hi, offset uint64, file, buildID string)) {
	// $ cat /proc/self/maps
	// 00400000-0040b000 r-xp 00000000 fc:01 787766                             /bin/cat
	// 0060a000-0060b000 r--p 0000a000 fc:01 787766                             /bin/cat
	// 0060b000-0060c000 rw-p 0000b000 fc:01 787766                             /bin/cat
	// 014ab000-014cc000 rw-p 00000000 00:00 0                                  [heap]
	// 7f7d76af8000-7f7d7797c000 r--p 00000000 fc:01 1318064                    /usr/lib/locale/locale-archive
	// 7f7d7797c000-7f7d77b36000 r-xp 00000000 fc:01 1180226                    /lib/x86_64-linux-gnu/libc-2.19.so
	// 7f7d77b36000-7f7d77d36000 ---p 001ba000 fc:01 1180226                    /lib/x86_64-linux-gnu/libc-2.19.so
	// ...
	// 7f7d77f65000-7f7d77f66000 rw-p 00000000 00:00 0
	// 7ffc342a2000-7ffc342c3000 rw-p 00000000 00:00 0                          [stack]
	// 7ffc34343000-7ffc34345000 r-xp 00000000 00:00 0                          [vdso]
	// ffffffffff600000-ffffffffff601000 r-xp 00000000 00:00 0                  [vsyscall]

	...

	for len(data) > 0 {
		...
		buildID, _ := elfBuildID(file)
		addMapping(lo, hi, offset, file, buildID)
	}
}

// elfBuildID returns the GNU build ID of the named ELF binary,
// without introducing a dependency on debug/elf and its dependencies.
func elfBuildID(file string) (string, error) {
    	...
}
```

### Exploration: test if pprof profile info contains GNU build-id

Based on this, let's generate a pprof profile and see if it records the GNU build-id:

```go
$ cat main.go
package main

import (
	"log"
	"os"
	"runtime/pprof"
)

func main() {
	f, err := os.Create("profile.pb.gz")
	if err != nil {
		log.Fatal(err)
	}
	pprof.StartCPUProfile(f)
	defer pprof.StopCPUProfile()
	var i int64
	for i = 0; i < (1 << 33); i++ {
	}
}
```

```bash
$ go build -ldflags "-B gobuildid" main.go

$ file main
main: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, BuildID[sha1]=f4b5d514bc46fad9417898216b23910ae874a85d, with debug_info, not stripped

$ readelf -n main

Displaying notes found in: .note.gnu.build-id
  Owner                Data size  Description
  GNU                  0x00000014 NT_GNU_BUILD_ID (unique build ID bitstring)
    Build ID: f4b5d514bc46fad9417898216b23910ae874a85d

Displaying notes found in: .note.go.buildid
  Owner                Data size  Description
  Go                   0x00000053 GO BUILDID
   description data: 45 72 5a 36 6f 30 30 37 79 53 35 48 4c 67 41 7a 51 66 6e 52 2f 42 5a 53 51 58 54 4b 49 35 53 61 61 4f 4d 6e 65 49 36 63 56 2f 52 37 41 42 44 38 68 6c 34 6c 6b 65 79 44 66 7a 35 35 69 4d 2f 73 58 6a 56 4b 38 6d 52 58 79 35 4d 79 41 73 46 46 52 6d 74

$ ./main

$ pprof -raw profile.pb.gz | grep -A10 Mappings
Mappings
1: 0x400000/0x4ac000/0x0 /tmp/main f4b5d514bc46fad9417898216b23910ae874a85d [FN]
```

Note that the GNU build-id is not generated by default; you need to explicitly pass -ldflags "-B ..." to specify it. If you don't, there is no such info:

```
$ go build main.go

$ file main
main: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, Go BuildID=..., with debug_info, not stripped

$ readelf -n main

Displaying notes found in: .note.go.buildid
  Owner                Data size  Description
  Go                   0x00000053 GO BUILDID
   description data: 6c 6c 72 6e 31 67 6f 37 32 35 5f 46 32 76 43 76 76 45 54 7a 2f 4f 49 54 65 52 75 36 6b 44 53 63 48 47 36 46 56 6a 64 4b 38 2f 52 37 41 42 44 38 68 6c 34 6c 6b 65 79 44 66 7a 35 35 69 4d 2f 75 6f 54 6f 73 74 44 72 66 42 35 6b 64 77 68 79 36 55 70 47

$ ./main

$ pprof -raw profile.pb.gz | grep -A10 Mappings
Mappings
1: 0x400000/0x4ac000/0x0 /tmp/main  [FN]
```

### Exploration: why does the text segment need to contain buildid? coredump?

But what we want to figure out is, for such a GNU build-id or go buildid, why does the linker define the corresponding segment as PT_LOAD together with the .text section? After all, no tool reads it directly from the binary. In fact, without the original ELF section/segment info, you don't know where in memory the buildid is or how many bytes it occupies, so you still can't parse it. As of now, at least in the official Go toolchain, no tool reads it directly from memory; they all read the ELF file's sections to get the GNU build-id or go buildid.

The only reason I can think of is, if it's not a bug, it's probably so that when generating a core file or memory dump, this info can be saved, making it easier to match the core file's buildid with the build system's info. Here's an example:

Start a Go program myapp and generate a core file

1. go build -o main main.go
2. ./main
3. gcore -o main.core $(pidof main)

Load this core file and read the buildid info

1. gdb main.core main
2. gdb> maintenance info sections
   ```bash
   Exec file:
       `/home/zhangjie/test/main', file type elf64-x86-64.
    [0]     0x00401000->0x00480c75 at 0x00001000: .text ALLOC LOAD READONLY CODE HAS_CONTENTS
    ...
    [18]     0x00400fdc->0x00401000 at 0x00000fdc: .note.gnu.build-id ALLOC LOAD READONLY DATA HAS_CONTENTS
    [19]     0x00400f78->0x00400fdc at 0x00000f78: .note.go.buildid ALLOC LOAD READONLY DATA HAS_CONTENTS
   Core file:
       `/home/zhangjie/test/mycore.444388', file type elf64-x86-64.
    [0]     0x00000000->0x00002798 at 0x00000548: note0 READONLY HAS_CONTENTS
    ...
   ```
3. Dump memory containing the go buildid
   ```bash
   gdb$ dump memory dump.go.buildid 0x00400f78 0x00400fdc
   ```
4. Dump memory containing the GNU build-id
   ```bash
   gdb$ dump memory dump.gnu.buildid 0x00400fdc 0x00401000
   ```

Compare the dumped buildid info in memory with the data in the ELF file:

- Use `strings`, `hexdump` to view the dumped memory data;
- Use `file`, `readelf -S <main> --string-dump=|--hex-dump=` to view ELF file data;
- They are consistent.

### Exploration: does anything except core dumps need to load these sections?

But again, if we can't get the original executable file and its ELF section/segment info, the debugger can't output the addresses of each section in memory, and it's not convenient to analyze after dumping memory. So, the only possible reason for loading .note.gnu.build-id and .note.go.buildid into memory is to include this info in the core file.

> ps: There should be a tool to help track the mapping between the core file's pid and the binary file.

Read More:

- [what does go build -ldflags "-B [0x999|gobuildid]" do](https://go-review.googlesource.com/c/go/+/511475#related-content) , this is to record a GNU buildid in the ELF, but derived from the go buildid, so external systems don't have to recalculate it. This buildid can be used to track whether a build has changed. Some external systems maintain a database mapping code version, symbol info, and buildid for troubleshooting and artifact tracking.
- .note.gnu.build-id can be provided by external systems at build time (go build -ldflags "-B `<yourbuildid>`"), or derived from .note.go.buildid (go build -ldflags "-B gobuildid").
- .note.gnu.build-id is read by many general tools, while .note.go.buildid is intended only for internal use by the Go toolchain.
- In any case, when pprof records the GNU build-id in the profile, it also reads /proc/`<pid>`/maps, finds the mmaped file with executable permissions, then reads the file to find the .note.gnu.build-id section. The code is somewhat repetitive, mainly to avoid importing too many dependencies from the standard library, so it reads and parses it itself.

Well, I'm still a little confused:

- Follow the discussion here: https://groups.google.com/g/golang-nuts/c/Pv5gPIUTVyY
