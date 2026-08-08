Ito ang buong README.md — kopyahin mo lang lahat, gumawa ng file na README.md sa lua-obfuscator folder mo, i-paste, save, tapos ikaw na ang mag-commit. Palitan mo lang ang <username> ng totoong GitHub username mo sa dalawang clone URL.

``markdown
Solaraph

A source-to-source Lua obfuscator, written from scratch in Lua. It reads a Lua
file, understands it as a full AST (lexer → parser), and rewrites it into
functionally identical but hard-to-read Lua.

Built and tested on Lua 5.4.

Ano ang ginagawa nito

Solaraph is a real compiler pipeline, not a find-and-replace script:

`source.lua → tokens → AST → obfuscation passes → obfuscated.lua
              lexer    parser                      generator`

Obfuscation layers

| Layer              | Ginagawa                                                                                                                 |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| Variable renaming  | Scope-aware — locals become v1, v2, … Globals and built-ins (print, pairs, …) are left untouched so the code still runs. |
| Number obfuscation | Integers become split sums, e.g. 55 → (50 + 5).                                                                          |
| String encryption  | String literals are XOR-encoded and decoded at runtime via a small prelude.                                              |
| Minify             | Removes all whitespace and newlines into one compact line.                                                               |

Ano ang suportado

Functions, local functions, methods (obj:m()), tables, multiple assignment,
if/elseif/else, while, repeat, numeric and generic for, do blocks,
return, break, full operator precedence, and unary operators.

> Note: Solaraph is teaching-grade. It handles a wide class of scripts, but
> some syntax isn't covered yet (e.g. goto/labels). When it hits unsupported
> syntax it errors clearly rather than producing broken output.

Requirements
• Lua 5.4 (string encryption uses the ~
bitwise operator, which needs Lua 5.3+).

Check your install:

`bash
lua -v
`

Installation

`bash
git clone https://github.com/<username>/lua-obfuscator
cd lua-obfuscator
`

Usage

`bash
lua solaraph.lua <input.lua> [output.lua] [flags]
`

If you don't give an output name, it writes <input>.obf.lua next to the input.

Halimbawa

`bash
Obfuscate demo.lua → demo.obf.lua (all layers, minified)
lua solaraph.lua demo.lua

Custom output name
lua solaraph.lua demo.lua secret.lua

Readable version — rename only, no minify, easier to inspect
lua solaraph.lua demo.lua demo.readable.lua --no-minify
`

Verify the result still runs:

`bash
lua demo.obf.lua
`

Flags

| Flag         | Epekto                                    |
| ------------ | ----------------------------------------- |
| --no-minify  | Keep normal formatting (readable output). |
| --no-rename  | Don't rename variables.                   |
| --no-strings | Don't encrypt strings.                    |
| --no-numbers | Don't obfuscate numbers.                  |

Project structure

| File          | Role                                            |
| ------------- | ----------------------------------------------- |
| lexer.lua     | Source string → tokens                          |
| parser.lua    | Tokens → AST                                    |
| generator.lua | AST → Lua source (with minify mode)             |
| renamer.lua   | Obfuscation pass: scope-aware variable renaming |
| numenc.lua    | Obfuscation pass: number obfuscation            |
| stringenc.lua | Obfuscation pass: string encryption             |
| solaraph.lua  | CLI entry point — ties every pass together      |

Roadmap
• [x] Lexer
• [x] Parser (tables, methods, multiple assignment)
• [x] Code generator (+ minify)
• [x] Variable renaming
• [x] Number obfuscation
• [x] String encryption
• [x] CLI tool
• [ ] Parser completeness (goto/labels)
• [ ] Dead code injection
• [ ] Control-flow flattening
• [ ] VM-based obfuscation

License

MIT
`

Dalawang bagay bago mo i-commit:

Palitan ang <username>` sa dalawang clone URL ng totoong GitHub username mo.
Gawing public ang repo kung private pa — kung hindi, walang makaka-clone. Sa GitHub: repo → Settings → General → Danger Zone → Change visibility → Public.

Kung gusto mo ng buong source ng ibang files (lexer, parser, generator, atbp.) na naka-paste rin dito, sabihin mo lang — nasa transcript mo silang lahat, kaya kaya kong ilabas nang buo.
