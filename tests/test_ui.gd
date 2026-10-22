extends SceneTree
## Application screen wiring and simulated SDK earned callbacks. No actual ads.

class FakeServices extends Node:
	var available: bool = true
	var callback: Callable
	var requests: int = 0
	var rounds: int = 0
	var unlocks: Array = []
	var scores: Dictionary = {}
	func can_reward() -> bool: return available
	func reward_requested(_context: String, action: Callable) -> void:
		requests += 1; callback = action
	func finish(earned: bool) -> void:
		var action: Callable = callback; callback = Callable(); action.call(earned)
	func set_menu_visible(_visible: bool) -> void: pass
	func round_finished() -> void: rounds += 1
	func unlock(key: String) -> void: unlocks.append(key)
	func submit(key: String,value: int) -> void: scores[key] = value
	func open_achievements() -> void: pass
	func open_leaderboards(_key: String) -> void: pass
	func sign_in() -> void: pass
	func privacy_options() -> void: pass
	func status() -> String: return "Test adapter"

var failures: int = 0
var checks: int = 0
var game
var sdk: FakeServices
var original_services: Node

func _install_test_services() -> void:
	# Replace the root lookup before the application runs _ready/_sync_progress.
	original_services = root.get_node_or_null("Services")
	if is_instance_valid(original_services):
		original_services.name = "ServicesUiTestOriginal"
	sdk = FakeServices.new()
	sdk.name = "Services"
	root.add_child(sdk)
	check(root.get_node_or_null("Services") == sdk, "test adapter owns root Services before application ready")

func _restore_test_services() -> void:
	if is_instance_valid(sdk):
		root.remove_child(sdk)
		sdk.free()
	if is_instance_valid(original_services):
		original_services.name = "Services"
	check(root.get_node_or_null("Services") == original_services, "original Services autoload name restored")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1; printerr("FAIL: " + label)

func combat_hint() -> Label:
	for child in game.ui.get_children():
		if child is Label and (child.text.begins_with("Move left thumb;") or child.text.begins_with("DASH:")):
			return child
	return null

func _initialize() -> void:
	call_deferred("_run")

func _settle() -> void:
	await process_frame
	await process_frame

