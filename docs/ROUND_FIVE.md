# Round Five: controls, routes and endless opening

This update implements the four Outlaw items in the owner's Round Five guidance. Android remains primary; Godot 4.5.1 Compatibility and Web fallback remain supported.

## Acceptance checklist

| Item | Implemented behavior | Verification scope |
| --- | --- | --- |
| A | DASH is immediately left of SHOOT, aligned at y805, both 153×89 logical units, with a 12-unit separation. RELOAD retains its separate target below SHOOT. | Actual viewport pointer fixture asserts geometry and input ownership; affected visual/native review remains separate. |
| B | The runner is the fast archetype. Its final speed is multiplied by 0.85 after existing stage, swift-rule and Round Three scaling. Other archetypes retain their scaling. | Focused spawn/movement fixtures and the updated Round Three invariant matrix. |
| C | All 100 campaign towns retain all 650 houses and their dimensions, roof choices and door offsets. Boundary houses move inward to leave a two-tile walking ring: at least 62 px at left/right and 64 px at top/bottom. Covers and decorative props relocate out of the ring; road tiles mark the clear perimeter. | Static all-town audit preserves100 distinct physical layouts with no house overlap and connected navigation. Engine fixtures cover campaign routes, all 100 endless-seed choices and controlled corner pursuit/attack. |
| D | Endless begins with a 3-second introduction. Spawn intervals, crowd cap and enemy strength increase through the first 60 seconds and join the prior challenge curve at 60 seconds. Drifters appear first, runners join at 20 seconds, gunners at 40 seconds, heavy/sniper enemies after 60 seconds. Hazards start after 30 seconds with one point, growing to the original two after 60 seconds. | Boundary-time/roster/cadence fixtures; actual player balance and device acceptance remain distinct. |

The movement collision radii remain 15 px for the player and 14 px for all enemy archetypes. The perimeter audit also checks a conservative 27 px obstruction envelope matching the boss projectile-hit radius. No house is removed. Navigation now skips nearby waypoints only when the following segment is actor-clear, and clamps travel to a reached waypoint instead of overshooting a turn.

## Source checks

Local strict source checks passed: 23,823 focused Round Five checks, 25,925 model checks, 5,337 Round Three invariants, 22 Viewport pointer checks, 2,508 UI checks, 31 fullscreen lifecycle checks, 96 Play Games checks, and the service smoke test. Import also passed. [The sanitized acceptance record](ROUND_FIVE_ACCEPTANCE.json) states the exact scope and limitations. These results do not establish native or human balance acceptance.

Use isolated per-process APPDATA and LOCALAPPDATA on Windows, or XDG_DATA_HOME on Linux. Do not run fixtures against genuine saves. Run the import, `tests/test_round_five.gd`, existing model/round-three/touch/UI/lifecycle tests, `platform/tests/services_smoke.gd`, and the Play Games regression fixture using its documented isolation guards. The strict script/parse/assertion/engine-error gate remains mandatory.

The controlled pursuit fixture does not inject progression, alter a player save, bank rewards or authenticate with Google. It neutralizes only the objective deadline so a slow enemy can demonstrate pathing to a stationary ordinary-health player. It is source-model evidence, not native or human gameplay acceptance.

The existing 21 Standard achievements and five unscaled numeric leaderboard mappings, including whole-second survival records, are unchanged. Owner configuration and the separately modified local export preset are preserved. Do not stage unrelated owner edits merely to make status clean.

## Build and owner limits

The old local APK/AABs and their screenshots retain their named source hashes; they do not contain Round Five. Hosted CI must be matched to the new public source commit and does not establish real signed-in services, physical touch, audio or human balance. Root coordinates fresh Web visual review and any available native route. No native acceptance is claimed without fresh evidence. No Play publication, production signing, account changes or new games are part of this update.
