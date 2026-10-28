extends SceneTree
## Synthetic adapter tests only. These do not authenticate with Google or prove
## native/backend acceptance. The runner must isolate user data and opt in below.

const GameScript = preload("res://game/main.gd")
const PENDING = "user://platform_pending_v1.json"
const SAVE = "user://outlaw_save_v1.json"

var checks := 0
var failures: Array[String] = []
var catalog: Dictionary = {}
var service_serial := 0
var service_script: GDScript
var clients_fixture: GDScript

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: " + label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# This guard is additional protection, not a substitute for process-scoped
	# APPDATA/LOCALAPPDATA (Windows) or XDG_DATA_HOME (Linux) set by the runner.
	if OS.get_environment("OUTLAW_PGS_TEST_ISOLATED") != "1" or OS.get_name() == "Android":
		printerr("FAIL: PGS fixture requires isolated user data and OUTLAW_PGS_TEST_ISOLATED=1; Android execution is forbidden")
		quit(1)
		return
	var isolated_root := OS.get_environment("OUTLAW_PGS_TEST_ROOT").replace("\\", "/").trim_suffix("/")
	var user_path := OS.get_user_data_dir().replace("\\", "/")
	if isolated_root.is_empty() or not user_path.begins_with(isolated_root + "/"):
		printerr("FAIL: PGS fixture user data is outside its explicit isolation root")
		quit(1)
		return
	# A --script entrypoint compiles before autoload globals are registered.
	# Resolve production services and SDK-derived fakes only after deferred _run,
	# when the normal autoload startup has completed. No SDK files are modified.
	service_script = root.get_node("Services").get_script() as GDScript
	clients_fixture = load("res://tests/play_games_clients_fixture.gd") as GDScript
	if service_script == null or clients_fixture == null or not clients_fixture.can_instantiate():
		printerr("FAIL: post-autoload Play Games test scripts failed to load")
		quit(1)
		return
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://game/catalog.json"))
	check(catalog.get("achievements", []).size() == 21 and catalog.get("leaderboards", []).size() == 5, "fixture exercises the complete Outlaw service catalog")
	await _test_existing_save_backfill()
	await _test_complete_achievement_mapping()
	await _test_authentication_and_deduplication()
	await _test_manual_sign_in_and_pending_views()
	await _test_score_acknowledges_captured_value()
	await _test_failed_submissions_retry()
	await _test_missing_callbacks_and_late_scores()
	await _test_missing_ids_and_invalid_keys()
	await _test_pending_journal_restart_and_validation()
	_erase_synthetic_files()
	print("OUTLAW_PLAY_GAMES_TESTS checks=%d failures=%d; synthetic adapters only, no Google/backend validation" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _settle() -> void:
	await process_frame
	await process_frame

func _erase_pending() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = PENDING + suffix
		if FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(path) == OK, "remove only synthetic isolated pending file " + suffix)

func _erase_synthetic_files() -> void:
	_erase_pending()
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = SAVE + suffix
		if FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(path) == OK, "remove only synthetic isolated game save " + suffix)

func _settings() -> Dictionary:
	var achievements := {}
	var boards := {}
	for item in catalog.get("achievements", []): achievements[str(item.key)] = "fixture-ach-" + str(item.key)
	for item in catalog.get("leaderboards", []): boards[str(item.key)] = "fixture-board-" + str(item.key)
	return {"play_games": {"enabled": true, "game_id": "fixture-game", "achievements": achievements, "leaderboards": boards}}

func _service(clear_journal: bool = true) -> Node:
	if clear_journal: _erase_pending()
	var service: Node = service_script.new()
	service_serial += 1
	service.name = "PgsFixture%d" % service_serial
	# Desktop _ready loads the real journal code and then takes its non-native
	# fallback. Override settings only with synthetic IDs before fake binding.
	root.add_child(service)
	service.set_process(false)
	service.settings = _settings()
	return service

