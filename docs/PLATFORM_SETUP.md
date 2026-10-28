# Android integrations and build handoff

## 2026-10-28 Play Games integration

The source configuration now contains the owner's 21 achievement IDs and five leaderboard IDs, `play_games.enabled=true`, and a game ID matching `godot_play_game_services/game_id` in the Android export preset. Preserve these values and symbolic keys. The JSON flag enables the app's Play Games authentication, achievement and leaderboard adapter. It is not a Saved Games switch. The device save remains `user://outlaw_save_v1.json`; enabling Saved Games in the backend does not add Snapshot upload, download, conflict resolution or cross-device save synchronization.

### Console value contract

- All 21 achievements are **Standard**. Their local `threshold` fields are conditions for one-time unlocks, not Google incremental step totals. Names/descriptions are in `game/catalog.json`; IDs belong in `platform/config.json` under `play_games.achievements`.
- All five leaderboards are **Numeric**, **0 decimal places**, **Larger is better**. Map IDs under `play_games.leaderboards`.

| Key | Submitted value |
| --- | --- |
| `eliminations` | Cumulative kills across all modes, in foes |
| `survival_score` | Best single endless-run score, in points |
| `campaign_stars` | Sum of the best stars earned on each campaign trail |
| `player_level` | Current in-game player level |
| `survival_seconds` | Longest endless run, in whole seconds |

No decimal or currency scaling is applied. Do not choose Time formatting for `survival_seconds` with this code: Google expects milliseconds for Time, while this game sends seconds. Changing that representation requires a coordinated code and console change.

### Synchronization and offline behavior

`game/main.gd` backfills legitimate saved unlock flags on load and progress changes, including `streak_7` after the current streak has reset. Qualifying existing metrics can mark an achievement earned without adding coins, XP or other rewards. Existing local best-score metrics supply the five boards.

`platform/services.gd` retains desired unlocks and maximum scores in `user://platform_pending_v1.json`. Startup validates and merges the primary, `.bak` and `.tmp` records; writes flush a temporary file and replace the primary, retaining the last readable backup. The adapter connects native authentication, achievement and score result signals. Acknowledgements are session-only, requests are coalesced, and each remote ID has at most one active request. Failed, timed-out or ambiguous callbacks retain desired progress; an old score callback cannot acknowledge a newer score. Reconnect and unchanged failed/ambiguous retries use a 30-second backoff. Authentication is rechecked on Android resume; interactive sign-in follows an explicit Connect/Online action, and a queued online view opens after authentication succeeds. Failure or cancellation leaves local play available. A successful SDK callback is not proof supplied by a synthetic fixture.

### Source checks and remaining owner validation

The focused fixture is `tests/test_play_games.gd`. It requires fresh process-scoped user-data directories, `OUTLAW_PGS_TEST_ISOLATED=1`, and `OUTLAW_PGS_TEST_ROOT` matching the parent of those directories. It verifies the actual Godot user-data path is inside that root and refuses Android execution. It uses synthetic clients rather than a real Google account. Run the service smoke test and affected game tests under the same isolation. Require exit zero, the `OUTLAW_PLAY_GAMES_TESTS` summary with zero failures, and no strict script/parse/assertion/engine-error diagnostics. Record the actual source revision and local/hosted results in `HANDOFF.txt`; these tests cannot establish real signed-in Google acceptance.

PowerShell, from the project root with the configured `godot` executable:

