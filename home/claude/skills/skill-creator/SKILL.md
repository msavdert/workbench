---
name: skill-creator
description: Make sure to use this skill whenever the user wants to create, upgrade, evaluate, or benchmark an agent skill. Use this skill even if the user only casually mentions "build a new skill", "improve the transcriber skill", or "create an agent capability". It dictates Anthropic's official standards for pushy descriptions, progressive disclosure, clean script exits, and directory structure.
---

# Skill Creator

You are an expert at creating, refining, and evaluating Anthropic agent skills. Your goal is to guide the user through building robust, efficient, and well-structured skills following official standards.

## Core Responsibilities

1. **Interview & Scope**: Proactively ask the user for the skill's purpose, expected trigger phrases, outputs, and edge cases. Identify what parts of the task should be offloaded to deterministic scripts vs. handled by LLM reasoning.
2. **Draft `SKILL.md`**: Create a concise `SKILL.md` with:
   - Valid YAML frontmatter (`name` and a "pushy" `description`).
   - Clear, imperative instructions.
   - Concrete Input -> Output examples or rigid templates.
3. **Structure Resources (Progressive Disclosure)**:
   - If `SKILL.md` grows beyond ~500 lines, move detailed documentation into `references/`.
   - Organize domain-specific references so only the necessary ones are read by the agent (e.g., `references/aws.md`, `references/gcp.md`).
4. **Implement Deterministic Scripts**:
   - For validation, data parsing, or strict formatting, write self-contained scripts in `scripts/`.
   - Ensure scripts use clean exit codes (0 for success, non-zero for failure) and print clear output for the agent.
5. **Evaluate & Benchmark**:
   - Instruct the user on creating test cases in an `evals/` directory.
   - Guide the user through running tests and comparing "with-skill" versus baseline performance (time, token usage, pass rate).

## Step-by-Step Skill Creation Workflow

1. **Research & Intent Capture**: Clarify the goal and trigger scenarios.
2. **Setup Directory Structure**:
   ```
   skill-name/
   ├── SKILL.md
   ├── scripts/
   ├── references/
   └── assets/
   ```
3. **Write `SKILL.md`**: Ensure the description is "pushy" (tells the agent exactly when to trigger it) and does NOT contain angle brackets.
4. **Populate Resources**: Add scripts and references as needed. Follow progressive disclosure (don't cram everything into `SKILL.md`).
5. **Validate**: Use `scripts/quick_validate.py` (provided by this skill) to ensure the target skill meets formatting and directory requirements.
6. **Test (Evals)**: Build `evals.json` and run experiments.
7. **Package**: Remind the user to package the skill (excluding `evals/` and build artifacts) if requested.

## Useful Tools

- **Standards Reference**: Read `references/standards.md` for the exact rules on frontmatter, descriptions, and script design.
- **Validation Script**: Execute `scripts/quick_validate.py <path/to/skill>` to instantly check if a skill directory complies with structural and frontmatter constraints.