func _clients(service: Node) -> Dictionary:
	var sign: Variant = clients_fixture.FakeSignIn.new()
	var achievements: Variant = clients_fixture.FakeAchievements.new()
	var boards: Variant = clients_fixture.FakeBoards.new()
	service._bind_play_games_clients(sign, achievements, boards)
	return {"sign": sign, "achievements": achievements, "boards": boards}

func _dispose(service: Node) -> void:
	if is_instance_valid(service):
		service.set_process(false)
		service.queue_free()
	await _settle()

func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "isolated fixture can write synthetic JSON")
	if file != null:
		file.store_string(JSON.stringify(value))
		file.close()

func _test_existing_save_backfill() -> void:
	_erase_synthetic_files()
	var seed = GameScript.new()
	seed.state.coins = 91
	seed.state.xp = 675
	seed.state.eliminations = 123
	seed.state.best_survival = 5555
	seed.state.best_seconds = 180
	seed.state.completed = {"1": 3, "2": 2}
	seed.state.streak = 1
	seed.state.unlocked = {"kills_1": true, "streak_7": true, "unknown_old_flag": true}
	seed._save()
	seed.free()
	var service = _service()
	var game = GameScript.new()
	game._load()
	game.catalog = catalog
	game.service = service
	var original_coins: int = game.state.coins
	var original_xp: int = game.state.xp
	game._sync_progress()
	await _settle()
	check(service._pending_unlocks.has("kills_1"), "already-earned save flag backfills when pending journal is absent")
	check(service._pending_unlocks.has("streak_7") and game.state.streak == 1, "earned seven-day achievement survives rolled-over current streak")
	check(game.state.unlocked.has("kills_25") and service._pending_unlocks.has("kills_25"), "met local threshold adds and queues its standard achievement")
	check(not game.state.unlocked.has("kills_500") and not service._pending_unlocks.has("kills_500"), "unmet threshold never grants an achievement")
	check(not service._pending_unlocks.has("unknown_old_flag"), "unknown historical flags never become remote achievement submissions")
	check(game.state.coins == original_coins and game.state.xp == original_xp, "service backfill does not grant coins or XP")
	var expected := {"eliminations": 123, "survival_score": 5555, "campaign_stars": 5, "player_level": 4, "survival_seconds": 180}
	check(service._pending_scores == expected, "all five metrics retain their unscaled integer values, including whole seconds")
	var persisted: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	check(persisted is Dictionary and persisted.get("unlocked", {}).get("kills_25", false), "newly earned local flags are persisted without a later gameplay action")
	var clients := _clients(service)
	check(clients.sign.checks == 1 and clients.boards.submissions.is_empty(), "binding requests authentication before any remote dispatch")
	clients.sign.complete(true)
	await _settle()
	check(clients.boards.submissions.size() == 5, "all five real catalog metrics reach the adapter once")
	for key in expected:
		check(clients.boards.latest_value("fixture-board-" + str(key)) == expected[key], "correct raw value for " + str(key))
	check(clients.achievements.incremental_requests == 0, "standard achievements never use incremental or set-steps APIs")
	game.free()
	await _dispose(service)

