<!--
Appended after the default system-prompt blocks. Never add a SYSTEM.md instead:
block 0 renders the skill/rule inventories and replacing it hides every skill.
Billed verbatim on every turn of every session - keep it near-empty.
-->

# Operator preferences

- Read narrowly: a line range, not a whole file; find the range with `grep` or `lsp` first.
- Use `lsp` for symbol work (definitions, references, rename, diagnostics) over text search.
- Mark inferred defaults, versions, and interfaces as assumptions, not facts.
- No emoji in repository files, commit messages, or code comments.
- Orchestrating subagents? Follow `skill://delegation`; never do bulk I/O inline.
