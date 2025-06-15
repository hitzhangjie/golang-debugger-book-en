## How "go build" works

### Basic Knowledge

The `go build` command is used to build Go programs, and anyone who has used Go should be familiar with it. But have you ever looked closely at what operations this command involves? Or even examined what options `go help build` supports? And what's the difference between it and `go tool compile`?

OK, we're not trying to stir up trouble here. If everything runs smoothly, who would bother to look into how it works internally? After all, we've all studied compilation principles, right? Right. However, I've encountered several situations that forced me to study the toolchain part of the Go source code.

The story began because `go test` does some additional work like generating main function stub code and flags parsing. When Go 1.13 adjusted some flags parsing order code, it caused the efficiency tools I wrote for the [microservice framework trpc](https://github.com/Tencent/trpc) to stop working properly. So I wanted to know how `go test` actually works, and then learned about the `go test -v -x -work` and `go build -v -x -work` options that can show the compilation and build process, and preserve the temporary build directory and artifacts. This led me to gradually understand the detailed execution process of `go build` and `go test`.

If you're interested in this part, you can refer to my blog or read the Go source code yourself.

- [Go Source Code Analysis - go command/go build](https://www.hitzhangjie.pro/blog/2020-09-28-go%E6%BA%90%E7%A0%81%E5%89%96%E6%9E%90-go%E5%91%BD%E4%BB%A4/#go-build)
- [Go Source Code Analysis - go command/go test](https://www.hitzhangjie.pro/blog/2020-09-28-go%E6%BA%90%E7%A0%81%E5%89%96%E6%9E%90-go%E5%91%BD%E4%BB%A4/#go-test)
- [Go Source Code Analysis - go test implementation](https://www.hitzhangjie.pro/blog/2020-02-23-go%E6%BA%90%E7%A0%81%E5%89%96%E6%9E%90-gotest%E5%AE%9E%E7%8E%B0/)

OK, the above articles detail the working process of go tool compile and how go test generates test entry stub code, but they don't mention the roles of go tool asm, pack, link, and buildid in the build process. This article mainly wants to introduce the collaboration between various tools in the compilation toolchain, rather than how a single tool works specifically. So you can skip the above articles and focus on the collaboration goal we care about.

### Example Preparation

Go provides a complete compilation toolchain. Running the `go tool` command shows the compiler compile, assembler asm, linker link, static library packaging tool pack, and some other tools. Let's focus on these first, and we'll introduce others when needed.

```bash
$ go tool

addr2line
asm
buildid
cgo
compile
covdata
cover
doc
fix
link
nm
objdump
pack
pprof
test2json
trace
vet
```

To demonstrate the functionality of the Go compilation toolchain and ensure that compile, asm, linker, and pack tools are all executed, we designed the following project example. See: [golang-debugger-lessons/30_how_gobuild_works](https://github.com/hitzhangjie/golang-debugger-lessons/tree/master/30_how_gobuild_works).

file1: main.go

```go
package main

import "fmt"

func main() {
        fmt.Println("vim-go")
}

```

file2： main.s

```asm
// Copyright 2009 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#include "textflag.h"

// func archSqrt(x float64) float64
TEXT ·archSqrt(SB), NOSPLIT, $0
        XORPS  X0, X0 // break dependency
        SQRTSD x+0(FP), X0
        MOVSD  X0, ret+8(FP)
        RET

```

file3: go.mod

```go
module xx

go 1.22.3
```

### Execution Test

Execute the build command `go build -v -x -work`. Let's introduce these options:

```bash
$ go help build
usage: go build [-o output] [build flags] [packages]
...

The build flags are shared by the build, clean, get, install, list, run,
and test commands:
        -v
                print the names of packages as they are compiled.
        -x
                print the commands.
        -work
                print the name of the temporary work directory and
                do not delete it when exiting.
...
```

Let's look at the output information of the Go build process. Because we added the above options, we can see the various commands executed during the compilation and build process, as well as the artifact information in the temporary build directory:

```bash
$ go build -v -x -work
WORK=/tmp/go-build3686919208
xx
mkdir -p $WORK/b001/
echo -n > $WORK/b001/go_asm.h # internal
cd $HOME/test/xx
🚩/usr/local/go/pkg/tool/linux_amd64/asm -p main -trimpath "$WORK/b001=>" -I $WORK/b001/ -I /usr/local/go/pkg/include -D GOOS_linux -D GOARCH_amd64 -D GOAMD64_v1 -gensymabis -o $WORK/b001/symabis ./main.s
cat >/tmp/go-build3686919208/b001/importcfg << 'EOF' # internal
# import config
packagefile fmt=$HOME/.cache/go-build/1a/1aeb36219a78df45c71149c716fa273649ec980faca58452aaa9184ba8747d05-d
packagefile runtime=$HOME/.cache/go-build/ff/ff9a2c1087b07575bc898f6cbded2c2bd65005b7d3ceaec59cd5dc9ef4dd8bcb-d
EOF
🚩/usr/local/go/pkg/tool/linux_amd64/compile -o $WORK/b001/_pkg_.a -trimpath "$WORK/b001=>" -p main -lang=go1.22 -buildid -wqdZirDfarB_eqBW8ak/-wqdZirDfarB_eqBW8ak -goversion go1.22.3 -symabis $WORK/b001/symabis -c=4 -nolocalimports -importcfg $WORK/b001/importcfg -pack -asmhdr $WORK/b001/go_asm.h ./main.go
🚩/usr/local/go/pkg/tool/linux_amd64/asm -p main -trimpath "$WORK/b001=>" -I $WORK/b001/ -I /usr/local/go/pkg/include -D GOOS_linux -D GOARCH_amd64 -D GOAMD64_v1 -o $WORK/b001/main.o ./main.s
🚩/usr/local/go/pkg/tool/linux_amd64/pack r $WORK/b001/_pkg_.a $WORK/b001/main.o # internal
🚩/usr/local/go/pkg/tool/linux_amd64/buildid -w $WORK/b001/_pkg_.a # internal
cp $WORK/b001/_pkg_.a $HOME/.cache/go-build/a8/a8abe4134014b2c51a6c890004545b5381947bf7b46ad92639eef689fda633c3-d # internal
🚩cat >/tmp/go-build3686919208/b001/importcfg.link << 'EOF' # internal
packagefile xx=/tmp/go-build3686919208/b001/_pkg_.a
packagefile fmt=$HOME/.cache/go-build/1a/1aeb36219a78df45c71149c716fa273649ec980faca58452aaa9184ba8747d05-d
packagefile runtime=$HOME/.cache/go-build/ff/ff9a2c1087b07575bc898f6cbded2c2bd65005b7d3ceaec59cd5dc9ef4dd8bcb-d
packagefile errors=$HOME/.cache/go-build/89/892ce7f48762195fcd6840c12c5f9ce87785a46c63b0dc07a57865a519122f28-d
packagefile internal/fmtsort=$HOME/.cache/go-build/dd/ddfbd9f18abcb9d77cbc7008f82d128c92ff43558ca6b7efc602cda04d7f6442-d
packagefile io=$HOME/.cache/go-build/31/313bc3b844204dfa06aa297c9ccdb7c50e8f5a400e6a2d0194022dc91cc2e16f-d
packagefile math=$HOME/.cache/go-build/d9/d965e602a715d2aed8249bef0203c0cd6e28e87987bf89a859f6166427adcd30-d
packagefile os=$HOME/.cache/go-build/58/5843eabefbd1a16227acf29d96ad1373972d6e6b6db2aabc28c31dc676b5e465-d
packagefile reflect=$HOME/.cache/go-build/bf/bfc22ec705a18fff28097e03b3f013e0ae088c1c0c26c9e1ce7cb5f64106a305-d
packagefile sort=$HOME/.cache/go-build/5e/5ed02f1d2aa35fd662d38bde42d018a9dc81f1c38efb01f210cba4daeaa54d0f-d
packagefile strconv=$HOME/.cache/go-build/da/da217c7dbe580ef4130eed0028da7aa38f8cec1787943e05a24d792dece7f6fa-d
packagefile sync=$HOME/.cache/go-build/6e/6e7ba2c9b00da040587f76dcf4ffc872412e07752bca8280065a41d7eb812e07-d
packagefile unicode/utf8=$HOME/.cache/go-build/a5/a5a3730633d8e8c948dcd5588bce011bd0bda847ecdc1c8b8db8d802d683bb76-d
packagefile internal/abi=$HOME/.cache/go-build/a9/a98408ccf41589aa8b8552dfd9d6ad04a59f9092a73f1d2237a2cca1e9dedfc2-d
packagefile internal/bytealg=$HOME/.cache/go-build/0e/0ef7fc32ea503101ae8a71905a3cc725d82f4436e1fb64e23dabc9a559a81717-d
packagefile internal/chacha8rand=$HOME/.cache/go-build/74/74c0617b7f700fffb3e2ec0a75511fe4b4442142fd8ea9d28af32c8e87f91a2e-d
packagefile internal/coverage/rtcov=$HOME/.cache/go-build/7a/7a8c48e81d34485c0a46d3b762d70b7252ff2a5122d7929976ac1ed316003edf-d
packagefile internal/cpu=$HOME/.cache/go-build/fe/fec87c97c3c638490387af5dca95acb3c7ca00cd3d34c4b665dce7ee8143e59a-d
packagefile internal/goarch=$HOME/.cache/go-build/0b/0bf1fceb5ecd8badbcb18732b4e517a2f4968c9960af4e0175726a2d0ce8ba31-d
packagefile internal/godebugs=$HOME/.cache/go-build/38/387def0b0b5adb9f38a38b5d5301a4816420da0d8d3259354903883ebf3d06ed-d
packagefile internal/goexperiment=$HOME/.cache/go-build/75/755756dfc319f00bcffc6745334076209023acfd72ec9f80b665e0e6b8ca7d37-d
packagefile internal/goos=$HOME/.cache/go-build/e2/e2b0d1019a4dd99ef01bb1d44e3ce0504234e38fe6dd5bf5e94960dfa0eae968-d
packagefile runtime/internal/atomic=$HOME/.cache/go-build/a1/a1ab93c6b342fa82fa28906124bad4a20b5fcb4c23653212bd8973861814fa46-d
packagefile runtime/internal/math=$HOME/.cache/go-build/01/01886c1840e6c3e18c9458497803130f0f40342031eda05d66824c0018d028c2-d
packagefile runtime/internal/sys=$HOME/.cache/go-build/cc/cc237a5895f1661e82c3a240f72bf165b7c98c49f584233dac2c830d1fd96db9-d
packagefile runtime/internal/syscall=$HOME/.cache/go-build/57/57f5686c8b8b90f002882a4d3020168b314b41aff9b7561f3b7fed78985bf682-d
packagefile internal/reflectlite=$HOME/.cache/go-build/fc/fc635c76e99ef1256f0df28309730bc72ada766800e7f75f43eacd4a49ac1825-d
packagefile math/bits=$HOME/.cache/go-build/b4/b49ee4aa1defd50d4d0dcfa35c74bc03c59487b53ad698f824db7d092fe12c89-d
packagefile internal/itoa=$HOME/.cache/go-build/3b/3b4a89fac06e8caef384af48ace1bd2da07824467fe03ad1980ceaeda67983c6-d
packagefile internal/poll=$HOME/.cache/go-build/15/1529e1d377fc16952dcba29f52c6a22a942f61a5059c8f9f959095b5089f1ab8-d
packagefile internal/safefilepath=$HOME/.cache/go-build/64/641d3e96f0d2f68d3472d7b1e6a695ffd71295a1e4c7028f28f4b2ef031b6914-d
packagefile internal/syscall/execenv=$HOME/.cache/go-build/7a/7a6794530a44ee997a0fcbb91f42ac2b1d30a58bf10a82a7ef31b48ee5279ae7-d
packagefile internal/syscall/unix=$HOME/.cache/go-build/97/97c10030ba3200bbde9370669d2d453aab43cfb97af080345505cbba2c755a5c-d
packagefile internal/testlog=$HOME/.cache/go-build/8b/8b88f2b695d41ad558f1e04ab9c0d0385b0ea6f33d09d1cf5f98f1e6e286cf65-d
packagefile io/fs=$HOME/.cache/go-build/53/536225877d64d4db64280b8ceddb0efddf18f3d88f01b0525ed1e1375cdaa4b5-d
packagefile sync/atomic=$HOME/.cache/go-build/a8/a8bc9b57a63c717e41c47f1b2561385a3e99ad7e6f1ac998dfa126558fb2a77c-d
packagefile syscall=$HOME/.cache/go-build/09/090478bb0bb13e1af21c128b423010e7ce96eb925d5fbe48dc0d9e0003bf90ea-d
packagefile time=$HOME/.cache/go-build/c5/c537d62b8dbfa4801ba05947b4cb7ed69b231f00fc275abd287c8d073c846360-d
packagefile internal/unsafeheader=$HOME/.cache/go-build/cb/cbfd364d12f2f9873ac2dbe3f709d93e560c6285abbd5800ed08870b0eef13da-d
packagefile unicode=$HOME/.cache/go-build/a6/a68c49fe16820f404e05e8b52685c89f9824b3a05241e84176f664b6b26def68-d
packagefile slices=$HOME/.cache/go-build/ee/ee5afcbf5fb8afb740704f6aaf3a227ad2304a26abf14792dfe91814e4ecbbe8-d
packagefile internal/race=$HOME/.cache/go-build/c5/c5d493a5513e485a53e716d5a2857cfeef7c998bc786b3d7cdba59c6c6b58ec8-d
packagefile internal/oserror=$HOME/.cache/go-build/70/70c743407927cf8c172a78fddb04df52b02d264b6e7b25dfbdd6179824a327c3-d
packagefile path=$HOME/.cache/go-build/7a/7aac686e9c5205ee6c817e8ed03a971f77c90d90d1fc668cfae54befbcee36e9-d
packagefile cmp=$HOME/.cache/go-build/a1/a12133a77c368ad656257d944b4049e56404cc17981f2a0f1f91ae5ab36419f7-d
modinfo "0w\xaf\f\x92t\b\x02A\xe1\xc1\a\xe6\xd6\x18\xe6path\txx\nmod\txx\t(devel)\t\nbuild\t-buildmode=exe\nbuild\t-compiler=gc\nbuild\tCGO_ENABLED=1\nbuild\tCGO_CFLAGS=\nbuild\tCGO_CPPFLAGS=\nbuild\tCGO_CXXFLAGS=\nbuild\tCGO_LDFLAGS=\nbuild\tGOARCH=amd64\nbuild\tGOOS=linux\nbuild\tGOAMD64=v1\n\xf92C1\x86\x18 r\x00\x82B\x10A\x16\xd8\xf2"
EOF
mkdir -p $WORK/b001/exe/
cd .
🚩/usr/local/go/pkg/tool/linux_amd64/link -o $WORK/b001/exe/a.out -importcfg $WORK/b001/importcfg.link -buildmode=exe -buildid=DnmbfNnl2SoT5ZrYeE1X/-wqdZirDfarB_eqBW8ak/b4gs6m2b26a_jZ5hsnkn/DnmbfNnl2SoT5ZrYeE1X -extld=gcc $WORK/b001/_pkg_.a
/usr/local/go/pkg/tool/linux_amd64/buildid -w $WORK/b001/exe/a.out # internal
mv $WORK/b001/exe/a.out xx
```

### Build Process

In the above output, we've marked (🚩) the execution steps of the tools we're interested in. Here's a simple summary:

1. Prepare a temporary directory for building. All build artifacts will be in this temporary directory. We can cd into this directory to check, but because it involves mv and rm operations, some intermediate artifacts will disappear after the build ends;
2. `go tool asm` processes the assembly source file main.s and outputs the function list symabis defined in the assembly file. If there's no assembly source file, this step will be skipped;
3. `go tool compile` processes the Go source file main.go and outputs the object file. Note that compile directly adds the *.o file to the static library _pkg_.a;
4. `go tool asm` performs assembly operations on the assembly source file and outputs the object file main.o. Note that main.go and other Go files' corresponding object files are added to the static library _pkg_.a;
5. `go tool pack` adds main.o to the static library file _pkg_.a. At this point, all source files in the example module have been compiled, assembled, and added to _pkg_.a;
6. Prepare a list of other object files that need to be linked, including the pre-compiled Go runtime and standard library object files, all written to the importcfg.link file;
7. `go tool link` performs linking operations on _pkg_.a and the Go runtime and standard library recorded in importcfg.link, completes symbol resolution and relocation, generates an executable program a.out, and writes buildid information to its .note.go.buildid;
8. Rename a.out to the module name, which is xx in this case;

At this point, the build process for this example module is complete.

### Summary

OK, this article briefly introduced the internal working process of `go build`, including the compiler, assembler, linker, static library creation tool, and buildid tool. We'll further explain what each of them does. But before we detail how each tool works, we need to turn our attention to their final product - the ELF file. We need to first understand the composition of ELF files (such as section headers, program headers, sections, segments) and their specific roles. After understanding these, we can look back at how these tools coordinate to generate them, and how subsequent tools like loaders and debuggers utilize them.