func _test_authentication_and_deduplication() -> void:
	var service = _service()
	service.unlock("kills_25")
	service.submit("survival_seconds", 180)
	var clients := _clients(service)
	await _settle()
	check(clients.achievements.unlocks.is_empty() and clients.boards.submissions.is_empty(), "offline state never fabricates remote success")
	clients.sign.complete(false)
	await _settle()
	check(not service._signed_in and clients.boards.submissions.is_empty(), "failed automatic authentication keeps progress local")
	service.sign_in()
	check(clients.sign.interactive_requests == 1, "only explicit sign-in requests interactive authentication")
	clients.sign.complete(true)
	await _settle()
	check(clients.achievements.unlocks == ["fixture-ach-kills_25"] and clients.boards.count_for("fixture-board-survival_seconds") == 1, "successful authentication sends retained progress with matching IDs")
	for repeat in range(8):
		service.unlock("kills_25")
		service.submit("survival_seconds", 180)
		service._queue_progress_flush()
	await _settle()
	check(clients.achievements.unlocks.size() == 1 and clients.boards.submissions.size() == 1, "duplicate game updates do not flood in-flight requests")
	clients.achievements.complete("fixture-ach-kills_25", true)
	clients.boards.complete("fixture-board-survival_seconds", true)
	await _settle()
	service.unlock("kills_25")
	service.submit("survival_seconds", 179)
	service._flush_pending()
	await _settle()
	check(clients.achievements.unlocks.size() == 1 and clients.boards.submissions.size() == 1, "acknowledged unchanged achievement and lower score are not resent in one session")
	check(service._pending_scores.get("survival_seconds") == 180 and service._pending_unlocks.has("kills_25"), "acknowledgement retains durable desired progress")
	clients.sign.complete(false)
	clients.sign.complete(true)
	await _settle()
	check(clients.achievements.unlocks.size() == 2 and clients.boards.submissions.size() == 2, "new authenticated session replays genuine desired progress")
	await _dispose(service)

func _test_complete_achievement_mapping() -> void:
	var service = _service()
	var clients := _clients(service)
	var expected: Array[String] = []
	for item in catalog.get("achievements", []):
		var key := str(item.key)
		expected.append("fixture-ach-" + key)
		service.unlock(key)
	clients.sign.complete(true)
	await _settle()
	var actual: Array[String] = clients.achievements.unlocks.duplicate()
	actual.sort()
	expected.sort()
	check(actual == expected, "all 21 symbolic achievements dispatch their distinct matching configured remote IDs")
	check(clients.achievements.incremental_requests == 0, "complete catalog uses standard unlock requests exclusively")
	for remote_id in expected: clients.achievements.complete(remote_id, true)
	for item in catalog.get("achievements", []): service.unlock(str(item.key))
	await _settle()
	check(clients.achievements.unlocks.size() == 21, "acknowledged complete catalog is not redundantly dispatched again")
	await _dispose(service)

func _test_score_acknowledges_captured_value() -> void:
	var service = _service()
	var clients := _clients(service)
	clients.sign.complete(true)
	service.submit("survival_seconds", 180)
	await _settle()
	service.submit("survival_seconds", 240)
	await _settle()
	check(clients.boards.submissions.size() == 1, "higher value waits behind the existing request for the same remote ID")
	clients.boards.complete("fixture-board-survival_seconds", true)
	var acknowledged: Dictionary = service._submitted_scores.get("survival_seconds", {})
	check(int(acknowledged.get("value", -1)) == 180, "older success acknowledges the captured sent value, not the newer desired value")
	await _settle()
	check(clients.boards.count_for("fixture-board-survival_seconds") == 2 and clients.boards.latest_value("fixture-board-survival_seconds") == 240, "newer high score is dispatched after the old request settles")
	clients.boards.complete("fixture-board-survival_seconds", true)
	await _settle()
	acknowledged = service._submitted_scores.get("survival_seconds", {})
	check(int(acknowledged.get("value", -1)) == 240, "newer score is acknowledged only by its own completion")
	check(service._pending_scores.get("survival_seconds") == 240, "highest desired score remains durable after acknowledgement")
	await _dispose(service)

func _test_manual_sign_in_and_pending_views() -> void:
	var service = _service()
	var clients := _clients(service)
	service.open_achievements()
	service.sign_in()
	service.sign_in()
	check(clients.sign.interactive_requests == 0, "manual requests wait behind the current automatic authentication check")
	clients.sign.complete(false)
	check(clients.sign.interactive_requests == 1, "queued manual sign-in starts exactly once after automatic authentication returns false")
	clients.sign.complete(true)
	await _settle()
	check(clients.achievements.opened == 1, "requested achievements view opens after successful sign-in")
	service.open_leaderboards("survival_seconds")
	check(clients.boards.opened == ["fixture-board-survival_seconds"], "specific leaderboard view uses the configured remote ID")
	clients.sign.complete(false)
	service.open_leaderboards("survival_score")
	clients.sign.complete(false)
	await _settle()
	var interactive_after_cancel: int = clients.sign.interactive_requests
	service._process_play_games(31.0)
	await _settle()
	check(clients.sign.interactive_requests == interactive_after_cancel, "cancellation never causes repeated background interactive prompts")
	check(clients.sign.checks >= 2, "background reconnect uses a non-interactive authentication check")
	check(clients.boards.opened.size() == 1, "cancelled sign-in does not open the pending online leaderboard")
	await _dispose(service)