```powershell
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('outlaw-pgs-' + [Guid]::NewGuid().ToString('N'))
$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA
$previousGuard = $env:OUTLAW_PGS_TEST_ISOLATED
$previousTestRoot = $env:OUTLAW_PGS_TEST_ROOT
try {
    $env:APPDATA = Join-Path $testRoot 'Roaming'
    $env:LOCALAPPDATA = Join-Path $testRoot 'Local'
    New-Item -ItemType Directory -Path $env:APPDATA, $env:LOCALAPPDATA -Force | Out-Null
    $env:OUTLAW_PGS_TEST_ISOLATED = '1'
    $env:OUTLAW_PGS_TEST_ROOT = $testRoot
    godot --headless --path . --script tests/test_play_games.gd
    if ($LASTEXITCODE -ne 0) { throw 'Play Games fixture failed; inspect the full log.' }
} finally {
    $env:APPDATA = $previousAppData
    $env:LOCALAPPDATA = $previousLocalAppData
    $env:OUTLAW_PGS_TEST_ISOLATED = $previousGuard
    $env:OUTLAW_PGS_TEST_ROOT = $previousTestRoot
}
```

On Linux, use a fresh `XDG_DATA_HOME` for each fixture process, for example `pgs_test_root="$(mktemp -d)"` followed by `XDG_DATA_HOME="$pgs_test_root/data" XDG_CONFIG_HOME="$pgs_test_root/config" OUTLAW_PGS_TEST_ISOLATED=1 OUTLAW_PGS_TEST_ROOT="$pgs_test_root" godot --headless --path . --script tests/test_play_games.gd`. Do not run synthetic fixtures against genuine saves or treat the opt-in guard as isolation by itself.

The owner still needs to validate a newly built Android app with matching `com.ethannyakabuski.finaloutlaw`, game ID, OAuth client and actual signing-certificate fingerprints, authorized testers and configured/published-for-testing Play Games resources. On the intended signed-in device, verify existing earned achievements, a newly earned Standard achievement, the five correctly formatted board values (including whole seconds), sign-in cancellation/failure, offline progress followed by online retry, background/resume and relaunch. Confirm the device save and earned rewards remain unchanged by synchronization. Verify the existing AdMob behavior separately; this integration does not change its app/unit IDs, consent or reward rules. CI and old artifacts cannot establish real-service acceptance. Release signing and Play publication remain owner actions.

## Current Round Four build

