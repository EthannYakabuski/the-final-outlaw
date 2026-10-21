# The Final Outlaw: working agreement

This folder is the canonical Git working copy. Work only on this game and the requested update; do not launch another game or treat archived publication copies as parallel development locations. The ten-game review cap is already reached.

Before editing, read README.md, HANDOFF.txt and docs/PLATFORM_SETUP.md, then inspect git status, branch/upstream and origin. A fresh task must load these files; prior chat history is not assumed. Preserve user edits and local artifacts. Do not reset/clean an existing worktree or delete backups.

## Project map

- `game/main.gd` connects UI, save and lifecycle/service behavior; `game/combat.gd and game/state.gd` owns game rules/state.
- `game/catalog.json`: 21 achievement/5 leaderboard definitions; `platform/config.json` maps console IDs.
- `export_presets.cfg`: matching numeric `godot_play_game_services/game_id`; `project.godot`: runtime/export settings.
- `platform/services.gd`: optional native services.
- `docs/NATIVE_QA.json`, `docs/LOCAL_TEST_RESULTS.json` and marketing screenshot metadata are dated sanitized summaries.

## Build and verify

Godot4.5.1 Compatibility, Android primary plus Web, Java17 and matching export templates/SDK. Retain min API24/target API35 as the current engine test constraint; verify current store requirements before release. Keep current Android shader-cache and remote-run settings unless separately justified.

Import once with `godot --headless --editor --path . --import`. Run the affected tests below, plus `platform/tests/services_smoke.gd` when services change. Use a process-scoped temporary user-data root (APPDATA and LOCALAPPDATA on Windows; XDG_DATA_HOME on Linux) so tests and service pending queues never touch genuine saves. Keep existing timeouts and strict script/parse/assertion/engine-error checks.

```sh
godot --headless --path . --script tests/test_fullscreen_lifecycle.gd
godot --headless --path . --script tests/test_models.gd
godot --headless --path . --script tests/test_ui.gd
```

For documentation-only changes, review text/links and the staged diff; do not rebuild or overwrite the preserved original QA APK. Runtime/service changes require relevant tests and an explicit native retest plan; desktop callbacks and CI exports do not establish native SDK behavior.

## Service IDs and publication

Read the exact mapping contract in docs/PLATFORM_SETUP.md. PGS IDs start blank/disabled. The AdMob manifest App ID is the ProjectSettings key `admob/general/android/app_id` in `project.godot`; JSON `admob.app_id` is only a reference. `test_mode` changes wording and does not convert production unit IDs into test requests. Keep sample IDs or configure native test devices explicitly.

Stage only reviewed project changes. Keep build outputs, raw SDK/log evidence, real saves, private handoffs/checkpoints, signing material and credentials out of public commits. Gitignore cannot protect private content copied over an already tracked QA document; keep public summaries sanitized and use relative artifact filenames. Preserve LICENSE/NOTICE/LICENSES and dependency terms. No force push, Pages activation, Library action, production signing or Google Play publication is implied by a normal iteration. After an approval denial, stop that action and report its exact target/payload/outcome; do not bypass or repeat it without materially new relevant authority.

When done, report changed behavior, actual tests, remaining limitations and artifact identity; update HANDOFF.txt without claiming old native QA applies to new binaries.
