## Extended Reading: Explaining the Difference Between Syntax Analysis and Semantic Analysis

### Review of the Compilation Process

If you've studied compiler principles, you should be familiar with the main steps of the compilation process. The Go compiler's compilation process mainly includes the following steps:

- Lexical Analysis: Converts source code into a stream of tokens, recognizing keywords, identifiers, operators, etc.
- Syntax Analysis: Parses the token stream into an Abstract Syntax Tree (AST).
- Semantic Analysis: Checks the semantics of the AST, handling variable declarations, type checking, scoping, etc.
- Intermediate Code Generation: Converts the AST into Static Single Assignment (SSA) form for optimization.
- Target Code Generation: Converts the SSA intermediate representation into platform-specific assembly code.

> Note: For ELF symbol tables and debug information (DWARF), the compiler collects symbol information and generates DWARF debug data while processing intermediate code.

### Syntax vs. Semantics

Among these, syntax analysis and semantic analysis are not as obviously distinct as the other steps, and if you haven't tried writing a compiler yourself, it's easy to confuse them just from the terminology. In fact, **syntax analysis and semantic analysis are quite different:**

**1. Different Goals**

- **Syntax analysis** mainly aims to verify whether the source code conforms to the language's grammar rules and to convert it into an Abstract Syntax Tree (AST). This step focuses on whether the code's structure is correct, ensuring there are no syntax errors.
- **Semantic analysis** focuses on understanding the meaning and logic of the code. It further processes the generated AST, such as type checking and scope analysis, to ensure the code is semantically correct.

**2. Different Inputs and Outputs**

- **Syntax analysis** takes the source code text as input and outputs an AST representing the code's structure.
- **Semantic analysis** takes the AST as input and outputs an intermediate representation after a series of semantic checks and processing, ensuring each element is logically and type-wise correct.

**3. Different Focuses**

- In **syntax analysis**, the compiler focuses on the formal structure of the code, such as whether tokens are correctly combined into valid statements and expressions.
- In **semantic analysis**, the compiler not only checks structural correctness but also ensures that variables are used according to their declared types, function call arguments match definitions, etc.

**4. Error Types**

- Errors found during **syntax analysis** are usually lexical or syntax errors, such as spelling mistakes, unmatched parentheses, etc.
- Errors found during **semantic analysis** are semantic errors, such as type incompatibility, undeclared variables, etc.

**5. Implementation Steps**

- **Syntax analysis** generally includes:
  - Scanning the source code to generate a token stream.
  - Parsing the token stream to generate an AST.
- **Semantic analysis** generally includes:
  - Building a symbol table to manage variable scopes.
  - Performing type checking to ensure operations are valid.
  - Handling semantic information for expressions and statements.

**6. Implementation in the Go Compiler**

- **Syntax analysis** is mainly implemented by the `ParseFile()` function in `parser.go`, which generates the AST.
- **Semantic analysis** is mainly implemented by the `NewNoder()` and `Noder.Emit()` functions in `noder.go`, which process the intermediate representation and perform type checking.

**7. Example**

Here's a simple example:

```go
func main() {
    var a int
    a = 5
}
```

- **Syntax analysis** will convert this code into an AST, including the function definition, variable declaration, and assignment operation.
- **Semantic analysis** will check on the generated AST:
  - Whether `a` is correctly declared in scope.
  - Whether the assignment of 5 is compatible with the int type.
  - Whether other operations, such as function calls, conform to semantic rules.

Through the above steps and example, you can see that while syntax analysis and semantic analysis are both key stages in the compilation process, they focus on different aspects and handle different content. Syntax analysis ensures the code's structure is correct, while semantic analysis ensures the code is logically sound and error-free.