func _run() -> void:
	print("OUTLAW_UI_USER_DIR " + ProjectSettings.globalize_path("user://"))
	_install_test_services()
	game = load("res://main.tscn").instantiate()
	if game.get_script() == null:
		printerr("FAIL: application script failed to load")
		_restore_test_services()
		quit(1)
		return
	game.smoke = true
	game.set_process(false)
	root.add_child(game)
	game.set_process(false)
	check(game.service == sdk and sdk.scores.has("player_level"), "initial progress sync uses test adapter")
	await _settle()
	await _test_responsive_menus()
	for screen in ["home","map","workshop","rewards","records","boards","options"]:
		game.call("_show_" + screen)
		await _settle()
		check(game.screen == screen and game.ui.get_child_count() >= 3, "screen creates controls " + screen)
		for child in game.ui.get_children():
			if child is Button:
				check(child.position.x >= 0 and child.position.y >= 0 and child.position.x + child.size.x <= 541 and child.position.y + child.size.y <= 961, "button inside portrait canvas " + child.text)
			if child is Label:
				check(child.position.x + child.size.x <= 541, "label wraps inside portrait canvas " + child.text.left(30))
	for trail in range(1,101):
		game._show_brief(trail); await _settle()
		for child in game.ui.get_children():
			if child is Label: check(child.position.x + child.size.x <= 541 and child.position.y + child.size.y <= 961, "trail briefing fits %d" % trail)
	# Native Trail 01 previously wrapped onto the joystick and claimed a fixed 20 rounds.
	var previous_magazine: int = int(game.state.upgrades.get("magazine",0))
	for upgrade in [0,1,8]:
		game.state.upgrades.magazine = upgrade
		game._start_level(1,false); await _settle()
		var hint: Label = combat_hint()
		print("HINT_UI magazine=%d lines=%d rect=%s minimum=%s" % [game.battle.magazine,hint.get_line_count(),hint.get_rect(),hint.get_minimum_size()])
		check(hint.text.contains("%d-round magazine" % game.battle.magazine), "tutorial reflects actual magazine upgrade %d" % upgrade)
		check(hint.get_line_count() == 2 and hint.get_rect().end.y <= 799, "tutorial stays two lines above joystick upgrade %d" % upgrade)
		check(hint.mouse_filter == Control.MOUSE_FILTER_IGNORE, "tutorial never captures touch")
	game.state.upgrades.magazine = previous_magazine
	game._show_home(); await _settle()
	var home_reload_hint: bool = false
	for child in game.ui.get_children():
		if child is Label and child.text.contains("Reload when empty"):
			home_reload_hint = true
	check(home_reload_hint, "home reload guidance remains correct for upgraded magazines")
	game._show_brief(1); await _settle()
	var brief_reload_hint: bool = false
	for child in game.ui.get_children():
		if child is Label and child.text.contains("Reload when empty"):
			brief_reload_hint = true
	check(brief_reload_hint, "Trail 01 briefing no longer claims fixed capacity")
	game._start_level(2,false); await _settle()
	var dash_hint: Label = combat_hint()
	check(dash_hint.get_line_count() == 2 and dash_hint.get_rect().end.y <= 799, "dash tutorial stays above joystick")
	game._show_rewards(); await _settle()
	var coins: int = game.state.coins
	game._request_crate(); game._request_crate()
	check(sdk.requests == 1 and game.reward_pending and game.reward_button.disabled, "one pending ad at a time")
	sdk.finish(false)
	check(game.state.coins == coins and not game.reward_pending, "dismissed/error ad does not grant coins")
	game._request_crate(); sdk.finish(true)
	check(game.state.coins == coins + 120 and game.state.rewarded_day == game._today(), "earned callback grants daily crate")
	game._request_crate()
	check(sdk.requests == 2, "daily crate cannot repeat")
	game._start_level(1,false); game.battle.result = "lost"; game.battle.health = 0
	game._show_result(); await _settle()
	game._request_revive(); sdk.finish(false)
	check(game.battle.result == "lost" and not game.battle.revived, "dismissed continue does not revive")
	game._request_revive(); sdk.finish(true)
	check(game.screen == "play" and game.battle.revived and game.battle.health > 0, "earned continue resumes same run")
	game.battle.result = "lost"; game._show_result(); await _settle()
	var count: int = sdk.requests
	game._request_revive()
	check(sdk.requests == count, "no second continue request")
	game._start_level(2,false); game.battle.result = "lost"; game._show_result(); await _settle()
	game._request_revive()
	game._record_result(false); game._start_level(3,false); game.battle.result = "lost"
	sdk.finish(true)
	check(not game.battle.revived, "late earned callback cannot revive a different run")
	sdk.available = false
	game._show_rewards(); await _settle()
	check(game.reward_button.disabled, "offline/Web unavailable ad is disabled")
	game.state.completed["1"] = 3
	game._sync_progress()
	check(sdk.unlocks.has("levels_1") and sdk.scores.has("player_level") and sdk.scores.has("eliminations"), "catalog metrics reach symbolic service keys")
	game._start_level(1,false); game.battle.elapsed = 20; game.battle.kills = 3; game.battle.result = "win"
	game._record_result(true)
	var before: int = game.state.coins
	game._record_result(true)
	check(game.state.coins == before, "result accounting idempotent")
	var rounds_before: int = sdk.rounds
	game._start_level(10,false); game.battle.elapsed = 2; game.battle.result = "win"
	game._record_result(true)
	check(sdk.rounds == rounds_before + 1, "short completed rounds retain round-based ad cadence")
	game._start_level(11,false); game.battle.elapsed = 30
	game._record_result(false)
	check(sdk.rounds == rounds_before + 1, "pause abandonment is not a completed-round interstitial")
	# Reproduce the observed exit ownership: active reward Ogg + looping WAV.
	game.state.settings.sound = true
	game._sound("coin")
	game.music.play()
	check(game.sounds.coin.playing and game.music.playing, "shutdown fixture actually starts both audio streams")
	await game.shutdown_audio()
	check(not game.sounds.coin.playing and game.sounds.coin.stream == null and not game.music.playing and game.music.stream == null, "owned audio releases before scene deletion")
	game._sound("coin")
	game._restart_music()
	check(not game.sounds.coin.playing and not game.music.playing, "shutdown rejects late SFX and music restart callbacks")
	await game.shutdown_audio()
	game.queue_free(); await _settle()
	_restore_test_services()
	await _settle()
	print("OUTLAW_UI_TESTS checks=%d failures=%d (mock service callbacks; no production integration claim)" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _test_responsive_menus() -> void:
	var original_size: Vector2i = root.size
	var profile: Dictionary = game.state.data().duplicate(true)
	for viewport_height in [960, 864]:
		root.size = Vector2i(540, viewport_height)
		await _settle()
		for view in ["home", "workshop"]:
			game.call("_show_" + view)
			await _settle()
			for reserve in [0.0, 100.0, 160.0, 400.0]:
				game._apply_banner_layout(reserve)
				await _settle()
				var available: float = minf(960.0, game.get_viewport_rect().size.y) - reserve
				check(is_equal_approx(game.menu_scroll.size.y, available), "actual viewport minus banner %s/%d/%s" % [view, viewport_height, reserve])
				var buttons: Array[Button] = []
				var heart_copy := false
				var boots_copy := false
				for child in game.ui.get_children():
					if child is Label:
						check(child.size.y + 0.1 >= child.get_minimum_size().y, "label contains all wrapped lines " + child.text.left(30))
						if child.text.contains("+7.2 health"): heart_copy = true
						if child.text.contains("+7.04 speed"): boots_copy = true
						if child.text.contains("Reload when empty"):
							check(child.size.y >= 72.0, "Home help has room for three actual font lines")
					if child is Control:
						check(child.get_rect().end.y <= game.ui.custom_minimum_size.y + 0.1, "content fits declared scroll extent " + view)
						if available >= 800.0:
							check(child.get_rect().end.y <= available + 0.1, "all menu content visible without scrolling " + view)
					if child is Button:
						buttons.append(child)
						check(child.size.y >= 44.0, "menu action retains touch target height")
				for first in range(buttons.size()):
					for second in range(first + 1, buttons.size()):
						check(not buttons[first].get_rect().intersects(buttons[second].get_rect()), "menu actions never overlap")
				check(buttons.size() == (6 if view == "home" else 8), "all primary controls preserved " + view)
				if available < 800.0:
					check(game.menu_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO, "short viewport retains scrolling fallback")
				if view == "workshop": check(heart_copy and boots_copy, "workshop lists actual effective upgrade benefits")
				if view == "home" and game._menu_compaction() >= 1.0:
					check(256.0 + 106.0 * 0.5 < 315.0, "compact hero clears first subtitle/control band")
	root.size = original_size
	game._start_level(1, false)
	await _settle()
	game._apply_banner_layout(400.0)
	check(game.menu_scroll.size == Vector2(540, 960) and game.ui.custom_minimum_size == Vector2(540, 960), "gameplay geometry ignores menu compaction and banner reserve")
	check(game.state.data() == profile, "responsive menus do not alter progression")
	game._show_home()
	await _settle()
