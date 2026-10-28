# The Final Outlaw

## 2026-10-28: Play Games source integration

The owner has supplied all 21 achievement IDs and five leaderboard IDs in `platform/config.json`, enabled `play_games.enabled`, and supplied the matching Android export game ID. This flag enables Play Games authentication, achievements and leaderboards; it does not enable cloud saves. Saves remain local to the device. Enabling Saved Games in Play Console does not implement the unused Snapshot API in this game.

All achievements use **Standard** unlocks. All leaderboards use **Numeric**, **0 decimal places**, **Larger is better**; `survival_seconds` sends whole seconds. Existing earned unlock flags, including a seven-day streak whose current counter has rolled over, are backfilled without granting gameplay rewards. The adapter retains validated desired unlocks and best scores, handles native result callbacks, coalesces requests, rechecks authentication on resume and retries failures with a 30-second backoff. Interactive sign-in follows a player action. See [the current configuration and device checklist](docs/PLATFORM_SETUP.md#2026-10-28-play-games-integration).

Local Godot 4.5.1 checks passed: 96 focused Play Games checks plus the existing model, fullscreen lifecycle, balance, touch, UI and service smoke suites, with clean strict diagnostics. See [the sanitized source validation](docs/PLAY_GAMES_VALIDATION.json). The containing commit's Actions run provides its hosted Android/Web build result; neither these source checks nor exports establish real signed-in backend acceptance. No local replacement binary was built. The artifacts below remain tied to their dated source revisions and do not contain this integration. AdMob configuration and gameplay rules are unchanged.

## Round Four: qualified Android App Bundle

The accepted debug/test AAB is `build/round-four-aab-002/the-final-outlaw-debug.aab` (95934834 bytes), SHA256 `3BA42538514249C8EFC905C98DFB056ED665EDEB9C40232F0D9189AD04CBFF7D`. Build source: `c9c600099db3f381202f0e5c240d7cc22bd4940c`. The preset used minimum API 24/target API 36; Godot 4.5.1 Compatibility exported it successfully. The actual bundle passed six native ELF-header checks and matching 32/64-bit library coverage for ARM64, x86 and x86_64.

Round Four scope is the Android build correction only; gameplay, service IDs and genuine saves were not changed by this delivery.

This AAB has not been installed/native-tested, production-signed or uploaded to Play. Earlier native QA and screenshots below remain tied to their named older APKs. Round Four source revision `9bb2d806a2389b39162dafe9ad6c26df475ea7f9` is public and its [exact-commit hosted CI](https://github.com/EthannYakabuski/the-final-outlaw/actions/runs/40125506666) passed. This source result does not native-test the frozen AAB above. Owner release signing, an unused version code, current Play checks and real-service/device testing remain separate. See [Android changes](docs/ROUND_FOUR_ANDROID.md), [platform setup](docs/PLATFORM_SETUP.md) and [handoff](HANDOFF.txt).

One trail. A hundred last stands.

A portrait western shooter with a 100-level campaign, tutorial opening, distinct challenges, endless survival, player progression and light powerups.

## Round Three source update

Enemies take three additional unupgraded five-damage shots after stage/endless and armored-stage health scaling. Their final movement speed is25% higher and contact/projectile damage15% higher; environmental hazards keep their existing damage. Player health is40% lower and movement12% slower across all equipment ranks. Reinforced vests add7.2 effective health per rank and Trail boots add7.04 effective speed. Equipment ranks, saves, manual fire,20+4/rank magazines, reloads and earned-only rewards retain their existing contracts.

Home and Workshop compact vertical spacing when the actual viewport/banner leaves less room. Fonts and touch targets retain their sizes, the decorative Home hero follows the compact layout, and help has room for three lines. Viewports below800 logical units retain scrolling rather than squeezing controls. Runtime `5e3588a6540dbc2dc3a64f831a521eb0fc7ebb5f` has verified Android/Web test exports under `build/round-three-5e3588a6-a1/` and [exact-source CI SUCCESS](https://github.com/EthannYakabuski/the-final-outlaw/actions/runs/39793134077). Full artifact hashes and qualified native scope are in `HANDOFF.txt`. Ordinary shooting, reload, sequential movement, pause/background return and once-only banking were observed; the first bank survived a fully loaded cold launch. Eighteen unchanged guest screenshots cover six views per logical phone/7-inch/10-inch profile. Actual offline and simultaneous native two-finger control remain unverified. The preserved Round Two package does not contain these changes.

## Preserved Round Two local package

Runtime `e22050edf4787f550dc74e8b1b8777a00077f661` has Root-accepted Android/Web test exports under `build/round-two-e22050ed-a2/`. Android SHA256 `9673417D958EAEE02349D8A9299C17DA48EDE8A3FB286D304A334B71E7F47212`. Exact-source [CI39719414433](https://github.com/EthannYakabuski/the-final-outlaw/actions/runs/39719414433) passed. Final handoff/docs identity and its hosted result are separate.

Current9673 passed qualified native menu/Back and subsequent18-group cold retention after an explicit genuine-profile restoration. Nine current Home/Workshop/Campaignmap images were Root-accepted with secondary-footer clipping retained as a known limit. Native graceful audio exit was not exercised; the broad log gate is false. Older1D73 controls and CFC169.315-second earned-ad/offline observations remain predecessor evidence. See HANDOFF for exact scope and limits.

## Play

Choose a campaign challenge or endless survival. Move with your left thumb and hold the gun button to shoot; targeting assists toward a visible foe. The starting magazine holds 20 rounds. Tap RELOAD, or keep firing when empty to start reloading. DASH evades danger. Keyboard: WASD/arrows move, J fires, R reloads, Space dashes and Escape pauses.

The 100 campaign stages have saved town street plans with buildings, doors, paths and cover. Fast fragile runners, heavy tanks, ranged attackers and guardians route around obstacles. Seven equipment tracks improve damage, health, speed, magazine capacity, reload speed, dash recovery and armor. Existing campaign progress and the original three upgrade tracks remain compatible.

Touch/mouse portrait play and offline local saves are supported. Android is the primary target; Web retains gameplay and saves when Android services are unavailable. Browser play never grants pretend ad rewards.

## Continue this project

This game folder is the canonical Git working copy for [The Final Outlaw](https://github.com/EthannYakabuski/the-final-outlaw). Open this folder as its own Codex project and use one focused task per update. Read `AGENTS.md`, `HANDOFF.txt` and `docs/PLATFORM_SETUP.md` first; a new task must recover context from these files rather than assume access to an earlier chat. Check existing user changes before editing.

Verified pre-consolidation public baseline: `41aa358d6bd765e90dcb28e2309dfbfa8cece0dc`.
[Hosted build/test run](https://github.com/EthannYakabuski/the-final-outlaw/actions/runs/39529171557): **PASS** on that exact commit.
Later commits require their own CI result; this dated result does not verify later binaries. The later historical audio-retention failures are preserved. The current monotonic drain helper enforces real elapsed duration rather than a frame timer that could count pre-creation time. The31-check fixture and exacte220 hosted Linux CI passed; this does not establish native graceful audio shutdown. The test exports/source bundle use committed build settings; the separately edited local preset was preserved and excluded.

`game/catalog.json` defines 21 achievements and 5 leaderboards. `platform/config.json` maps their symbolic keys to owner-supplied console IDs; the numeric Play Games game ID must also match `export_presets.cfg`. See native setup for the separate AdMob manifest setting and the development test-ID rules.

## Development

Original code: Apache-2.0. Developer: [EthannYakabuski](https://github.com/EthannYakabuski). Included assets/plugins retain their own licenses and notices.

Use Godot **4.5.1**, **Compatibility**, matching export templates, Java 17 and the Android SDK. The test preset uses minimum API 24 and target API 36. This is a test-configured build; final release signing, current Play requirements and production backend verification remain with the owner. See [native setup](docs/PLATFORM_SETUP.md).

```sh
godot --headless --editor --path . --import
godot --headless --path . --script tests/test_models.gd
godot --headless --path . --script platform/tests/services_smoke.gd
godot --headless --path . --export-release Web build/local-next/web/index.html
godot --headless --path . --install-android-build-template --export-debug Android build/local-next/android/game-debug.aab
python tools/verify_android_bundle.py build/local-next/android/game-debug.aab --preset export_presets.cfg
```

Choose a new unused build version directory and create its web/android subfolders first; local-next is only an example. Never overwrite the preserved original or accepted test artifacts. Android package: `com.ethannyakabuski.finaloutlaw`. Tests are documented under game/ and tests/. No Windows build is supplied.

## Integration and handoff

AdMob uses Google's official test IDs. Menus support a banner, every two completed rounds create an interstitial opportunity, and rewarded benefits require the earned-reward callback. Unavailable ads or consent leave normal play usable. Google Play Games now has owner-supplied achievement/leaderboard ID maps and is enabled in the source configuration. Matching package, OAuth/signing, testers and resource configuration still require real Android verification. See platform/config.json and docs/PLATFORM_SETUP.md.

New illustrated app/feature and all 26 catalog images, exact originals/prompts and source-aligned store copy are in marketing/. Eighteen current native images are selected under marketing/screenshots/round-three-f292447f/; nine9673 menu views and earlier first-pass/1D73 images remain separately qualified. The current evidence, limitations and exact next owner actions are in HANDOFF.txt. Production backend testing, human playtesting and Google Play publication are human-owned.

## CI and Web

Hosted GitHub Actions imports resources, runs game/service tests, exports Web and an Android debug AAB, and retains export artifacts. Pages deployment remains explicitly disabled. Build outputs, caches and signing keys are excluded from source. Confirm actual run results in HANDOFF.txt; workflow presence alone is not a passing CI claim.

## Future extension

Ghost Mesa: a new campaign chapter with spectral hazards and a new survival modifier.

## Licenses

See [the complete accompanying notices](LICENSES/INDEX.txt) for the engine,
fonts, plugins and assets. Keep the `LICENSES` directory with every redistributed
Android or Web build; original-code Apache licensing does not replace third-party
terms. CI copies these notices beside both exports and includes them with the
Android artifact.

## Public source and deployment status

The public repository contains source, assets, notices and sanitized verification summaries. Original local QA APKs, raw SDK logs, real saves, signing material and private evidence stay outside tracked public content. Local restored build outputs remain ignored. Hosted export artifacts are separate binaries from the APK named in HANDOFF.txt and have not received that original native QA.

Pages remains disabled; no live deployment, Library action or Google Play publication is part of this handoff. Keep the complete third-party notices with redistributed source and builds.

## Screenshot verification

Public screenshot metadata records PNG-relative filenames, SHA256 digests, dimensions and the original visual qualifications. Compare the18 files under `marketing/screenshots/round-three-f292447f/` against its `capture-manifest.json` with a SHA256 utility; matching hashes verify unchanged guest bytes. Actual display readbacks identify logical profiles. Earlier manifests/PNGs retain their original build provenance. These public summaries are not internal capture-validator receipts and do not create new device acceptance.
