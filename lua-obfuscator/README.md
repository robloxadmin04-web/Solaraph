# Solaraph

A source-to-source **Lua obfuscator with a full-program virtual machine**, written from scratch in Lua.

Solaraph reads a Lua file, understands it as a complete AST (lexer → parser), and rewrites it into functionally identical but hard-to-read Lua. Its strongest layer compiles your code into a **custom register-based bytecode** that runs inside an embedded VM — the whole program executes as encrypted, per-build-randomized, tamper-protected bytecode rather than plain Lua.

Built and tested on **Lua 5.4** (needs 5.3+ for bitwise operators).

---

## What it does

Solaraph is a real compiler pipeline, not a find-and-replace script:

```
source.lua
   │  lexer        source string → tokens
   │  parser       tokens → AST
   │  passes       constant folding, control-flow flattening, rename,
   │               number obfuscation, VM virtualization, string encryption,
   │               dead code injection
   │  generator    AST → Lua source (with minify)
   ▼
obfuscated.lua
```

### The virtual machine

The centerpiece is a **full-program register-based VM**. Instead of emitting your logic as readable Lua, Solaraph compiles it into bytecode for a small interpreter that ships with the output:

```
your code  →  __vmmain()   -- runs a tree of bytecode "protos"
```

The VM handles a wide class of real Lua:

- Local variables (as registers) and function parameters
- Arithmetic, concatenation, comparison, unary operators
- Function calls, including nested calls inside expressions
- Global lookup and assignment
- `if` / `elseif` / `else`, `while`, numeric `for`, `repeat` / `until`
- **Nested functions** (`local function`, function literals), **closures**, **upvalues**, and **recursion**
- **Tables**, field/index access, table assignment
- **Method calls** (`obj:method()`) with metatable `__index` chains — full OOP
- **Generic `for`** (`pairs` / `ipairs` iterators)
- **Multiple assignment** (`a, b = b, a` — true parallel evaluation)
- **Varargs** (`...`) and **multiple return values**

If the VM hits something it doesn't cover yet, it **leaves that function as normal Lua** (a safe fallback) — the script never breaks, the VM coverage just shrinks for that piece.

### Security layers on the bytecode

| Layer | What it does |
| --- | --- |
| **Per-proto encryption** | Every function's bytecode is XOR-encrypted with its own key, decrypted at runtime. |
| **Per-build randomization** | The opcode numbers are shuffled into a new random mapping on every obfuscation, so a decoder built for one output does not work on another. |
| **Anti-tamper** | Each proto carries a checksum, re-verified at runtime. If a single byte of the bytecode is edited, the script stops with an error. Uses only pure arithmetic — no `debug` library, no `string.dump`, no file I/O — so it works inside restricted sandboxes (e.g. Roblox executors) instead of failing silently. |

### Other obfuscation passes

| Layer | What it does |
| --- | --- |
| Constant folding | Pre-computes constant expressions, e.g. `(2 + 3) * 4` → `20`. |
| Control-flow flattening | Turns straight-line statement sequences into a dispatch loop / state machine. |
| Variable renaming | Scope-aware — locals become `_v1`, `_v2`, … Globals and built-ins (`print`, `pairs`, …) are left untouched. |
| Number obfuscation | Integers become split sums, e.g. `55` → `(50 + 5)`. |
| String encryption | String literals are XOR-encoded and decoded at runtime via a small prelude. |
| Dead code injection | Inserts `if false then … end` garbage blocks that never run. |
| Minify | Collapses whitespace and newlines into one compact line. |

---

## Requirements

- **Lua 5.4** (string encryption and bytecode encryption use the `~` bitwise operator, which needs Lua 5.3+).

Check your install:

```bash
lua -v
```

---

## Installation

```bash
git clone https://github.com/robloxadmin04-web/Solaraph
cd Solaraph/lua-obfuscator
```

---

## Usage (CLI)

```bash
lua solaraph.lua <input.lua> [output.lua] [flags]
```

If you don't give an output name, it writes `<input>.obf.lua` next to the input.

### Examples

