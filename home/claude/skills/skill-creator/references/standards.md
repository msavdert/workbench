# Agent Skill Creation Standards & Best Practices

## 1. Frontmatter & Metadata Standards
Every skill MUST have a `SKILL.md` file at its root with valid YAML frontmatter.
- **`name`**: Required. Must be kebab-case (lowercase letters, digits, hyphens only), max 64 characters.
- **`description`**: Required. Max 1024 characters. Cannot contain angle brackets (`<` or `>`).
  - **Triggering Optimization ("Pushy" Descriptions)**: Claude tends to under-trigger skills. The description must be "pushy" and explicitly state when to trigger (e.g., *"Make sure to use this skill whenever the user mentions dashboards... even if they don't explicitly ask for it"*). Include both what it does and specific context triggers.
- **Optional fields**: `license`, `allowed-tools`, `metadata`, `compatibility` (max 500 characters).

## 2. Directory Hierarchy
Skills should be organized into specific bundled resource directories:
```
skill-name/
├── SKILL.md          # Required: YAML frontmatter + Markdown instructions
├── scripts/          # Optional: Executable code for deterministic/repetitive tasks
├── references/       # Optional: Documentation loaded into context as needed
└── assets/           # Optional: Files used in output (templates, icons, fonts)
```
- *Note:* The root `evals/` directory is used during development for testing but is excluded when packaging the final `.skill` artifact.

## 3. Progressive Disclosure
Skills utilize a three-level loading system to optimize agent context windows:
1. **Metadata** (`name` + `description`): Always in context (~100 words).
2. **SKILL.md body**: Loaded into context whenever the skill triggers. Ideal length is `<500 lines`. If approaching this limit, introduce hierarchy and point the agent to reference files.
3. **Bundled resources**: Loaded only as needed (unlimited size). 
   - Scripts can be executed by the agent without loading their source code into context.
   - For large reference files (>300 lines), include a Table of Contents.
   - **Domain Organization**: If a skill covers multiple frameworks, organize them by variant (e.g., `references/aws.md`, `references/gcp.md`) so the agent only reads the relevant file.

## 4. Script Design Rules (Scripts vs. Model Guidance)
- **When to use scripts**: Use for deterministic, repetitive tasks, strict validation, formatting, or complex data extraction.
- **When to use model guidance**: Use for subjective outputs (writing style, art, tone), flexible workflows, or tasks requiring reasoning and theory of mind.
- **Script Guidelines**: 
  - Must be self-contained with minimal external dependencies.
  - Must use clean exit codes (e.g., `sys.exit(0)` for success, `sys.exit(1)` for failure) so the agent immediately understands success or failure.
  - Must print clear console output or error messages for the agent to read.

## 5. Best Practices Checklist
- [ ] **Capture Intent & Research**: Identify the workflow, trigger phrases, expected output, and verifiable success criteria. Proactively ask users about edge cases.
- [ ] **Write `SKILL.md`**: Use the imperative form for instructions. Define output formats rigidly (e.g., providing markdown templates) and include concrete examples (Input -> Output patterns).
- [ ] **Define Test Cases**: Save realistic user prompts in `evals/evals.json`. 
- [ ] **Run Evals**: Execute test cases using both a "with-skill" subagent and a baseline (no skill/old version) subagent.
- [ ] **Iterate & Benchmark**: Evaluate the results quantitatively and qualitatively (e.g., pass rates, execution time, token usage). Revise the skill based on feedback.
- [ ] **Package the Skill**: Use a packaging script (like Anthropic's `package_skill.py`) to zip the directory into a `.skill` file, stripping out build artifacts (`__pycache__`, `node_modules`, `evals`).
