---
name: roblox-device-qa
description: Runs evidence-based Roblox Studio playtests across devices, with verified Rojo syncing, real input flows, regression checks, and restoration of test settings. Use for mobile UI checks, emulator comparisons, Studio gameplay verification, or testing a Roblox fix; not for code-only reviews or isolated unit tests.
---

# Roblox device QA

Run the requested player flow in the intended Studio place using the intended source. Record expected and observed behavior with concrete evidence. Choose coverage from the change and current project guidance; the suggestions below are starting points.

## Establish the target

- Read the task, applicable project instructions, and current test documentation. Reuse maintained harnesses and test commands. Verify APIs against the current connected tools; historical notes are leads, not proof.
- Discover available Studio instances and select the one matching the requested place and task. Pass its exact ID to every Studio call. Read its state and available Edit, Client, and Server contexts. Never reuse a remembered instance ID.
- Prefer the designated test place. Existing explicit authorization for another place takes precedence. Do not select production merely because it is the only open place. Resolve ambiguity before syncing.
- Record the repository/worktree, branch or commit and dirty state, project file, Studio place, relevant build/configuration/profile, initial play state, simulator settings, and network conditions. Include only details that matter to the test.
- Treat a Studio instance as shared mutable state. Coordinate ownership of device switching, Rojo connection, and Play lifecycle. Do not interrupt an active user or another tester session.
- Testing authorizes reversible checks within scope. It does not authorize publishing, merging, asset uploads, real purchases, destructive profile resets, or live configuration changes.

## Sync and verify source

Inspect existing Rojo servers and the Studio source before connecting. Reuse a suitable server only after verifying its worktree, project file, port, source tree, and connection. Check dependencies and generated files before syncing; incomplete packages can overwrite working Studio content.

If starting a server, use the repository-pinned CLI from the intended worktree, select a free port, and record the process and port you own. Never stop unrelated servers. Inspect the installed plugin's current capabilities. Discover connected MCP tools and schemas; there is no universal Studio connection API.

For a new automatic connection without native UI access, follow [headless-rojo.md](references/headless-rojo.md). It requires local filesystem access and Studio MCP, uses a locally built pinned helper, and requires a user-saved permission for the exact localhost endpoint. Otherwise connect through the authorized Studio UI. Review the initial changes, including root renames and deletions, before accepting. Do not overlap mapped subtrees with another Rojo client.

Prove source reached Edit mode by comparing distinctive changed scripts with the intended local source, preferably exact content or hashes. Verify needed dependencies too. A listening server, plugin label, or file length alone does not prove synchronization. Start a fresh Play session after source or harness changes when needed; verify the running behavior actually uses the new source. Repeat affected checks after relevant branch, rebase, or merge changes.

To prove live sync on an existing connection, create a uniquely named inert temporary ModuleScript in an agreed idle mapped folder. Verify exact source, update its marker and verify the replacement, then delete only the owned file and confirm the Studio instance disappears. Confirm your fixture is gone and pre-existing dirty files remain untouched. This proves create/update/delete on that connection; it does not prove a new plugin connection can be created automatically.

## Choose devices and restore settings

When discoverable in the connected environment, load Roblox's built-in `rbx-device-simulator-lua` skill and verify its current API documentation against the live tool schemas. It documents `StudioDeviceSimulatorService:GetDeviceListAsync()` and `GetDeviceInfoAsync(id)` for dynamic device discovery. A skill describes a workflow; it does not grant tools or permissions.

- Read the game's supported orientation and relevant safe-area/inset settings. Do not force unsupported orientations unless requested as a stress test.
- Use the current dynamic device-list and device-info APIs to select devices by form factor, name, and dimensions. Do not hardcode internal device IDs or assume one fixed device represents the smallest screen.
- A useful starting set is desktop, a narrow phone, a representative notched phone, and a tablet. Deduplicate overlapping cases; add other platforms, controller, or VR only when relevant.
- Capture the current device, orientation, resolution, density, and scaling mode when available. Guard getters that can fail without an active simulated device. Avoid changing a setting whose initial value cannot be read.
- `SetDeviceAsync` clears resolution and DPI overrides. Capture these first and explicitly restore them after switching devices. A `default` device may not support active-device getters.
- After changing devices, wait for the asynchronous viewport update, then verify active device, orientation, and camera viewport. Poll readiness with a deadline when layout or assets are still loading.
- Apply orientation only to device types that support it. Read back settings after setter errors because a combined call may partially succeed. Restore captured values explicitly during cleanup.

Prefer device setup in Edit mode before Play. Never call simulator setters in a PlayServer context. Use PlayClient only when the current API supports it and the selected context is verified.

## Exercise observable behavior

Before testing, write a short scenario matrix: **starting state → player action → expected behavior → evidence**.

