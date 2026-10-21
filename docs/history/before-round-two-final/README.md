# The Final Outlaw

One trail. A hundred last stands.

A portrait western shooter with a 100-level campaign, tutorial opening, distinct challenges, endless survival, player progression and light powerups.

## Play

Choose a campaign challenge or endless survival. Move with your left thumb and hold the gun button to shoot; targeting assists toward a visible foe. The starting magazine holds 20 rounds. Tap RELOAD, or keep firing when empty to start reloading. DASH evades danger. Keyboard: WASD/arrows move, J fires, R reloads, Space dashes and Escape pauses.

The 100 campaign stages have saved town street plans with buildings, doors, paths and cover. Fast fragile runners, heavy tanks, ranged attackers and guardians route around obstacles. Seven equipment tracks improve damage, health, speed, magazine capacity, reload speed, dash recovery and armor. Existing campaign progress and the original three upgrade tracks remain compatible.

Touch/mouse portrait play and offline local saves are supported. Android is the primary target; Web retains gameplay and saves when Android services are unavailable. Browser play never grants pretend ad rewards.

## Continue this project

This game folder is the canonical Git working copy for [The Final Outlaw](https://github.com/EthannYakabuski/the-final-outlaw). Open this folder as its own Codex project and use one focused task per update. Read `AGENTS.md`, `HANDOFF.txt` and `docs/PLATFORM_SETUP.md` first; a new task must recover context from these files rather than assume access to an earlier chat. Check existing user changes before editing.

Verified pre-consolidation public baseline: `41aa358d6bd765e90dcb28e2309dfbfa8cece0dc`.
[Hosted build/test run](https://github.com/EthannYakabuski/the-final-outlaw/actions/runs/39529171557): **PASS** on that exact commit.
Later commits require their own CI result; this dated result does not verify later binaries. The later documentation run39543094868 reproduced an audio shutdown ownership failure. Round Two adds an owned audio drain before scene deletion/exit; isolated active-audio regressions pass. A new hosted CI result is still required for the source changes.

`game/catalog.json` defines 21 achievements and 5 leaderboards. `platform/config.json` maps their symbolic keys to owner-supplied console IDs; the numeric Play Games game ID must also match `export_presets.cfg`. See native setup for the separate AdMob manifest setting and the development test-ID rules.

## Development

Original code: Apache-2.0. Developer: [EthannYakabuski](https://github.com/EthannYakabuski). Included assets/plugins retain their own licenses and notices.

Use Godot **4.5.1**, **Compatibility**, matching export templates, Java 17 and the Android SDK. The test preset uses minimum API 24 and target API 35. This is a test-configured build; final release signing, current Play requirements and production backend verification remain with the owner. See [native setup](docs/PLATFORM_SETUP.md).

```sh
godot --headless --editor --path . --import
godot --headless --path . --script tests/test_models.gd
godot --headless --path . --script platform/tests/services_smoke.gd
godot --headless --path . --export-release Web build/web/index.html
godot --headless --path . --install-android-build-template --export-debug Android build/android/game-debug.apk
```

Create build/web and build/android first. Android package: `com.ethannyakabuski.finaloutlaw`. Tests are documented under game/ and tests/. No Windows build is supplied.

## Integration and handoff

AdMob uses Google's official test IDs. Menus support a banner, every two completed rounds create an interstitial opportunity, and rewarded benefits require the earned-reward callback. Unavailable ads or consent leave normal play usable. Google Play Games uses symbolic achievement/leaderboard maps with empty production IDs and is disabled until the owner configures them. See platform/config.json and docs/PLATFORM_SETUP.md.

New illustrated app/feature and all 26 catalog images, exact originals/prompts and source-aligned store copy are in marketing/. The resize-only artwork packer is offline; old screenshot provenance remains dated first-pass evidence until fresh coordinator captures. The current evidence, limitations and exact next owner actions are in HANDOFF.txt. Production backend testing, human playtesting and Google Play publication are human-owned.

## CI and Web

Hosted GitHub Actions imports resources, runs game/service tests, exports Web and an Android debug APK, and retains export artifacts. Pages deployment remains explicitly disabled. Build outputs, caches and signing keys are excluded from source. Confirm actual run results in HANDOFF.txt; workflow presence alone is not a passing CI claim.

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

Public screenshot metadata records PNG-relative filenames, SHA256 digests, dimensions and the original visual qualifications. Compare files in `marketing/screenshots/` and its `raw/` directory against `capture-manifest.json` with a SHA256 utility; matching hashes verify unchanged image bytes. These public summaries are not internal capture-validator receipts and do not create new device acceptance.
