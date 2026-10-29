# The Final Outlaw: working agreement

This folder is the canonical Git working copy. Work only on this game and the requested update; do not launch another game or treat archived publication copies as parallel development locations. The current Round Five request covers combat button placement, runner speed, safe house-edge routes and the endless opening ramp; read docs/ROUND_FIVE.md. Preserve the existing Play Games integration, owner IDs, local saves, unrelated export/signing settings and user edits. Do not expand into another game or cloud-save implementation without a new request.

Before editing, read README.md, HANDOFF.txt and docs/PLATFORM_SETUP.md, then inspect git status, branch/upstream and origin. A fresh task must load these files; prior chat history is not assumed. Preserve user edits and local artifacts. Do not reset/clean an existing worktree or delete backups.

## Project map

- `game/main.gd` connects UI, save and lifecycle/service behavior; `game/combat.gd and game/state.gd` owns game rules/state.
- `game/catalog.json`: 21 achievement/5 leaderboard definitions; `platform/config.json` maps console IDs.
- `export_presets.cfg`: matching numeric `godot_play_game_services/game_id`; `project.godot`: runtime/export settings.
- `platform/services.gd`: optional native services.
- `docs/NATIVE_QA.json`, `docs/LOCAL_TEST_RESULTS.json` and marketing screenshot metadata are dated sanitized summaries.

## Build and verify

Godot4.5.1 Compatibility, Android primary plus Web, Java17 and matching export templates/SDK. The accepted Round Four AAB uses min API24/target API36; old API35 native records remain historical, not a fixed engine constraint; verify current store requirements before release. Keep current Android shader-cache and remote-run settings unless separately justified.

Import once with `godot --headless --editor --path . --import`. Run the affected tests below, plus `platform/tests/services_smoke.gd` when services change. Use a process-scoped temporary user-data root (APPDATA and LOCALAPPDATA on Windows; XDG_DATA_HOME on Linux) so tests and service pending queues never touch genuine saves. Keep existing timeouts and strict script/parse/assertion/engine-error checks.

```sh
godot --headless --path . --script tests/test_fullscreen_lifecycle.gd
godot --headless --path . --script tests/test_models.gd
godot --headless --path . --script tests/test_round_three.gd
godot --headless --path . --script tests/test_ui.gd
godot --headless --path . --script tests/test_touch_input.gd
```

For the Play Games regression fixture, isolate user data first, then set the process-only guard `OUTLAW_PGS_TEST_ISOLATED=1` and `OUTLAW_PGS_TEST_ROOT` to that isolation parent before running `godot --headless --path . --script tests/test_play_games.gd`. The guard alone does not isolate data. The fixture verifies the actual user-data path, refuses Android and exercises synthetic adapters; it does not sign in to Google or prove backend acceptance. Use the isolated examples in `docs/PLATFORM_SETUP.md`, require its `OUTLAW_PLAY_GAMES_TESTS` completion line with zero failures, a successful exit and the existing strict log gate. Run the service smoke test and affected game tests as well.

For documentation-only changes, review text/links and the staged diff; do not rebuild or overwrite the preserved original QA APK. Runtime/service changes require relevant tests and an explicit native retest plan; desktop callbacks and CI exports do not establish native SDK behavior.

## Service IDs and publication

Read the exact mapping contract in docs/PLATFORM_SETUP.md. Owner-supplied PGS IDs are now enabled, with the numeric game ID matching the Android export. `play_games.enabled` gates all Play Games access, not Saved Games; game saves remain local and no Snapshot flow is implemented. Preserve Standard achievements and Numeric/zero-decimal/Larger-is-better leaderboards, including whole-second `survival_seconds`. The durable desired-progress journal must retain legitimate earned flags and best scores; acknowledgements are session-only, and ambiguous or failed callbacks must not discard newer progress. The AdMob manifest App ID is the ProjectSettings key `admob/general/android/app_id` in `project.godot`; JSON `admob.app_id` is only a reference. `test_mode` changes wording and does not convert production unit IDs into test requests. Keep sample IDs or configure native test devices explicitly.

Stage only reviewed project changes. Keep build outputs, raw SDK/log evidence, real saves, private handoffs/checkpoints, signing material and credentials out of public commits. Gitignore cannot protect private content copied over an already tracked QA document; keep public summaries sanitized and use relative artifact filenames. Preserve LICENSE/NOTICE/LICENSES and dependency terms. No force push, Pages activation, Library action, production signing or Google Play publication is implied by a normal iteration. After an approval denial, stop that action and report its exact target/payload/outcome; do not bypass or repeat it without materially new relevant authority.

When done, report changed behavior, actual tests, remaining limitations and artifact identity; update HANDOFF.txt without claiming old native QA applies to new binaries.