func _test_failed_submissions_retry() -> void:
	var service = _service()
	var clients := _clients(service)
	service.unlock("kills_1")
	service.submit("eliminations", 7)
	clients.sign.complete(true)
	await _settle()
	clients.achievements.complete("fixture-ach-kills_1", false)
	clients.boards.complete("fixture-board-eliminations", false)
	await _settle()
	check(service._pending_unlocks.has("kills_1") and service._pending_scores.get("eliminations") == 7, "failed callbacks retain durable desired values")
	check(not service._submitted_unlocks.has("kills_1") and not service._submitted_scores.has("eliminations"), "failed callbacks never become successful acknowledgements")
	var failed_unlock_count: int = clients.achievements.unlocks.size()
	var failed_score_count: int = clients.boards.submissions.size()
	service.unlock("kills_1")
	service.submit("eliminations", 8)
	await _settle()
	check(clients.achievements.unlocks.size() == failed_unlock_count and clients.boards.submissions.size() == failed_score_count, "new progress retains its higher value without bypassing failed-upload backoff")
	service._process_play_games(31.0)
	await _settle()
	check(clients.sign.checks >= 2 and not service._signed_in, "failed submission schedules a non-interactive authentication recheck")
	clients.sign.complete(true)
	await _settle()
	check(clients.achievements.unlocks.size() >= 2 and clients.boards.count_for("fixture-board-eliminations") >= 2, "bounded retry tick retries failed unlock and score without new gameplay")
	check(clients.sign.interactive_requests == 0, "background retry never opens an interactive sign-in request")
	await _dispose(service)

func _test_missing_callbacks_and_late_scores() -> void:
	var service = _service()
	var clients := _clients(service)
	service.submit("survival_score", 100)
	# An unanswered authentication check must not block an explicit retry forever.
	service._process_play_games(21.0)
	await _settle()
	service.sign_in()
	check(clients.sign.interactive_requests == 1, "authentication timeout permits a later explicit sign-in")
	clients.sign.complete(true)
	await _settle()
	service.submit("survival_score", 300)
	service._process_play_games(31.0)
	await _settle()
	check(service._pending_scores.get("survival_score") == 300, "missing callback does not lose the newer desired score")
	check(service._uncertain_score_ids.has("fixture-board-survival_score") and clients.boards.count_for("fixture-board-survival_score") >= 2, "missing score callback expires and retries without assuming an acknowledgement")
	clients.boards.complete("fixture-board-survival_score", true)
	await _settle()
	var acknowledged: Dictionary = service._submitted_scores.get("survival_score", {})
	check(int(acknowledged.get("value", -1)) != 300, "ambiguous late success never falsely acknowledges a newer value")
	check(service._pending_scores.get("survival_score") == 300, "late callback cannot remove durable desired progress")
	var ambiguous_count: int = clients.boards.submissions.size()
	service.submit("survival_score", 300)
	await _settle()
	check(clients.boards.submissions.size() == ambiguous_count, "an unchanged ambiguous score cannot bypass the retry cooldown")
	await _dispose(service)

