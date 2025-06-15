## go tool link: Debug Information Generation

### ld.Main()->dwarfGenerateDebugSyms()

Below is the path where the linker generates all DWARF debug information,

file: cmd/link/internal/ld/main.go

```go
func Main() {
    ...

    // entry1: generate dwarf data .debug_info for all types, variables, ...
    dwarfGenerateDebugInfo(ctxt)
    ...

    // entry2: generate dwarf data for all other .debug_ sections
    dwarfGenerateDebugSyms(ctxt)   
    ...

    // compress generated dwarf data
    dwarfcompress(ctxt) 
    ...
}
```

Let's analyze the relationship between these two functions:

1. From the code comments, you can see these two functions are the two main entry points for generating DWARF debug information:

```go
// dwarfGenerateDebugInfo generated debug info entries for all types,
// variables and functions in the program.
// Along with dwarfGenerateDebugSyms they are the two main entry points into
// dwarf generation: dwarfGenerateDebugInfo does all the work that should be
// done before symbol names are mangled while dwarfGenerateDebugSyms does
// all the work that can only be done after addresses have been assigned to
// text symbols.
```

2. Their main differences are in execution timing and responsibilities:

- `dwarfGenerateDebugInfo`:

  - Executes before symbol names are mangled (for example, the source code function `func Add(a, b int) int` might become `go.info.Add$main$int$int$int` after name mangling)
  - Responsible for generating debug info entries for all types, variables, and functions
  - Mainly handles the content generation of DWARF information
- `dwarfGenerateDebugSyms`:

  - Executes after addresses have been assigned to text symbols
  - Responsible for generating debug symbols
  - Mainly handles the layout and final output of DWARF information

3. From the call order in `main.go`, you can see their execution sequence:

```go
bench.Start("dwarfGenerateDebugInfo")
dwarfGenerateDebugInfo(ctxt)

// ... other operations in between ...

bench.Start("dwarfGenerateDebugSyms")
dwarfGenerateDebugSyms(ctxt)
```

4. In terms of implementation:

- `dwarfGenerateDebugInfo` mainly does:

  - Initializes DWARF context
  - Generates type information
  - Handles compilation units
  - Collects variable and function information
- `dwarfGenerateDebugSyms` mainly does:

  - Generates .debug_line, .debug_frame, and .debug_loc debug sections
  - Handles address-related information
  - Outputs the final debug information

5. Together, they complete the generation of DWARF debug information, but split into two stages:
   - The first stage (`dwarfGenerateDebugInfo`) focuses on content generation
   - The second stage (`dwarfGenerateDebugSyms`) focuses on layout and output

This staged design makes the generation of DWARF debug information clearer and more controllable, and also fits the workflow of the linker—first determine content, then determine layout and addresses.

### entry1: dwarfGenerateDebugInfo