- Wait for concrete readiness such as a player/character, required GUI, loaded profile, or enabled action. Use bounded polls instead of long fixed sleeps. Capture current client/server errors and distinguish baseline warnings from new failures.
- For async lists and previews, use positive evidence that the intended content loaded. An absent loading label is weak evidence; an early placeholder proves opening, not completed rendering.
- Use actual mouse, keyboard, emulated touch, or controller input for interaction claims. Inspect live targets and derive coordinates from current GUI bounds or native UI snapshots. Recalibrate after device changes.
- If a click does nothing, measure the delivered `InputObject.Position` and target `InputBegan`/`Activated` with a temporary runtime-only observer. Tool coordinates may differ due to simulator insets or scaling. An observed target `Touch` event proves emulated touch delivery; `TouchEnabled` alone does not.
- Label direct module calls, remote firing, state injection, and fixture setup accurately. They can test logic or establish a starting state, but do not prove a player can reach and activate that action. Callback invocation is not an input pass.
- For changed controls, select relevant press/release, cancel, hold, repeat, drag/scroll, rebinding, and modal/focus cases. Observe resulting game state as well as animation. If gamepad input arrives as keyboard input, report controller behavior as unverified.
- Inspect Play-mode screens for clipping, overlap, text truncation, safe-area clearance, readable labels, target size, scrolling, and hidden actions. Check keyboard occlusion for relevant text entry. Verify visibility through ancestors and clipping; `Visible = true` alone is insufficient.
- Use screenshots when they establish an outcome. Preserve actual capture IDs or artifact paths and state what the capture tool includes. Never invent a saved path or claim evidence outside the captured view.

Check that the current executor has the tools needed for each evidence type. If screenshot access is unavailable to a delegated tester, the parent must take and review captures. Require enabled intended UI and visible content changes after input; hidden descendants do not establish a player-visible pass. If the call budget runs out, mark remaining cases **NOT RUN**.

Current `execute_luau` schemas may expose Edit, Client, and Server. Check live schema/state and use a small read-only probe rather than assuming old context restrictions. An MCP-required module may be an isolated copy; use authoritative instances, server state, or a runtime harness when identity matters.

## Add relevant regression checks

| Change or risk | Useful additional checks |
| --- | --- |
| Onboarding or progression | Fresh and returning test profiles, active flags/cohorts, repeat behavior after guidance ends; use isolated or mock profiles, not destructive resets. |
| UI startup or lifecycle | Open/close/reopen, respawn, late-created UI, stacking/focus, and cleanup after transitions. Browser wireframes do not establish native Roblox behavior. |
| Ownership, streaming, or networking | Two Studio clients when contention matters; disconnect/rejoin, stream out/in, and stale cleanup. Synthetic fixtures leave multiplayer behavior unverified. |
| Slow network | Use the current network-simulator instructions, save settings, read back the selected preset, and measure action-to-result and server catch-up. A blocked network case remains blocked even if normal network passes. |
| Analytics | Separate event generation/payload checks from delivery and reporting. Do not infer conversion rates from counts or treat skipped steps as completed funnel events. |
| Pricing, rewards, or configuration | Check runtime configuration, entitlements, owned/off-sale/free states, and displayed versus prompted totals. Use deterministic parity checks or justified samples for randomized rewards. |

Keep project-specific lessons scoped to the project that established them. Model/spec-only changes may have no meaningful in-game test.

## Clean up and report

Cleanup is required after success and failure:

1. Release held input, stop only Play sessions you started, remove only your temporary fixtures/scripts/connections, and restore temporary flags. Do not reset unrelated user changes.
2. Restore the captured simulator device, overrides, orientation, and scaling mode; verify read-back. Restore network settings to their captured values.
3. Restore a changed sync endpoint when safe. Stop only a Rojo process you started. Preserve pre-existing servers and user-saved permissions. Report incomplete restoration.
4. Check that your fixtures and flags are gone and pre-existing dirty checkout files remain untouched. Report final Studio and sync state. Saving a place, publishing, deployment, and server restart are separate actions.

Report concise, reproducible evidence:

| Scenario | Device/input/network | Expected | Observed/evidence | Status |
| --- | --- | --- | --- | --- |

Use **PASS**, **FAIL**, **BLOCKED/INCONCLUSIVE**, or **NOT RUN**. Record tested commit/dirty state, place, relevant config/profile, and exact failures. Separate static checks, mocks/Lune, Studio logic probes, player interaction, emulated devices, physical hardware, and production observations. Lead with what works and the most consequential failure. For each failure, provide a short reproduction and evidence pointer. Name the concrete missing capability for blocked checks. Stop when relevant checks pass; expand coverage only for new changes, failures, or unresolved concerns.
