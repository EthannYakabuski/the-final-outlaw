extends SceneTree
## Isolated synthetic callbacks and headless frame stepping; no native-ad claim.

class NoPersistenceServices extends Node:
	signal availability_changed
	var logic: Node
	var available := true
	var requests := 0
	var persistence_calls := 0
	var _reward_showing: bool:
		get: return bool(logic.get("_reward_showing"))
		set(value): logic.set("_reward_showing", value)
	var _interstitial_showing: bool:
		get: return bool(logic.get("_interstitial_showing"))
		set(value): logic.set("_interstitial_showing", value)
	var _reward_granted: bool:
		get: return bool(logic.get("_reward_granted"))
		set(value): logic.set("_reward_granted", value)
	var _reward_callback: Callable:
		get: return logic.get("_reward_callback")
		set(value): logic.set("_reward_callback", value)
	func fullscreen_ad_active() -> bool: return bool(logic.call("fullscreen_ad_active"))
	func can_reward() -> bool: return available and not fullscreen_ad_active()
	func reward_requested(context: String, action: Callable) -> void:
		requests += 1
		logic.set("_reward_context", context)
		_reward_callback = action
		_reward_granted = false
		_reward_showing = true
		availability_changed.emit()
	func set_menu_visible(_visible: bool) -> void: pass
	func round_finished() -> void: pass
	func unlock(_key: String) -> void: pass
	func submit(_key: String, _value: int) -> void: pass
	func earn() -> void: logic.call("_earned_reward", null)
	func close() -> void: logic.call("_rewarded_closed")

var checks := 0
var failures: Array[String] = []
var labels: Array[String] = []
var game
var sdk: NoPersistenceServices
var original_services: Node

func check(ok: bool, label: String) -> void:
	checks += 1
	labels.append(label)
	if not ok:
		failures.append(label)
		printerr("FAIL: " + label)

func fingerprint() -> String:
	var b = game.battle
	return JSON.stringify({"elapsed": b.elapsed, "health": b.health, "invincible": b.invincible,
		"player": b.player, "result": b.result, "revived": b.revived, "score": b.score,
		"enemies": b.enemies, "bullets": b.bullets, "pickups": b.pickups,
		"ammo":b.ammo,"reload":b.reload_time,
		"spawn": b.spawn_timer, "fire": b.fire_timer, "dash": b.dash_cooldown,
		"rapid": b.rapid_time, "spread": b.spread_time, "shield": b.shield_time,
		"rng": b.rng.state, "deadline": b.level.time_limit})

func fresh_lost(level: int = 1) -> void:
	sdk._reward_showing = false
	sdk._interstitial_showing = false
	sdk._reward_callback = Callable()
	sdk._reward_granted = false
	game.application_suspended = false
	game._discard_next_combat_delta = false
	game._waiting_for_neutral_movement = false
	game._waiting_for_neutral_fire = false
	game.reward_pending = false
	game.frame_count = 10
	game._start_level(level, false)
	game.battle.result = "lost"
	game.battle.health = 0
	game._show_result()

func _initialize() -> void:
	call_deferred("run")

func _audio_watch() -> Dictionary:
	# Keep only weak observers; no audio object survives this helper's return.
	var shot: AudioStreamPlayer = game.sounds["shoot"]
	return {"start_us": Time.get_ticks_usec(), "player": weakref(shot),
		"stream": weakref(shot.stream),
		"playback": weakref(shot.get_stream_playback()) if shot.has_stream_playback() else null}

func _audio_ref_snapshot(observer: Variant) -> Dictionary:
	var value: Variant = observer.get_ref() if observer != null else null
	if value == null: return {"alive": false}
	var snapshot := {"alive": true, "type": value.get_class()}
	if value is RefCounted:
		# This includes the temporary reference used only inside this helper.
		snapshot["refcount_during_observation"] = value.get_reference_count()
	if value is Resource and value.resource_path.begins_with("res://"):
		snapshot["source"] = value.resource_path
	if value is AudioStreamPlayback: snapshot["playing"] = value.is_playing()
	if value is AudioStreamPlayer:
		snapshot["playing"] = value.playing
		snapshot["has_playback"] = value.has_stream_playback()
		snapshot["stream_is_null"] = value.stream == null
	value = null
	return snapshot