```go
// dwarfGenerateDebugInfo generated debug info entries for all types,
// variables and functions in the program.
// Along with dwarfGenerateDebugSyms they are the two main entry points into
// dwarf generation: dwarfGenerateDebugInfo does all the work that should be
// done before symbol names are mangled while dwarfGenerateDebugSyms does
// all the work that can only be done after addresses have been assigned to
// text symbols.
func dwarfGenerateDebugInfo(ctxt *Link) {
    ...

    d := &dwctxt{
        linkctxt: ctxt,
        ldr:      ctxt.loader,
        arch:     ctxt.Arch,
        tmap:     make(map[string]loader.Sym),
        tdmap:    make(map[loader.Sym]loader.Sym),
        rtmap:    make(map[loader.Sym]loader.Sym),
    }
    ...
    // traverse the []*sym.Library
    for _, lib := range ctxt.Library {

        consts := d.ldr.Lookup(dwarf.ConstInfoPrefix+lib.Pkg, 0)
        // traverse the []*sym.CompilationUnit
        for _, unit := range lib.Units {
            // We drop the constants into the first CU.
            if consts != 0 {
                unit.Consts = sym.LoaderSym(consts)
                d.importInfoSymbol(consts)
                consts = 0
            }
            ctxt.compUnits = append(ctxt.compUnits, unit)
            ...
            newattr(unit.DWInfo, dwarf.DW_AT_comp_dir, dwarf.DW_CLS_STRING, int64(len(compDir)), compDir)
            ...
            newattr(unit.DWInfo, dwarf.DW_AT_go_package_name, dwarf.DW_CLS_STRING, int64(len(pkgname)), pkgname)
            ...
            // Scan all functions in this compilation unit, create
            // DIEs for all referenced types, find all referenced
            // abstract functions, visit range symbols. Note that
            // Textp has been dead-code-eliminated already.
            for _, s := range unit.Textp {
                d.dwarfVisitFunction(loader.Sym(s), unit)
            }
        }
    }

    // Make a pass through all data symbols, looking for those
    // corresponding to reachable, Go-generated, user-visible
    // global variables. For each global of this sort, locate
    // the corresponding compiler-generated DIE symbol and tack
    // it onto the list associated with the unit.
    // Also looks for dictionary symbols and generates DIE symbols for each
    // type they reference.
    for idx := loader.Sym(1); idx < loader.Sym(d.ldr.NDef()); idx++ {
        if !d.ldr.AttrReachable(idx) ||
            d.ldr.AttrNotInSymbolTable(idx) ||
            d.ldr.SymVersion(idx) >= sym.SymVerStatic {
            continue
        }
        t := d.ldr.SymType(idx)
        switch t {
        case sym.SRODATA, sym.SDATA, sym.SNOPTRDATA, sym.STYPE, sym.SBSS, sym.SNOPTRBSS, sym.STLSBSS:
            // ok
        default:
            continue
        }
        // Skip things with no type, unless it's a dictionary
        gt := d.ldr.SymGoType(idx)
        if gt == 0 {
            if t == sym.SRODATA {
                if d.ldr.IsDict(idx) {
                    // This is a dictionary, make sure that all types referenced by this dictionary are reachable
                    relocs := d.ldr.Relocs(idx)
                    for i := 0; i < relocs.Count(); i++ {
                        reloc := relocs.At(i)
                        if reloc.Type() == objabi.R_USEIFACE {
                            d.defgotype(reloc.Sym())
                        }
                    }
                }
            }
            continue
        }
        ...

        // Find compiler-generated DWARF info sym for global in question,
        // and tack it onto the appropriate unit.  Note that there are
        // circumstances under which we can't find the compiler-generated
        // symbol-- this typically happens as a result of compiler options
        // (e.g. compile package X with "-dwarf=0").
        varDIE := d.ldr.GetVarDwarfAuxSym(idx)
        if varDIE != 0 {
            unit := d.ldr.SymUnit(idx)
            d.defgotype(gt)
            unit.VarDIEs = append(unit.VarDIEs, sym.LoaderSym(varDIE))
        }
    }

    d.synthesizestringtypes(ctxt, dwtypes.Child)
    d.synthesizeslicetypes(ctxt, dwtypes.Child)
    d.synthesizemaptypes(ctxt, dwtypes.Child)
    d.synthesizechantypes(ctxt, dwtypes.Child)
}
```

### entry2: dwarfGenerateDebugSyms

```go
// dwarfGenerateDebugSyms constructs debug_line, debug_frame, and
// debug_loc. It also writes out the debug_info section using symbols
// generated in dwarfGenerateDebugInfo2.
func dwarfGenerateDebugSyms(ctxt *Link) {
    if !dwarfEnabled(ctxt) {
        return
    }
    d := &dwctxt{
        linkctxt: ctxt,
        ldr:      ctxt.loader,
        arch:     ctxt.Arch,
        dwmu:     new(sync.Mutex),
    }
    d.dwarfGenerateDebugSyms()
}
```

### ld.Main()→dwarfcompress(*Link)

**The linker performs necessary compression on DWARF debug information**

```go
// dwarfcompress compresses the DWARF sections. Relocations are applied
// on the fly. After this, dwarfp will contain a different (new) set of
// symbols, and sections may have been replaced.
func dwarfcompress(ctxt *Link) {
    ...
}
```
