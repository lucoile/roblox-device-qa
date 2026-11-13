# Optional headless Rojo connection

Use this route only when the user requests a new automatic connection without native Studio UI access. It runs a locally built, pinned Rojo sync helper through Studio MCP. It is an optional version-pinned integration, not a public Rojo API. It requires local filesystem tools and Studio MCP; a Roblox Studio Assistant must not assume it can read local files.

The helper uses the official Rojo 7.7.0 sync modules inside an in-memory, non-archivable CoreGui container. It does not replace the installed plugin or expose an arbitrary HTTP command service. The supported network target is only `http://127.0.0.1:<port>`. The user must save permission for that exact endpoint in Studio MCP's Network permission allowlist. A denial is not permission to change host aliases, contexts, or protocols. Ask for a narrow permission only when needed.

Only one client should own a mapped subtree. Do not run this helper and the native plugin over overlapping paths. For an isolated test, map only a uniquely owned folder and use `$ignoreUnknownInstances: true` on its ancestors. Before full-project sync, verify dependencies, intended source, and ownership of all existing connections.

## Build and prepare

Run setup from the skill repository root. Install the pinned tools using Rokit, if using Rokit, with `rokit install`; the repository pins Rojo 7.7.0 and Lune 0.10.3 in `rokit.toml`. Lune installation instructions are at [Lune's official installation guide](https://lune-org.github.io/docs/getting-started/1-installation/). Setup downloads the official pinned Rojo release and uses Lune to transform it into the ignored local bundle. Setup builds files locally and does not contact or modify Studio.

```sh
rokit install
python3 scripts/setup_rojo.py
python3 scripts/prepare_bootstrap.py bootstrap \
  --bundle assets/RojoHeadless-7.7.0.rbxm \
  --controller scripts/Controller.luau
```

The `bootstrap` directory is generated local output. Choose another private temporary directory if that path already contains files you need to keep.

Run the Rojo server from the intended project worktree using exactly version 7.7.0. Verify the version in the server's actual working directory; version managers can select a different executable elsewhere. Use a free port and bind to localhost. Record the process and port you own.

The bootstrap generator verifies the bundle checksum and creates seven ordered Luau files plus a manifest. Read each complete file and send it to the connected `execute_luau` tool in Edit mode for the chosen Studio instance, in manifest order. Read large payloads in bounded chunks and pass them directly; do not dump encoded bundle data into chat.

The bootstrap refuses to overwrite an existing bridge. Inspect ownership and status before proceeding. Do not destroy another session. Initial status must be Disconnected.

## Preview and approve

Before preparing, record the independently selected expected place ID from the chosen Studio state, and the project name from the served Rojo project. Never set the expected place by reading `game.PlaceId` in the same call; that makes the check tautological.

```lua
local bridge = game.CoreGui.__CodexRojoBridge
bridge.Prepare:Invoke({
    port = PORT,
    expectedPlaceId = VERIFIED_PLACE_ID,
    expectedProjectName = "VERIFIED_PROJECT_NAME",
    confirmationTimeoutSeconds = 120,
})
return bridge.Status:Invoke()
```

Replace the uppercase values with the verified port, place ID, and project name. Poll with a bounded deadline until status is Review or Disconnected. Project identity can be cached until the server restarts after a project-file rename.

Review includes the server session ID, endpoint, expected place/universe, and added, removed, and updated entries. Property summaries are bounded; Source is redacted to byte counts and SHA-256. A truncated summary is not enough to approve an unknown change. Inspect the owning local source and compare every proposed change to the authorized scope, including root DataModel renames.

Accept only the exact observed review token after inspection. Do not retrieve and accept a fresh token blindly in one call. Abort with the same observed token if changes exceed scope. The review expires after its configured deadline (default 120 seconds, maximum 300 seconds).

```lua
return game.CoreGui.__CodexRojoBridge.Accept:Invoke("OBSERVED_REVIEW_TOKEN")
```

The controller rejects invalid ports, wrong place IDs, mismatched project names, duplicate sessions, stale tokens, and acceptance after entering Play or changing place/universe. Two-way sync is disabled.

## Prove the connection and clean up

Require `status = Connected`, `socketStatus = Open`, and no patch failures. Connected alone proves only initial application; the WebSocket may still be opening.

Prove fresh-connection behavior with an inert temporary ModuleScript in an agreed mapped folder. Verify exact initial source, edit a marker and verify exact replacement, create another module after the socket opens and verify it, then remove both owned files and confirm both Studio instances disappear. Use bounded polls and record the new session ID. A listening port, successful GET, module constructor, or marker on an old connection is not a pass.

Invoke Disconnect and verify Disconnected/Closed. Delete only owned test objects after confirming their source-file deletion. Destroy only the bridge you created, and stop only the recorded test server. Preserve unrelated servers and user settings; do not revoke the saved permission automatically. Confirm your temporary fixtures are gone and pre-existing dirty files remain untouched. Verify Studio is in its original play/device state. Report any incomplete cleanup.