The Android preset defaults to Gradle AAB with matched ARM64/x86/x86_64 native coverage. The accepted local export used minimum API 24/target API 36; SHA256 `3BA42538514249C8EFC905C98DFB056ED665EDEB9C40232F0D9189AD04CBFF7D` from build source `c9c600099db3f381202f0e5c240d7cc22bd4940c`. Public source revision `9bb2d806a2389b39162dafe9ad6c26df475ea7f9` has [passing exact-commit hosted CI](https://github.com/EthannYakabuski/the-final-outlaw/actions/runs/40125506666); release signing and native/device acceptance remain pending. The accepted local bundle retains its original build-source/hash provenance. Older native/API35 observations below are dated evidence only; they do not impose a fixed engine constraint on this new export. Read [the build correction](ROUND_FOUR_ANDROID.md) and [the artifact handoff](../HANDOFF.txt) before distribution.

This project targets Godot **4.5.1 Compatibility**, Android (API36 target, min24), and a single-threaded Web export. Windows desktop builds are outside its scope. Production Play publication remains a separate human step: verify the then-current target API policy before release; a successful API35 test build is not a claim of current store-submission eligibility.

## Runtime services

`Services` is the game-facing adapter. Its Android implementation calls the supplied Poing AdMob **5.1.0** and Godot Play Games Services **3.4.0** packages. The Web/editor implementation never simulates a successful rewarded ad. Gameplay, saves, achievements and best scores continue locally.

- Menu banner: native 320x50dp banner anchored at the screen bottom. Menu UI consumes `Services.menu_bottom_reserve(reference)` and listens to `menu_bottom_reserve_changed`; gameplay calls `set_menu_visible(false)`.
- Interstitials: every second naturally completed round, when an ad is loaded; no added fixed-time throttle. Failed/unavailable ads do not prevent play.
- Rewarded: opt-in, available only after a real native rewarded ad loads; benefits granted only on the earned-reward callback, once per request. Dismissal/failure grants nothing.
- Consent: refresh UMP consent at Android launch, show a required form, and initialize advertising only after `OBTAINED` or `NOT_REQUIRED`. A privacy-options action is exposed. Without configured/available consent information, requests pause and gameplay continues. Google's sample AdMob app does not prove the publisher's eventual privacy-message configuration; this requires human final configuration/testing.
- Play Games: owner-supplied achievement/leaderboard IDs are enabled in the current source configuration. Desired unlocks and best scores are retained in `user://platform_pending_v1.json` and resubmitted idempotently after sign-in. Only the configured symbolic keys map to remote IDs; native backend acceptance remains to be verified.

### Menu geometry

`menu_bottom_reserve(reference: CanvasItem = null) -> float` returns the Android menu's required bottom margin in the reference node's local units. It uses the greater of the measured banner pixel height or a conservative 50dp unloaded fallback, adds safe-bottom pixels and12dp padding, then converts through `reference.get_viewport().get_screen_transform() * reference.get_global_transform_with_canvas()`. This retains window stretch when subwindows are embedded; `CanvasItem.get_screen_transform()` alone can omit that stretch. Non-immersive Android keeps a conservative48dp navigation allowance because safe-area coordinates can already omit system bars. The result is0 outside Android or while the menu banner is hidden.

Connect the no-argument `menu_bottom_reserve_changed` signal once, then update existing geometry after setting banner visibility. Measurements refresh on banner creation/load, viewport resize, resume, and half-second menu polling. Anchored containers use the result as a bottom margin. Fixed-position menus must fit/reposition their children within the usable rectangle; merely reducing a root's size does not move its fixed children. Query a stable owner/root when fitting a child stage, rather than feeding the newly scaled child's units back into its own scale. Keep gameplay geometry unchanged when the banner is hidden. Position menu toasts and modal controls above the same reserved region.

`menu_layout_metrics(reference)` exposes raw measurements for QA, and Android logs changed measurements as `NATIVE_MENU_METRICS`. Unit calculations with the supplied phone geometry (131px banner,126px navigation allowance,420dpi,1.8screen pixels per local unit) require161logical units; this is calculation evidence, not proof that a rebuilt Android layout has passed device testing. Actual menu/banner separation still requires screenshots and touch checks on the rebuilt APK.

Coordinate references: https://docs.godotengine.org/en/4.5/classes/class_canvasitem.html#class-canvasitem-method-get-screen-transform and https://docs.godotengine.org/en/4.5/classes/class_displayserver.html#class-displayserver-method-get-display-safe-area . Godot4.5.1's Android safe-area handling is in https://github.com/godotengine/godot/blob/4.5.1-stable/platform/android/java/lib/src/org/godotengine/godot/GodotIO.java .

## Human configuration

Android debug builds log `NATIVE_AD_EVENT` only from actual SDK presentation, dismissal, failure, and accepted earned-reward callbacks. `rewarded_earned` is logged after the game's successful callback and only once, with its event context. Request attempts are not presentation proof. Editor/Web unit callback exercises never emit these native diagnostics; no analytics or network calls were added.

1. Keep test IDs in use during development. Google's Android sample app ID and banner/interstitial/rewarded units are recorded in `platform/config.json`. The native SDK's manifest app ID comes from the project setting `admob/general/android/app_id`, with the plugin's same Google sample ID as its default. An absent `[admob]` section in `project.godot` is normal when this default is unchanged; the editor can omit default-valued settings. For production, set the real app ID in Godot Project Settings (serialized under `[admob]` as `general/android/app_id`) and update the JSON reference value too. JSON `admob.app_id` alone does not change the Android manifest. Source: `addons/admob/internal/exporters/android/export_plugin.gd:112-125` and `internal/services/project_settings_service.gd:27,62-63,124-130`.
2. The owner has filled `platform/config.json`'s `play_games.game_id`, enabled Play Games and supplied all catalog achievement/leaderboard mappings. Keep the same numeric game ID in `export_presets.cfg` (`godot_play_game_services/game_id`); this export option supplies Android manifest metadata, while JSON supplies the runtime adapter's configuration. Preserve the owner's IDs and unrelated export/signing edits.
3. Configure package name, OAuth clients/signing fingerprints, authorized testers, Play Games resources, AdMob app/privacy messages, audience and production ad IDs in the owner's consoles. Supply signing material outside source control. Confirm applicable consent/audience settings before production.
4. Test real sign-in cancellation/failure, score/achievement submission, consent/privacy options, all test-ad formats, save persistence, offline behavior, and suspend/resume on the intended devices. Human production-ID/backend testing is distinct from passing local/CI tests.
5. Google Play publication remains the owner's responsibility. No workflow submits to Google Play or uses production signing keys.

## Build

Install/reuse Godot4.5.1, its matching export templates, Java17 and Android SDK and compatible template build tools (current target API36), NDK28.1.13356709. Use installed compatible tools or provision them explicitly; the hosted workflow provisions its own isolated runner dependencies. Do not assume a fresh machine has them.

```sh
godot --headless --editor --path . --import
godot --headless --path . --script platform/tests/services_smoke.gd
godot --headless --path . --install-android-build-template --export-debug Android build/android/game-debug.aab
python tools/verify_android_bundle.py build/android/game-debug.aab --preset export_presets.cfg
godot --headless --path . --export-release Web build/web/index.html
```

Create output directories first. The debug AAB is test-signed software, not a production-signed release and not directly installable like an APK. The current preset includes ARM64, x86 and x86_64 with actual matching native-library coverage checked after export. Release signing remains owner-supplied outside Git. `android/build` is generated from matching Godot templates and must not be committed with machine-local SDK paths/caches/keys.

The Android preset intentionally uses `runnable=false`. CLI exports still work; this prevents Godot's editor shutdown path from stopping the shared ADB server during a Web export. No global editor setting is changed. The API30 emulator also needs `rendering/shader_compiler/shader_cache/enabled.android=false` for its observed GL program-binary failure; retain the existing project setting unless a separately tested change justifies replacing it.

Enable `rendering/textures/vram_compression/import_etc2_astc=true` in project settings before importing assets for Android. Keep desktop texture import enabled for Web. Tests, test-only platform scripts, captures, marketing packages, helper scripts, logs and documentation are excluded from shipping resource packs. Copy the app icon to `platform/app-icon-512.png` and point the project icon setting there so excluding `marketing/` does not remove its runtime resource. Game catalogs and runtime art/audio remain included.

Hosted Actions verifies pinned Godot download digests, builds and validates the native Android AAB, validates Web/editor service fallback behavior, discovers and runs `tests/test_*.gd`, `tests/*_test.gd`, and `tests/smoke.gd` (requiring at least one), exports Web, retains Android artifacts seven days, and leaves Pages deployment explicitly disabled. Test processes have bounded timeouts; logs containing script/parse/assertion errors fail even if Godot exits0. CI does not substitute for human playtesting or verify unpublished Google service IDs. Do not enable Pages or change deployment settings as part of an ordinary code or ID update.

## Vendored dependencies and notices

- `addons/GodotPlayGameServices`: user's supplied3.4.0 copy, including required MIT license and native debug/release AARs.
- Its copied exporter checks Android build templates only for Android exports, avoiding irrelevant warnings during Web export.
- `addons/admob`: user's supplied5.1.0 source, MIT license retained. Native Android `ads`/core AARs came from the official `android-template-v4.5.1.zip` release asset: https://github.com/poingstudios/godot-admob-plugin/releases/download/v5.1.0/android-template-v4.5.1.zip . SHA256 `f7fdf644d50c0e231d8f02ae044057e489d0bcafcf50e908a4858477e7ee05ee` verified against GitHub's release digest.
- No mediation networks or iOS binaries are bundled. A documented one-line change removes the copied AdMob editor's automatic binary installer call because Android binaries are already vendored and iOS is outside this project. Runtime APIs and native exports remain intact. Original source asset folders are untouched.
- Original project code uses Apache2.0; third-party components retain their own licenses. Preserve notices in the repository and distributed game's credits/licenses screen.

Public upstream references: https://github.com/poingstudios/godot-admob-plugin and https://github.com/godot-sdk-integrations/godot-play-game-services .

## Project-specific continuation

Android package: `com.ethannyakabuski.finaloutlaw`. `game/catalog.json` contains 21 achievement and 5 leaderboard definitions. Preserve their symbolic identifiers when entering console IDs in `platform/config.json`; renaming keys changes the service contract.

Achievement keys: `kills_1`, `kills_25`, `kills_100`, `kills_500`, `kills_2000`, `levels_1`, `levels_10`, `levels_25`, `levels_50`, `levels_75`, `levels_100`, `stars_10`, `stars_100`, `stars_300`, `level_3`, `level_5`, `level_10`, `survival_60`, `survival_180`, `workshop_8`, `streak_7`.

Leaderboard keys: `eliminations`, `survival_score`, `campaign_stars`, `player_level`, `survival_seconds`.

`play_games.enabled` is now true with owner-supplied achievement/leaderboard mappings and a matching Android export game ID. This enables the Play Games adapter, not cloud saves. Retain matching package, OAuth/signing fingerprints, authorized testers and resource configuration in the owner consoles, then verify actual submissions on the intended signed-in Android build. Preserve these owner edits during future updates.

For AdMob, `banner_unit_id`, `interstitial_unit_id` and `rewarded_unit_id` are the actual requested unit IDs. Set the manifest App ID in Godot Project Settings `admob/general/android/app_id` (the `[admob]` section of `project.godot`), and keep JSON `admob.app_id` consistent as a reference. No platform/game code reads JSON `app_id` to set the manifest. An absent `[admob]` override uses the plugin sample default. `test_mode` only changes status wording; it does not configure test devices or override production unit IDs. Retain Google sample IDs during ordinary development.

Run test scripts and capture fixtures with process-scoped temporary user data: isolate both `APPDATA` and `LOCALAPPDATA` on Windows, or `XDG_DATA_HOME` on Linux. Do not modify global environment settings or run fixtures against genuine player saves. The service adapter also writes pending progress, so a test-only gameplay filename alone does not isolate the entire process.

Actual game test entrypoints:

```sh
godot --headless --path . --script tests/test_fullscreen_lifecycle.gd
godot --headless --path . --script tests/test_models.gd
godot --headless --path . --script tests/test_ui.gd
```

For documentation-only changes, review the diff and links; do not rebuild or overwrite the preserved original QA APK. For runtime/service changes, keep the strict existing CI error gates, run the affected tests and review the changed behavior. Model/stub tests do not replace native test-ad, Back/save/offline and physical-device verification.

Verified pre-consolidation public baseline: `41aa358d6bd765e90dcb28e2309dfbfa8cece0dc`.
[Hosted build/test run](https://github.com/EthannYakabuski/the-final-outlaw/actions/runs/39529171557): **PASS** on that exact commit.
Later documentation commits require their own CI result; this dated result does not verify later binaries.

## Current audio-clock successor build binding

Runtime `e22050edf4787f550dc74e8b1b8777a00077f661` passed exact-source hosted CI39719414433. The Android/Web test artifacts were compiled from frozen raw committed Git files, including the committed test-build preset. A separately edited local export preset was preserved and excluded from compilation and source packaging. Keep that local edit; do not reset or stage it merely to make the tree clean. A later owner build using changed IDs/settings is a distinct binary and needs its own verification.

The owned audio drain now measures its existing target against monotonic elapsed time. The31-check fixture verifies the minimum real duration; the early focused-result JSON remains the original30-check subset. Current native Back returns Home and does not exercise graceful audio shutdown. Passing CI does not replace audible Android or graceful-exit verification.