func _audio_diagnostic(boundary: String, watch: Dictionary) -> void:
	# Observations can perturb timing; an exit without leaks is not a repair.
	var snapshot := {"boundary": boundary,
		"elapsed_us": Time.get_ticks_usec() - int(watch.start_us),
		"since_last_mix_s": AudioServer.get_time_since_last_mix(),
		"to_next_mix_s": AudioServer.get_time_to_next_mix(),
		"output_latency_s": AudioServer.get_output_latency(),
		"shoot_cached": ResourceLoader.has_cached("res://assets/audio/shoot.ogg"),
		"player": _audio_ref_snapshot(watch.player),
		"stream": _audio_ref_snapshot(watch.stream),
		"latest_playback": _audio_ref_snapshot(watch.playback)}
	print("OUTLAW_AUDIO_DIAGNOSTIC " + JSON.stringify(snapshot))

func run() -> void:
	original_services = root.get_node_or_null("Services")
	if is_instance_valid(original_services): original_services.name = "ServicesLifecycleTestOriginal"
	sdk = NoPersistenceServices.new()
	# Lazy load after PGS autoload registration; never add real Services to tree.
	sdk.logic = load("res://platform/services.gd").new()
	sdk.logic.availability_changed.connect(func(): sdk.availability_changed.emit())
	sdk.name = "Services"
	root.add_child(sdk)
	sdk.set_process(false)
	game = load("res://main.tscn").instantiate()
	game.smoke = true
	game.set_process(false)
	root.add_child(game)
	game.set_process(false)
	# Synthetic lifecycle callbacks are not auditory or native SDK acceptance.
	# Smoke combat can play effects; teardown drains owned players before removal.
	game.music.stop()
	game.music.stream = null
	game.frame_count = 10
	await process_frame
	check(game.service == sdk, "no-persistence stub installed before game ready")
	for flags in [[false, false], [true, false], [false, true], [true, true]]:
		sdk._reward_showing = flags[0]
		sdk._interstitial_showing = flags[1]
		check(sdk.fullscreen_ad_active() == (flags[0] or flags[1]), "real Services accessor OR truth table " + str(flags))

	fresh_lost()
	game._request_revive()
	game._request_revive()
	check(sdk.requests == 1 and game.reward_pending and sdk.fullscreen_ad_active(), "one pending fullscreen continue request")
	var requested_battle = game.battle
	sdk.earn()
	check(game.battle == requested_battle and game.screen == "play" and game.battle.revived and game.battle.invincible == 3.0, "earned callback revives the same battle once before close")
	var frozen := fingerprint()
	game.joystick_active = true
	game.joystick_index = 7
	game.dash_request = true
	game.fire_held = true
	game.fire_request = true
	game.reload_request = true
	for frame in range(90): game._process(1.0)
	check(fingerprint() == frozen, "ninety covered seconds preserve all combat state and revive protection")
	check(not game.joystick_active and game.joystick_index == -1 and not game.dash_request, "coverage clears queued joystick and dash")
	check(not game.fire_held and not game.fire_request and not game.reload_request,"coverage clears held/queued gun and reload input")
	game.fire_button.button_down.emit()
	game.reload_button.pressed.emit()
	check(not game.fire_held and not game.reload_request and fingerprint()==frozen,"covered gun/reload buttons cannot shoot, reload or consume ammo")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	game._unhandled_input(space)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.index = 9
	touch.position = Vector2(120, 850)
	game._unhandled_input(touch)
	game.dash_button.pressed.emit()
	check(not game.dash_request and not game.joystick_active, "covered SPACE touch and GUI DASH cannot queue arena input")
	game._back()
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	game._unhandled_input(escape)
	game._pause()
	check(game.screen == "play" and game.battle == requested_battle and not game.paused and not game.result_recorded, "covered direct ESC WM Back and pause preserve the run")
	sdk.earn()
	check(fingerprint() == frozen, "duplicate earned callback cannot grant or reset protection again")
	Input.action_press("ui_right")
	sdk.close()
	game._process(80.0)
	check(fingerprint() == frozen, "first uncovered large delta is discarded without even a zero-delta combat step")
	check(game._movement() == Vector2.ZERO, "keyboard action held across coverage remains suppressed")
	Input.action_release("ui_right")
	game._movement()
	Input.action_press("ui_right")
	check(game._movement().x > 0.0, "fresh movement works after keyboard returns neutral")
	Input.action_release("ui_right")
	var elapsed: float = game.battle.elapsed
	game._process(0.02)
	check(game.battle.elapsed > elapsed and game.battle.invincible < 3.0, "ordinary subsequent frame resumes combat and protection countdown")

	game.paused = true
	sdk._interstitial_showing = true
	frozen = fingerprint()
	game._process(20.0)
	sdk._interstitial_showing = false
	game._process(20.0)
	check(game.paused and fingerprint() == frozen, "preexisting user pause survives interstitial and dismissal")
	game._back()
	game._process(0.02)
	check(not game.paused and fingerprint() != frozen, "ordinary user unpause remains functional")

	sdk._interstitial_showing = true
	frozen = fingerprint()
	game._process(12.0)
	check(fingerprint() == frozen, "interstitial alone freezes combat")
	game._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	sdk._interstitial_showing = false
	game._process(20.0)
	check(game.application_suspended and fingerprint() == frozen, "ad closure cannot release an overlapping application suspension")
	game._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	game._process(70.0)
	check(fingerprint() == frozen, "resume discards covered delta after overlapping blockers")
	game._process(0.02)
	check(fingerprint() != frozen, "combat resumes after all blockers clear")

	game._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	frozen = fingerprint()
	game._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(game.paused and not game.application_suspended, "normal backgrounding retains the existing pause-overlay policy")
	game._back()
	game._process(100.0)
	check(fingerprint() == frozen, "PAUSED and RESUMED between process calls still discard the return frame")

	fresh_lost(2)
	game._request_revive()
	sdk.close()
	sdk.close()
	sdk.earn()
	check(game.battle.result == "lost" and not game.battle.revived and not game.reward_pending, "unearned dismissal failure and late earn do not revive")
	fresh_lost(2)
	game._request_revive()
	game._start_level(3, false)
	var replacement_battle = game.battle
	game.battle.result = "lost"
	game._show_result()
	sdk.earn()
	check(game.battle == replacement_battle and not game.battle.revived, "stale callback cannot revive a different run")
	sdk.close()
	game.service = null
	check(not game._external_gameplay_blocked(), "missing service preserves ordinary local gameplay")
	game.service = sdk
	check(sdk.persistence_calls == 0, "stub never persisted platform progress")
	print("OUTLAW_FULLSCREEN_USER_DIR " + ProjectSettings.globalize_path("user://"))
	var report := {"scope": "PRIVATE SYNTHETIC HEADLESS REGRESSION; no native ad acceptance claim", "checks": checks, "failures": failures, "labels": labels, "user_dir": ProjectSettings.globalize_path("user://")}
	var path := ProjectSettings.globalize_path("res://").path_join("../evidence/focused-result.json").simplify_path()
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify(report, "\t")); output.close()
	requested_battle = null
	replacement_battle = null
	var audio_watch := _audio_watch()
	_audio_diagnostic("before_shutdown", audio_watch)
	await game.shutdown_audio()
	_audio_diagnostic("after_shutdown", audio_watch)
	game.queue_free()
	await process_frame
	game = null
	_audio_diagnostic("after_game_free", audio_watch)
	root.remove_child(sdk)
	sdk.logic.free()
	sdk.free()
	sdk = null
	if is_instance_valid(original_services): original_services.name = "Services"
	await process_frame
	await process_frame
	_audio_diagnostic("before_quit", audio_watch)
	audio_watch.clear()
	print("OUTLAW_FULLSCREEN_CHECKS checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