```bash
# Obfuscate demo.lua → demo.obf.lua (all layers, minified)
lua solaraph.lua demo.lua

# Custom output name
lua solaraph.lua demo.lua secret.lua

# Readable version — easier to inspect (no minify, no strings, no dead code)
lua solaraph.lua demo.lua demo.readable.lua --no-minify --no-strings --no-dead
```

Verify the result still runs and matches the original:

```bash
lua demo.obf.lua
lua demo.lua
```

### Flags

| Flag | Effect |
| --- | --- |
| `--no-fold` | Don't constant-fold. |
| `--no-flatten` | Don't flatten control flow. |
| `--no-rename` | Don't rename variables. |
| `--no-numbers` | Don't obfuscate numbers. |
| `--no-vm` | Don't virtualize into bytecode. |
| `--no-strings` | Don't encrypt strings. |
| `--no-dead` | Don't inject dead code. |
| `--no-minify` | Keep normal formatting (readable output). |

### Pipeline order

Passes run in this order (each can be disabled with its flag):

```
fold → flatten → rename → numbers → vm → strings → dead → minify
```

The order matters — for example, folding runs before number obfuscation so constants are computed first, and the VM runs after renaming so it captures the final variable names.

---

## Usage (Web)

Solaraph also ships a browser interface (`index.html`) that runs the **entire pipeline client-side** using [Fengari](https://fengari.io/) (a Lua VM compiled to JavaScript). No backend needed — it fetches the `.lua` modules from the same folder and obfuscates in the browser.

- Drag-and-drop a file or a whole folder, or use the Open button
- Supports `.lua`, `.txt`, `.luau`, and other text formats
- Toggle any pass on/off
- Copy or download the output (`<name>.obf.lua`)
- UTF-8 throughout — no mojibake

Because it fetches the module files, it must be **served**, not opened as a `file://` page:

```bash
cd lua-obfuscator
python -m http.server 8000
# open http://localhost:8000
```

To deploy: host the `lua-obfuscator` folder as a **static site** (Render Static Site, GitHub Pages, etc.). No build step required.

---

## Project structure

| File | Role |
| --- | --- |
| `lexer.lua` | Source string → tokens |
| `parser.lua` | Tokens → AST |
| `generator.lua` | AST → Lua source (with minify mode) |
| `constfold.lua` | Pass: constant folding |
| `cflatten.lua` | Pass: control-flow flattening |
| `renamer.lua` | Pass: scope-aware variable renaming |
| `numenc.lua` | Pass: number obfuscation |
| `stringenc.lua` | Pass: string encryption |
| `deadcode.lua` | Pass: dead code injection |
| `vm.lua` | Pass: full-program VM (compiler + interpreter + encryption + randomization + anti-tamper) |
| `solaraph.lua` | CLI entry point — ties every pass together |
| `index.html` | Browser interface (runs the pipeline via Fengari) |

---

## Roadmap

### Compiler foundation
- [x] Lexer
- [x] Parser (tables, methods, multiple assignment)
- [x] Code generator (+ minify)
- [x] CLI tool
- [x] Web interface

### Obfuscation passes
- [x] Variable renaming
- [x] Number obfuscation
- [x] String encryption
- [x] Constant folding
- [x] Dead code injection
- [x] Control-flow flattening

### Full-program virtual machine
- [x] Register-based core (locals, arithmetic, calls)
- [x] Jumps (`if` / `while` / numeric `for`)
- [x] Function parameters
- [x] Closures, upvalues, recursion
- [x] Tables, index/field, method calls, generic `for`
- [x] `repeat` / `until`, multiple assignment, varargs, multiple return
- [x] Per-proto bytecode encryption
- [x] Per-build opcode randomization
- [x] Anti-tamper (executor-safe checksum)

### Not yet covered (safe fallback → stays normal Lua)
- [ ] `goto` / labels
- [ ] Some multi-value table constructors

---

## Notes

- Solaraph is teaching-grade but capable — it virtualizes a broad subset of real Lua. When it meets syntax it doesn't support, it errors clearly (parser) or falls back to normal code (VM) rather than producing broken output.
- Intended for protecting your **own** scripts.

## License

MIT