func _test_missing_ids_and_invalid_keys() -> void:
	var service = _service()
	service.settings.play_games.achievements["kills_1"] = ""
	service.settings.play_games.leaderboards["survival_seconds"] = ""
	service.unlock("kills_1")
	service.submit("survival_seconds", 180)
	service.unlock("unknown_achievement")
	service.submit("unknown_board", 999)
	var clients := _clients(service)
	clients.sign.complete(true)
	await _settle()
	check(clients.achievements.unlocks.is_empty() and clients.boards.submissions.is_empty(), "missing mappings never send blank remote IDs")
	check(service._pending_unlocks.has("kills_1") and service._pending_scores.get("survival_seconds") == 180, "missing mappings retain real progress for later configuration")
	check(not service._pending_unlocks.has("unknown_achievement") and not service._pending_scores.has("unknown_board"), "unrecognized symbolic keys are rejected")
	service.settings.play_games.achievements["kills_1"] = "fixture-ach-kills_1"
	service.settings.play_games.leaderboards["survival_seconds"] = "fixture-board-survival_seconds"
	service._flush_pending()
	await _settle()
	check(clients.achievements.unlocks == ["fixture-ach-kills_1"] and clients.boards.latest_value("fixture-board-survival_seconds") == 180, "adding mappings submits the retained genuine values without replaying gameplay")
	await _dispose(service)

func _test_pending_journal_restart_and_validation() -> void:
	var service = _service()
	service.unlock("kills_25")
	service.submit("survival_seconds", 180)
	service.submit("survival_seconds", 240)
	await _settle()
	check(FileAccess.file_exists(PENDING) and not FileAccess.file_exists(PENDING + ".tmp"), "successful ledger write leaves a complete primary and no temporary file")
	var backup: Variant = JSON.parse_string(FileAccess.get_file_as_string(PENDING + ".bak"))
	check(backup is Dictionary, "replacing a valid ledger retains a parseable last-good backup")
	await _dispose(service)
	service = _service(false)
	check(service._pending_unlocks.has("kills_25") and service._pending_scores.get("survival_seconds") == 240, "restart restores the retained unlock and highest whole-second value")
	check(service._submitted_unlocks.is_empty() and service._submitted_scores.is_empty(), "session acknowledgements are not trusted across a process restart")
	await _dispose(service)
	_erase_pending()
	_write_json(PENDING, {"unlocks": {"kills_1": true, "kills_25": "true", "unknown_achievement": true}, "scores": {"survival_seconds": 180, "player_level": 4, "eliminations": -1, "campaign_stars": "bad", "survival_score": 3.5, "unknown_board": 99}})
	service = _service(false)
	check(service._pending_unlocks == {"kills_1": true}, "journal validation accepts only true flags for known achievement keys")
	check(service._pending_scores.get("survival_seconds") == 180 and service._pending_scores.get("player_level") == 4, "JSON numeric integers round-trip as valid unscaled scores")
	check(not service._pending_scores.has("unknown_board") and not service._pending_scores.has("eliminations") and not service._pending_scores.has("campaign_stars") and not service._pending_scores.has("survival_score"), "negative, fractional, string and unknown journal scores are safely ignored")
	await _dispose(service)
	_erase_pending()
	_write_json(PENDING, {"unlocks": [], "scores": "not-a-dictionary"})
	_write_json(PENDING + ".bak", {"unlocks": {"kills_25": true}, "scores": {"survival_seconds": 180}})
	service = _service(false)
	check(service._pending_unlocks.has("kills_25") and service._pending_scores.get("survival_seconds") == 180, "malformed primary field types fall back to the last-good journal")
	await _dispose(service)
	_erase_pending()
	_write_json(PENDING, {"unlocks": {"kills_1": true}, "scores": {"survival_seconds": 120}})
	_write_json(PENDING + ".bak", {"unlocks": {"kills_25": true}, "scores": {"survival_seconds": 180}})
	_write_json(PENDING + ".tmp", {"unlocks": {"levels_1": true}, "scores": {"survival_seconds": 240}})
	service = _service(false)
	check(service._pending_unlocks.has("kills_1") and service._pending_unlocks.has("kills_25") and service._pending_unlocks.has("levels_1"), "interrupted write recovery preserves the union of valid unlocks")
	check(service._pending_scores.get("survival_seconds") == 240, "primary, backup and temporary journals recover the highest valid raw score")
	await _dispose(service)
