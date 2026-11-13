# Roblox Device QA

A Codex or Claude skill for evidence-based Roblox Studio playtests. It helps verify that the intended source reached Studio, exercise real player input across relevant device sizes, check regressions, restore test settings, and report observed evidence separately from assumptions.

## Install

Clone this repository and place the `roblox-device-qa` directory in your chosen skills folder. Keep any existing skill directory; inspect it and merge intentionally rather than overwriting it.

For Codex:

```sh
mkdir -p ~/.codex/skills
git clone https://github.com/lucoile/roblox-device-qa.git ~/.codex/skills/roblox-device-qa
```

For Claude Code, use this destination instead:

```sh
mkdir -p ~/.claude/skills
git clone https://github.com/lucoile/roblox-device-qa.git ~/.claude/skills/roblox-device-qa
```

If the destination already exists, inspect it and merge intentionally before installing; do not overwrite existing work. Git refuses to clone into a nonempty destination.

Restart or refresh the client if it does not discover the skill immediately.

## Requirements

- Roblox Studio and an authorized test place.
- Studio MCP for connected Studio inspection and execution. This skill does not include or grant Studio MCP access.
- A project-pinned Rojo installation for ordinary sync workflows.
- For the optional automatic headless connection: local filesystem access, Studio MCP with `execute_luau`, Python 3, Lune 0.10.3, Rojo 7.7.0, and user-saved permission for the exact localhost endpoint used by the Rojo server.

The headless helper is optional. Read [references/headless-rojo.md](references/headless-rojo.md) before using it. Its setup builds a local ignored bundle from official pinned Rojo 7.7.0 inputs and does not connect to Studio.

## Use

Ask for a specific test, for example:

> Verify the inventory close-button fix in the test place. Check desktop and a narrow phone, use actual input, capture the expected behavior, and restore simulator settings.

The skill guides the agent to establish the exact test target, verify source synchronization, exercise player-visible behavior, and report **PASS**, **FAIL**, **BLOCKED/INCONCLUSIVE**, or **NOT RUN** with evidence.

## Limits

The MCP workflow does not require full desktop control. The user's environment must provide the initial Studio MCP connection and any needed localhost permission; the skill cannot grant permission autonomously. The skill does not publish places, merge changes, upload assets, make purchases, reset profiles, or change live configuration. Simulator checks are not physical-device performance tests, and test-place results are not production observations.

## Licensing

The skill and its helper scripts are MIT licensed; see [LICENSE](LICENSE). Setup downloads the official Rojo plugin model locally. Rojo retains its MPL-2.0 license, and its dependencies retain their own terms; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Generated Rojo binaries are not committed to this repository.

## Development checks

From the repository root, after preparing the optional local bundle, run:

```sh
python3 -m unittest discover -s tests
python3 scripts/prepare_bootstrap.py bootstrap --bundle assets/RojoHeadless-7.7.0.rbxm --controller scripts/Controller.luau
lune run tests/validate.luau
```

These validate repository tooling; they do not establish Roblox Studio or physical-device behavior.
