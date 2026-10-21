extends Node2D

const Model = preload("res://game/state.gd")
const Combat = preload("res://game/combat.gd")
const W = 540.0
const H = 960.0
const CREAM = Color("f5e8c9")
const INK = Color("3d2d49")
const TEAL = Color("287f7d")
const GOLD = Color("e8b86c")
const LILAC = Color("a28bc4")
const SAVE = "user://outlaw_save_v1.json"
var state = Model.new()
var battle = null
var campaign: Array = []
var catalog: Dictionary = {}
var ui: Control
var menu_scroll: ScrollContainer
var service: Node
var screen: String = "home"
var chapter: int = 0
var selected_level: int = 1
var last_result: Dictionary = {}
var result_recorded: bool = false
var reward_pending: bool = false
var textures: Dictionary = {}
var players: Array[Texture2D] = []
var enemy_art: Array[Texture2D] = []
var weapon: Texture2D
var sounds: Dictionary = {}
var music: AudioStreamPlayer
var hud_health: ProgressBar
var hud_goal: Label
var hud_time: Label
var dash_button: Button
var reward_button: Button
var toast: Label
var toast_time: float = 0.0
var joystick_active: bool = false
var joystick_index: int = -1
var joystick_origin: Vector2 = Vector2(90, 850)
var joystick_point: Vector2 = Vector2(90, 850)
var dash_request: bool = false
var paused: bool = false
var application_suspended: bool = false
var _discard_next_combat_delta: bool = false
var _waiting_for_neutral_movement: bool = false
var total_time: float = 0.0
var save_clock: float = 0.0
var frame_count: int = 0
var capture_screen: String = ""
var capture_path: String = ""
var capture_level: int = 10
var capture_done: bool = false
var smoke: bool = false
var _audio_shutting_down: bool = false
var _audio_drained: bool = false
var _quit_pending: bool = false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	for arg in OS.get_cmdline_user_args():
		if arg == "--smoke-test": smoke = true
		if arg.begins_with("--capture="): capture_screen = arg.trim_prefix("--capture=")
		if arg.begins_with("--capture-path="): capture_path = arg.trim_prefix("--capture-path=")
		if arg.begins_with("--capture-level="): capture_level = clampi(arg.trim_prefix("--capture-level=").to_int(), 1, 100)
	if not smoke and capture_screen.is_empty():
		_load()
	state.roll_day(_today())
	campaign = JSON.parse_string(FileAccess.get_file_as_string("res://game/campaign.json"))
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://game/catalog.json"))
	for file in [55, 59, 60, 61, 62, 63, 64, 65, 68, 77, 80, 81, 82, 83, 84, 87, 105, 122, 155, 172, 173, 174, 175, 176, 192, 193, 202, 203, 217, 218, 220, 222, 225, 226, 227, 228]:
		textures[file] = load("res://assets/tiles/tile_%04d.png" % file)
	for i in range(16):
		players.append(load("res://assets/players/tile_%04d.png" % i))
		enemy_art.append(load("res://assets/enemies/tile_%04d.png" % i))
	weapon = load("res://assets/weapon.png")
	for key in ["shoot", "hurt", "coin", "win", "lose", "click"]:
		var player = AudioStreamPlayer.new()
		player.stream = load("res://assets/audio/" + key + ".ogg")
		player.volume_db = -19 if key == "shoot" else -12
		add_child(player)
		sounds[key] = player
	music = AudioStreamPlayer.new()
	music.stream = load("res://assets/audio/trail_theme.wav")
	music.volume_db = -25
	add_child(music)
	music.finished.connect(_restart_music)
	if state.settings.music:
		music.play()
	service = get_node_or_null("/root/Services")
	if is_instance_valid(service) and service.has_signal("menu_bottom_reserve_changed"):
		service.connect("menu_bottom_reserve_changed", _apply_banner_layout)
	get_viewport().size_changed.connect(_apply_banner_layout)
	if service != null and service.has_signal("availability_changed"):
		service.availability_changed.connect(_refresh_reward_button)
	_build_theme()
	_show_home()
	if not capture_screen.is_empty():
		match capture_screen:
			"play": _start_level(capture_level, false)
			"map": chapter = 0; _show_map()
			"workshop": _show_workshop()
			"rewards": _show_rewards()
			"records": _show_records()
			"brief": _show_brief(capture_level)
			_: _show_home()
	_sync_progress()

func _build_theme() -> void:
	var theme = Theme.new()
	theme.default_font_size = 20
	for type_name in ["Label", "Button", "CheckButton"]:
		theme.set_color("font_color", type_name, INK)
	theme.set_color("font_color", "Button", CREAM)
	theme.set_color("font_disabled_color", "Button", INK)
	for key in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style = StyleBoxFlat.new()
		style.bg_color = TEAL
		if key == "hover": style.bg_color = Color("3e9b91")
		if key == "pressed": style.bg_color = Color("216566")
		if key == "disabled": style.bg_color = Color("a89c91")
		style.corner_radius_top_left = 12
		style.corner_radius_top_right = 12
		style.corner_radius_bottom_left = 12
		style.corner_radius_bottom_right = 12
		style.border_color = Color("493850")
		style.set_border_width_all(2)
		style.content_margin_left = 12
		style.content_margin_right = 12
		theme.set_stylebox(key, "Button", style)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = theme
	var layer = CanvasLayer.new()
	add_child(layer)
	menu_scroll = ScrollContainer.new()
	menu_scroll.size = Vector2(540, 960)
	menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_scroll.follow_focus = true
	menu_scroll.get_v_scroll_bar().value_changed.connect(func(_value: float): queue_redraw())
	layer.add_child(menu_scroll)
	ui.custom_minimum_size = Vector2(540, 960)
	menu_scroll.add_child(ui)

func _apply_banner_layout(reserve_override: float = -1.0) -> void:
	if not is_instance_valid(menu_scroll): return
	var reserve := reserve_override
	if reserve < 0.0:
		reserve = float(service.call("menu_bottom_reserve", self)) if is_instance_valid(service) and service.has_method("menu_bottom_reserve") else 0.0
	if screen == "play": reserve = 0.0
	reserve = clampf(reserve, 0.0, 400.0)
	menu_scroll.size = Vector2(540.0, 960.0 - reserve)
	menu_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if reserve > 0.0 else ScrollContainer.SCROLL_MODE_SHOW_NEVER
	menu_scroll.mouse_filter = Control.MOUSE_FILTER_PASS if reserve > 0.0 else Control.MOUSE_FILTER_IGNORE
	if reserve <= 0.0: menu_scroll.scroll_vertical = 0
	queue_redraw()

func _menu_draw_offset() -> Vector2:
	return Vector2(0, -float(menu_scroll.scroll_vertical)) if is_instance_valid(menu_scroll) else Vector2.ZERO


func _clear(next: String) -> void:
	screen = next
	for child in ui.get_children():
		child.queue_free()
	hud_health = null
	reward_button = null
	toast = null
	_clear_arena_input()
	paused = false
	if _external_gameplay_blocked(): _hold_external_gameplay()
	if service != null:
		service.set_menu_visible(next != "play")
	menu_scroll.scroll_vertical = 0
	_apply_banner_layout()
	queue_redraw()

func _label(text: String, point: Vector2, size: Vector2, font_size: int = 20, color: Color = INK, centered: bool = false) -> Label:
	var label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.text = text
	label.position = point
	label.size = size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if centered: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(label)
	return label

func _button(text: String, point: Vector2, size: Vector2, action: Callable, disabled: bool = false) -> Button:
	var button = Button.new()
	button.mouse_filter = Control.MOUSE_FILTER_PASS if screen != "play" else Control.MOUSE_FILTER_STOP
	button.text = text
	button.position = point
	button.size = size
	button.disabled = disabled
	button.pressed.connect(func():
		if _external_gameplay_blocked():
			_hold_external_gameplay()
			return
		_sound("click")
		action.call())
	ui.add_child(button)
	return button

func _card(rect: Rect2, color: Color = Color("f5e8c9")) -> Panel:
	var panel = Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(16)
	box.border_color = Color("6e5874")
	box.set_border_width_all(2)
	box.shadow_color = Color(0.16, 0.1, 0.2, 0.14)
	box.shadow_size = 5
	panel.add_theme_stylebox_override("panel", box)
	ui.add_child(panel)
	return panel

func _header(title: String, back_action: Callable) -> void:
	_label(title, Vector2(28, 30), Vector2(370, 44), 30)
	_label("LEVEL %d   •   %d COINS   •   %d / 100 TRAILS" % [state.player_level(), state.coins, state.completed.size()], Vector2(30, 82), Vector2(480, 30), 15)
	_button("Back", Vector2(421, 28), Vector2(91, 48), back_action)
	_footer()

func _footer() -> void:
	_label("Progress is saved on this device", Vector2(30, 872), Vector2(480, 25), 15, INK, true)

func _show_home() -> void:
	_clear("home")
	_label("A LITTLE COURAGE. A LONG WAY WEST.", Vector2(25, 34), Vector2(490, 26), 15, CREAM, true)
	_label("THE FINAL\nOUTLAW", Vector2(30, 73), Vector2(480, 128), 49, CREAM, true)
	_label("100 trails to a quieter frontier", Vector2(35, 365), Vector2(470, 35), 20, CREAM, true)
	_button("Ride the campaign", Vector2(42, 426), Vector2(456, 62), _show_map)
	_button("Endless badlands", Vector2(42, 503), Vector2(456, 56), func(): _show_brief(0))
	_button("Workshop", Vector2(42, 576), Vector2(220, 54), _show_workshop)
	_button("Daily camp", Vector2(278, 576), Vector2(220, 54), _show_rewards)
	_button("Trail journal", Vector2(42, 646), Vector2(220, 54), _show_records)
	_button("Options", Vector2(278, 646), Vector2(220, 54), _show_options)
	_label("LEVEL %d   •   %d COINS   •   %d STARS" % [state.player_level(), state.coins, state.stars_total()], Vector2(30, 733), Vector2(480, 32), 18, CREAM, true)
	_label("Drag to move. Aim is automatic.\nDash through danger, and bring the frontier home.", Vector2(40, 790), Vector2(460, 57), 18, CREAM, true)
	_label("Offline play • Optional online features on Android", Vector2(20, 872), Vector2(500, 27), 14, CREAM, true)

func _show_map() -> void:
	_clear("map")
	_header("The western trail", _show_home)
	var definition: Dictionary = campaign[chapter * 10]
	_label("CHAPTER %d / 10" % (chapter + 1), Vector2(104, 137), Vector2(332, 28), 16, TEAL, true)
	_label(str(definition.chapter_name), Vector2(80, 171), Vector2(380, 39), 28, INK, true)
	_button("‹", Vector2(28, 145), Vector2(56, 56), func(): chapter = maxi(0, chapter - 1); _show_map(), chapter == 0)
	_button("›", Vector2(456, 145), Vector2(56, 56), func(): chapter = mini(9, chapter + 1); _show_map(), chapter == 9)
	for i in range(10):
		var number: int = chapter * 10 + i + 1
		var point: Vector2 = _map_point(i)
		var stars: int = int(state.completed.get(str(number), 0))
		var text: String = "%02d\n%s" % [number, "★".repeat(stars) + "☆".repeat(3 - stars)]
		var btn = _button(text, point - Vector2(41, 24), Vector2(82, 52), func(): _show_brief(number), not state.open_level(number))
		btn.add_theme_font_size_override("font_size", 16)
	_label("Follow the lights. Every trail has its own challenge.", Vector2(35, 814), Vector2(470, 42), 17, INK, true)

func _map_point(index: int) -> Vector2:
	var xs: Array = [105, 262, 427, 360, 201, 92, 211, 378, 428, 268]
	return Vector2(float(xs[index]), 258.0 + float(index) * 56.0)

func _show_brief(number: int) -> void:
	selected_level = number
	_clear("brief")
	_header("Before you ride", _show_map if number > 0 else _show_home)
	var definition: Dictionary = _definition(number)
	_card(Rect2(28, 157, 484, 537))
	_label("TRAIL %03d" % number if number > 0 else "ENDLESS CHALLENGE", Vector2(49, 180), Vector2(442, 29), 16, TEAL)
	_label(str(definition.name), Vector2(49, 225), Vector2(442, 83), 31)
	_label(str(definition.description), Vector2(49, 326), Vector2(442, 105), 21)
	_label("YOUR CHALLENGE", Vector2(49, 453), Vector2(442, 28), 15, TEAL)
	_label(str(definition.objective), Vector2(49, 491), Vector2(442, 62), 24)
	_label("Tip: " + str(definition.tip), Vector2(49, 581), Vector2(442, 85), 18)
	_button("Ride out", Vector2(42, 725), Vector2(456, 61), func(): _start_level(number, number == 0))
	_label("Drag anywhere to steer • Automatic aim • Tap DASH to evade", Vector2(34, 808), Vector2(472, 44), 16, INK, true)

func _definition(number: int) -> Dictionary:
	if number > 0:
		return campaign[clampi(number - 1, 0, 99)]
	return {"id": 0, "chapter": 10, "chapter_name": "The endless badlands", "name": "One more sunset", "description": "A fresh frontier every time. The longer you last, the faster the badlands answer.", "objective": "Survive and build your highest score", "tip": "Keep moving, collect power-ups, and watch the outer lanes.", "mode": "survive", "target": 100000, "time_limit": 100000, "difficulty": 2.0, "spawn": 1.45, "enemies": ["drifter", "runner", "gunner", "tank", "sniper"], "hazard": "sandburst", "layout": 42, "palette": 7, "rule": "steady"}

func _show_workshop() -> void:
	_clear("workshop")
	_header("The workshop", _show_home)
	_label("A little better prepared", Vector2(36, 137), Vector2(468, 36), 24)
	var names: Dictionary = {"power": "Polished revolver", "heart": "Reinforced vest", "boots": "Trail-worn boots"}
	var desc: Dictionary = {"power": "+1 damage per shot", "heart": "+12 maximum health", "boots": "+8 movement speed"}
	var index: int = 0
	for key in ["power", "heart", "boots"]:
		var y: float = 198 + index * 179
		_card(Rect2(28, y, 484, 155))
		_label(names[key], Vector2(47, y + 16), Vector2(310, 34), 24)
		_label("LEVEL %d / 8   •   %s" % [int(state.upgrades[key]), desc[key]], Vector2(47, y + 62), Vector2(442, 32), 16)
		var cost: int = state.upgrade_cost(key)
		_button("Upgrade · %d" % cost if cost >= 0 else "Masterwork", Vector2(282, y + 102), Vector2(207, 42), func():
			if state.buy_upgrade(key):
				_save(); _sync_progress(); _sound("coin"); _show_workshop(), cost < 0 or state.coins < cost)
		index += 1
	_label("Earn coins on the trail. No purchase is required.", Vector2(38, 771), Vector2(464, 48), 19, INK, true)
	_label("PLAYER LEVEL %d   •   %d XP" % [state.player_level(), state.xp], Vector2(40, 824), Vector2(460, 32), 18, TEAL, true)

func _show_rewards() -> void:
	state.roll_day(_today())
	_clear("rewards")
	_header("The daily camp", _show_home)
	_card(Rect2(28, 146, 484, 179))
	_label("Seven sunrise gifts", Vector2(47, 165), Vector2(440, 37), 25)
	_label("Day %d of 7 • gifts grow through the week" % (state.streak if state.login_day == _today() else state.streak % 7 + 1), Vector2(47, 214), Vector2(440, 30), 18)
	_button("Collect today's gift" if state.can_claim_login(_today()) else "Gift collected", Vector2(47, 263), Vector2(440, 45), func():
		var amount: int = state.claim_login(_today())
		_save(); _sync_progress(); _show_rewards(); _show_toast("%d coins, with a little sunrise XP" % amount), not state.can_claim_login(_today()))
	var names: Dictionary = {"kills": "Clear the dust", "wins": "Two good deeds", "seconds": "Stay a little longer"}
	var index: int = 0
	for key in ["kills", "wins", "seconds"]:
		var y: float = 350 + index * 120
		_card(Rect2(28, y, 484, 104))
		_label(names[key], Vector2(47, y + 12), Vector2(290, 29), 22)
		_label("%d / %d %s" % [mini(int(state.daily[key]), int(Model.DAILY_TARGETS[key])), int(Model.DAILY_TARGETS[key]), key], Vector2(47, y + 53), Vector2(250, 28), 17)
		var available: bool = int(state.daily[key]) >= int(Model.DAILY_TARGETS[key]) and not state.daily_claimed.has(key)
		_button("Claim 80" if not state.daily_claimed.has(key) else "Done", Vector2(358, y + 31), Vector2(130, 47), func(): state.claim_quest(key); _save(); _sync_progress(); _show_rewards(), not available)
		index += 1
	reward_button = _button("Watch a rewarded ad · 120 coins", Vector2(42, 747), Vector2(456, 55), _request_crate)
	_refresh_reward_button()
	_label("Daily gifts reset at midnight UTC.\nMiss a day and your sunrise streak begins again.", Vector2(38, 821), Vector2(464, 45), 15, INK, true)

func _request_crate() -> void:
	if reward_pending or service == null or not service.can_reward() or state.rewarded_day == _today():
		return
	reward_pending = true
	_refresh_reward_button()
	service.reward_requested("camp supply crate", func(earned: bool):
		reward_pending = false
		if earned and state.reward_crate(_today()):
			_save(); _sound("coin")
			if screen == "rewards": _show_rewards()
			_show_toast("Supply crate: 120 coins")
		elif screen == "rewards":
			_show_toast("No reward was earned. Your camp is still here.")
		_refresh_reward_button())

func _show_records() -> void:
	_clear("records")
	_header("Trail journal", _show_home)
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(27, 143)
	scroll.size = Vector2(486, 650)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.add_child(scroll)
	var list = VBoxContainer.new()
	list.custom_minimum_size.x = 462
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var metrics: Dictionary = state.metrics()
	for achievement in catalog.get("achievements", []):
		var card = PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		var box = StyleBoxFlat.new()
		box.bg_color = Color("d8e6c7") if state.unlocked.has(str(achievement.key)) else CREAM
		box.set_corner_radius_all(12)
		box.content_margin_left = 15
		box.content_margin_right = 15
		box.content_margin_top = 12
		box.content_margin_bottom = 12
		card.add_theme_stylebox_override("panel", box)
		var label = Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 420
		label.add_theme_font_size_override("font_size", 18)
		label.text = ("★ " if state.unlocked.has(str(achievement.key)) else "☆ ") + str(achievement.name) + "\n" + str(achievement.description) + "\n%d / %d" % [mini(int(metrics.get(str(achievement.metric), 0)), int(achievement.threshold)), int(achievement.threshold)]
		card.add_child(label)
		list.add_child(card)
	_button("Online achievements", Vector2(28, 813), Vector2(235, 48), func(): _online("achievements"))
	_button("Leaderboards", Vector2(277, 813), Vector2(235, 48), _show_boards)

func _show_boards() -> void:
	_clear("boards")
	_header("The frontier records", _show_records)
	var metrics: Dictionary = state.metrics()
	var i: int = 0
	for board in catalog.get("leaderboards", []):
		var y: float = 161 + i * 132
		_card(Rect2(28, y, 484, 112))
		_label(str(board.name), Vector2(47, y + 14), Vector2(420, 31), 23)
		_label("Your record: %d" % int(metrics.get(str(board.metric), 0)), Vector2(47, y + 60), Vector2(250, 30), 18)
		_button("Online", Vector2(366, y + 54), Vector2(121, 44), func():
			if service != null: service.open_leaderboards(str(board.key))
			_show_toast("Online records require Play Games on Android."))
		i += 1

func _show_options() -> void:
	_clear("options")
	_header("A quieter camp", _show_home)
	_card(Rect2(28, 155, 484, 446))
	_label("HOW TO RIDE", Vector2(48, 179), Vector2(440, 34), 17, TEAL)
	_label("Drag your thumb anywhere in the field to move. Your revolver aims at the nearest foe. Tap DASH to slip through a tight spot.\n\nKeyboard: WASD / arrows. SPACE dashes. ESC pauses.\n\nCollect hearts, shields, rapid-fire and fan-shot badges. Amber rings warn before a hazard strikes.", Vector2(48, 228), Vector2(440, 270), 20)
	_button("Sound: " + ("ON" if state.settings.sound else "OFF"), Vector2(48, 523), Vector2(213, 52), func(): state.settings.sound = not state.settings.sound; _save(); _show_options())
	_button("Music: " + ("ON" if state.settings.music else "OFF"), Vector2(279, 523), Vector2(213, 52), func():
		state.settings.music = not state.settings.music
		if state.settings.music: music.play()
		else: music.stop()
		_save(); _show_options())
	_button("Connect Play Games", Vector2(42, 633), Vector2(456, 53), func(): _online("sign_in"))
	_button("Advertising privacy options", Vector2(42, 702), Vector2(456, 53), func():
		if service != null: service.privacy_options()
		_show_toast("Advertising options are provided in the Android app."))
	_label("Your save is local to this device.\nOnline services are optional; the whole campaign works offline.", Vector2(43, 790), Vector2(454, 62), 17, INK, true)

func _online(kind: String) -> void:
	if service != null:
		if kind == "sign_in": service.sign_in()
		else: service.open_achievements()
	_show_toast("Online features use Play Games in the Android app.")

func _start_level(number: int, endless: bool) -> void:
	selected_level = number
	battle = Combat.new()
	battle.start(_definition(number), state.stats(), 4701 + number * 79 + state.runs * 17, endless)
	result_recorded = false
	last_result.clear()
	_clear("play")
	_build_hud()

func _build_hud() -> void:
	_label("TRAIL %03d" % selected_level if selected_level > 0 else "ENDLESS BADLANDS", Vector2(23, 20), Vector2(382, 27), 16, CREAM)
	hud_goal = _label("", Vector2(23, 55), Vector2(410, 37), 21, CREAM)
	_button("Ⅱ", Vector2(454, 23), Vector2(63, 51), _pause)
	hud_health = ProgressBar.new()
	hud_health.position = Vector2(23, 103)
	hud_health.size = Vector2(365, 16)
	hud_health.max_value = battle.max_health
	hud_health.show_percentage = false
	var fill = StyleBoxFlat.new()
	fill.bg_color = Color("8bd0ad")
	fill.set_corner_radius_all(7)
	hud_health.add_theme_stylebox_override("fill", fill)
	ui.add_child(hud_health)
	hud_time = _label("0:00", Vector2(405, 96), Vector2(110, 30), 18, CREAM, true)
	_label("DRAG TO MOVE", Vector2(26, 902), Vector2(232, 25), 16, CREAM, true)
	_label("AUTO AIM", Vector2(276, 781), Vector2(238, 24), 16, CREAM, true)
	dash_button = _button("DASH", Vector2(358, 820), Vector2(145, 70), _request_dash)
	if selected_level <= 2 and selected_level > 0:
		_label(str(battle.level.tip), Vector2(42, 760), Vector2(291, 60), 17, CREAM, true)

func _pause() -> void:
	if _external_gameplay_blocked():
		_hold_external_gameplay()
		return
	if screen != "play": return
	paused = true
	joystick_active = false
	_card(Rect2(47, 300, 446, 357))
	_label("A moment by the fire", Vector2(65, 327), Vector2(410, 50), 29, INK, true)
	_button("Keep riding", Vector2(79, 408), Vector2(382, 58), func():
		_clear("play"); _build_hud())
	_button("Return to camp", Vector2(79, 488), Vector2(382, 58), func(): _record_result(false); battle = null; _show_home())
	_label("Your earned progress will be saved.", Vector2(79, 578), Vector2(382, 39), 17, INK, true)

func _record_result(won: bool) -> void:
	if result_recorded or battle == null:
		return
	state.roll_day(_today())
	last_result = state.record_run(selected_level, won, battle.kills, battle.elapsed, battle.health / battle.max_health, battle.score, battle.survival)
	result_recorded = true
	_sync_progress()
	_save()
	if service != null and not battle.result.is_empty():
		service.round_finished()

func _show_result() -> void:
	var won: bool = battle.result == "win"
	_clear("results")
	_label("TRAIL COMPLETE" if won else "THE SUN WILL RISE AGAIN", Vector2(29, 73), Vector2(482, 35), 18, CREAM, true)
	_label("A good day's ride" if won else "Dust yourself off", Vector2(27, 135), Vector2(486, 60), 38, CREAM, true)
	_card(Rect2(37, 246, 466, 258))
	_label("%d FOES   •   %d:%02d ON THE TRAIL" % [battle.kills, int(battle.elapsed) / 60, int(battle.elapsed) % 60], Vector2(55, 275), Vector2(430, 32), 19, INK, true)
	if result_recorded:
		_label("+%d COINS     +%d XP" % [int(last_result.get("coins", 0)), int(last_result.get("xp", 0))], Vector2(55, 337), Vector2(430, 35), 28, TEAL, true)
		_label("★".repeat(int(last_result.get("stars", 0))) if won else "Every trail teaches something.", Vector2(55, 406), Vector2(430, 52), 34 if won else 22, INK, true)
	else:
		_label("Choose a fresh start or an optional rewarded continue.\nYour run is saved when you finish.", Vector2(62, 345), Vector2(416, 105), 22, INK, true)
	if not won and not battle.revived:
		reward_button = _button("Rewarded continue · restore health", Vector2(42, 546), Vector2(456, 58), _request_revive)
		_refresh_reward_button()
		_label("Optional ad • unavailable offline/Web", Vector2(42, 611), Vector2(456, 27), 15, CREAM, true)
	_button("Next trail" if won and selected_level < 100 else "Ride again", Vector2(42, 666), Vector2(456, 61), func():
		if not result_recorded: _record_result(false)
		_start_level(selected_level + 1 if won and selected_level > 0 and selected_level < 100 else selected_level, battle.survival))
	_button("Return to camp", Vector2(42, 749), Vector2(456, 56), func():
		if not result_recorded: _record_result(false)
		battle = null; _show_home())
	_label("LEVEL %d   •   %d COINS" % [state.player_level(), state.coins], Vector2(30, 853), Vector2(480, 32), 18, CREAM, true)

func _request_revive() -> void:
	if reward_pending or service == null or not service.can_reward() or battle == null or battle.revived or result_recorded:
		return
	var requested_battle = battle
	reward_pending = true
	_refresh_reward_button()
	service.reward_requested("one frontier continue", func(earned: bool):
		reward_pending = false
		if earned and battle == requested_battle and screen == "results" and not result_recorded and battle.revive():
			_clear("play"); _build_hud()
		else:
			_show_toast("No continue was earned. A fresh ride is always free.")
		_refresh_reward_button())

func _refresh_reward_button() -> void:
	if not is_instance_valid(reward_button): return
	var ready: bool = not reward_pending and service != null and service.can_reward()
	if screen == "rewards": ready = ready and state.rewarded_day != _today()
	if screen == "results": ready = ready and not result_recorded
	reward_button.disabled = not ready

func _process(delta: float) -> void:
	if _quit_pending: return
	var covered := _external_gameplay_blocked()
	var discard_delta := _discard_next_combat_delta
	if covered:
		_hold_external_gameplay()
	elif discard_delta:
		_discard_next_combat_delta = false
		_clear_arena_input()
	frame_count += 1
	total_time += delta
	toast_time -= delta
	if is_instance_valid(toast): toast.visible = toast_time > 0
	if smoke and frame_count == 5:
		_start_level(1, false)
	if screen == "play" and not paused and battle != null and not covered and not discard_delta:
		var movement: Vector2 = _movement()
		if smoke or not capture_screen.is_empty():
			movement = Vector2(cos(total_time), sin(total_time)) * 0.45
		battle.step(1.0 / 60.0 if smoke else delta, movement, dash_request)
		dash_request = false
		for event in battle.events:
			match str(event.kind):
				"shot": _sound("shoot")
				"hurt": _sound("hurt")
				"defeat", "pickup": _sound("coin")
		if is_instance_valid(hud_health):
			hud_health.value = battle.health
			hud_goal.text = "SCORE %d" % battle.score if battle.survival else battle.progress_text()
			hud_time.text = "%d:%02d" % [int(battle.elapsed) / 60, int(battle.elapsed) % 60]
			dash_button.text = "DASH" if battle.dash_cooldown <= 0 else "%.1f" % battle.dash_cooldown
			dash_button.disabled = battle.dash_cooldown > 0
		if not battle.result.is_empty():
			if battle.result == "win":
				_record_result(true); _sound("win")
			else:
				_sound("lose")
				if battle.revived or service == null or not service.can_reward(): _record_result(false)
			_show_result()
	save_clock += delta
	if save_clock > 20.0:
		save_clock = 0.0
		_save()
	if smoke and frame_count >= 360:
		print("OUTLAW_RUNTIME_PASS frames=%d" % frame_count)
		_quit_cleanly(0)
	if not capture_screen.is_empty() and not capture_done and frame_count > (210 if capture_screen == "play" else 30):
		capture_done = true
		_capture()
	queue_redraw()

func _external_gameplay_blocked() -> bool:
	return application_suspended or (is_instance_valid(service) and service.has_method("fullscreen_ad_active") and bool(service.fullscreen_ad_active()))

func _clear_arena_input() -> void:
	joystick_active = false
	joystick_index = -1
	joystick_point = joystick_origin
	dash_request = false

func _hold_external_gameplay() -> void:
	_clear_arena_input()
	_waiting_for_neutral_movement = true
	_discard_next_combat_delta = true

func _request_dash() -> void:
	if _external_gameplay_blocked():
		_hold_external_gameplay()
		return
	if screen == "play" and not paused:
		dash_request = true

func _movement() -> Vector2:
	var move: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	move.x += float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	move.y += float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	if _waiting_for_neutral_movement:
		var keys_held := Input.is_action_pressed("ui_left") or Input.is_action_pressed("ui_right") or Input.is_action_pressed("ui_up") or Input.is_action_pressed("ui_down") or Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_S)
		if not keys_held: _waiting_for_neutral_movement = false
		move = Vector2.ZERO
	if joystick_active:
		move = (joystick_point - joystick_origin) / 62.0
	return move.limit_length(1.0)

func _unhandled_input(event: InputEvent) -> void:
	if _external_gameplay_blocked():
		_hold_external_gameplay()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_back(); get_viewport().set_input_as_handled()
		if event.keycode == KEY_SPACE: _request_dash()
	if screen != "play" or paused: return
	if event is InputEventScreenTouch:
		if event.pressed and not joystick_active:
			joystick_active = true; joystick_index = event.index; joystick_origin = event.position; joystick_point = event.position
		elif not event.pressed and event.index == joystick_index:
			joystick_active = false
	if event is InputEventScreenDrag and event.index == joystick_index: joystick_point = event.position
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		joystick_active = event.pressed
		joystick_origin = event.position
		joystick_point = event.position
	if event is InputEventMouseMotion and joystick_active: joystick_point = event.position

func _back() -> void:
	if _external_gameplay_blocked():
		_hold_external_gameplay()
		return
	if screen == "play":
		if paused: _clear("play"); _build_hud()
		else: _pause()
	elif screen == "results":
		if not result_recorded: _record_result(false)
		battle = null; _show_home()
	else:
		_show_home()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if battle != null and not result_recorded: _record_result(false)
		_save(); _quit_cleanly(0)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_save()
		if screen == "play" and not paused: _pause()
		application_suspended = true
		_hold_external_gameplay()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		application_suspended = false
		_hold_external_gameplay()

func _draw() -> void:
	var dark: bool = screen in ["home", "play", "results"]
	draw_rect(Rect2(0, 0, W, H), INK if dark else Color("decdad"))
	draw_set_transform(_menu_draw_offset() if screen != "play" else Vector2.ZERO)
	if screen == "play" and battle != null:
		_draw_arena()
	elif screen == "map":
		for i in range(9):
			draw_line(_map_point(i), _map_point(i + 1), Color("a38b78"), 12, true)
			draw_line(_map_point(i), _map_point(i + 1), GOLD, 5, true)
		draw_circle(Vector2(66, 457), 39, Color("c4b29e"))
		_tex(63, Rect2(33, 418, 64, 64))
		_tex(62, Rect2(448, 620, 64, 64))
	elif screen == "home":
		draw_circle(Vector2(270, 285), 106, Color("74608c"))
		draw_circle(Vector2(270, 285), 89, Color("c59b80"))
		for i in range(18):
			var x: float = fmod(float(i * 79), 520) + 10
			var y: float = fmod(float(i * 131), 890) + 20
			draw_circle(Vector2(x, y), 1.6, Color("ae88a0"))
		_tex(63, Rect2(57, 261, 64, 64))
		_tex(80, Rect2(418, 242, 64, 64))
		if not players.is_empty():
			draw_texture_rect(players[0], Rect2(222, 227, 96, 96), false)
			draw_texture_rect(weapon, Rect2(294, 276, 48, 48), false)
	elif screen == "results":
		for i in range(24):
			draw_circle(Vector2(fmod(i * 97.0, 540), fmod(i * 149.0, 960)), 2, Color("967c9f"))

	draw_set_transform(Vector2.ZERO)

func _draw_arena() -> void:
	var rect: Rect2 = Combat.ARENA
	var palette: int = int(battle.level.get("palette", 0))
	var tint: Color = [Color("f0c99f"), Color("d2c4a6"), Color("d8a980"), Color("c4b1a1"), Color("bdabd0"), Color("d9bca4"), Color("b4b8c7"), Color("9d9ab6"), Color("b0c7bc"), Color("cfabb9")][palette % 10]
	draw_rect(rect.grow(4), Color("78617f"))
	draw_rect(rect, tint)
	for row in range(19):
		for col in range(16):
			var index: int = [64, 64, 64, 65, 64, 55][(row * 17 + col * 11 + int(battle.level.get("layout", 0))) % 6]
			_tex(index, Rect2(rect.position + Vector2(col * 31, row * 32), Vector2(32, 32)), Color(1, 1, 1, 0.32))
	for wall in battle.obstacles:
		draw_rect(Rect2(wall.position + Vector2(3, 5), wall.size), Color(0.2, 0.1, 0.2, 0.25))
		_tex(220 if int(wall.position.x) % 2 == 0 else 59, wall)
	if str(battle.level.mode) == "hold":
		var center: Vector2 = battle.hold_center()
		draw_circle(center, 66, Color(0.22, 0.6, 0.53, 0.22))
		draw_arc(center, 66, 0, TAU, 48, Color("2f8d80"), 4, true)
	if str(battle.level.get("hazard", "none")) != "none":
		var phase: float = fmod(battle.hazard_clock, 7.0)
		if phase >= 3.5 and phase <= 5.7:
			for point in battle.hazard_points():
				draw_circle(point, 43, Color(0.85, 0.35, 0.2, 0.45 if phase >= 5 else 0.12))
				draw_arc(point, 43, 0, TAU, 28, Color("e28d4e"), 3, true)
	for pickup in battle.pickups:
		var icon: int = {"heart": 222, "shield": 227, "rapid": 225, "spread": 226, "supply": 220}.get(str(pickup.kind), 220)
		var p: Vector2 = pickup.p
		draw_circle(p + Vector2(0, 9), 15, Color(0.2, 0.1, 0.2, 0.13))
		_tex(icon, Rect2(p - Vector2(18, 18 + sin(total_time * 4) * 2), Vector2(36, 36)))
	for enemy in battle.enemies:
		var point: Vector2 = enemy.p
		var size: float = 64.0 if str(enemy.kind) == "boss" else 42.0
		draw_circle(point + Vector2(0, size * 0.27), size * 0.26, Color(0.2, 0.1, 0.2, 0.17))
		var color: Color = Color(1.8, 1.4, 1.4) if float(enemy.flash) > 0 else Color.WHITE
		draw_texture_rect(enemy_art[int(Combat.TYPES[str(enemy.kind)].sprite)], Rect2(point - Vector2.ONE * size * 0.5, Vector2.ONE * size), false, color)
		if float(enemy.hp) < float(enemy.max_hp):
			draw_rect(Rect2(point + Vector2(-20, -size * 0.62), Vector2(40, 4)), INK)
			draw_rect(Rect2(point + Vector2(-20, -size * 0.62), Vector2(40 * float(enemy.hp) / float(enemy.max_hp), 4)), Color("edb26c"))
	var player: Vector2 = battle.player
	if battle.dash_time > 0:
		draw_line(player, player - battle.dash_direction * 55, Color(0.7, 0.85, 0.95, 0.5), 17, true)
	draw_circle(player + Vector2(0, 15), 17, Color(0.2, 0.1, 0.2, 0.2))
	if battle.shield_time > 0: draw_arc(player, 29, 0, TAU, 28, Color("8ad6d4"), 3, true)
	if battle.invincible <= 0 or fmod(total_time * 12, 1) > 0.35:
		draw_texture_rect(players[0 if battle.last_move.x <= 0 else 4], Rect2(player - Vector2(24, 27), Vector2(48, 48)), false)
		draw_set_transform(player + Vector2(0, 4), battle.aim.angle(), Vector2.ONE)
		draw_texture_rect(weapon, Rect2(0, -13, 32, 26), false)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	for bullet in battle.bullets:
		var color: Color = Color("c4527b") if bool(bullet.enemy) else Color("fff0b0")
		draw_circle(bullet.p, 5 if bool(bullet.enemy) else 3.5, color)
		draw_line(bullet.p, Vector2(bullet.p) - Vector2(bullet.v).normalized() * 10, color, 3, true)
	for particle in battle.particles:
		draw_rect(Rect2(Vector2(particle.p), Vector2(4, 4)), particle.color)
	var origin: Vector2 = joystick_origin if joystick_active else Vector2(100, 853)
	draw_circle(origin, 48, Color(0.8, 0.75, 0.86, 0.13))
	draw_arc(origin, 48, 0, TAU, 32, Color(0.8, 0.75, 0.86, 0.36), 2, true)
	var knob: Vector2 = origin + ((joystick_point - joystick_origin).limit_length(42) if joystick_active else Vector2.ZERO)
	draw_circle(knob, 22, Color(0.85, 0.82, 0.9, 0.42))

func _tex(index: int, rectangle: Rect2, color: Color = Color.WHITE) -> void:
	if textures.has(index):
		draw_texture_rect(textures[index], rectangle, false, color)

func _sound(key: String) -> void:
	if not _audio_shutting_down and state.settings.sound and sounds.has(key):
		sounds[key].play()

func _show_toast(message: String) -> void:
	if is_instance_valid(toast): toast.queue_free()
	var toast_y := minf(906.0, menu_scroll.size.y - 55.0) + float(menu_scroll.scroll_vertical)
	toast = _label(message, Vector2(36, toast_y), Vector2(468, 43), 15, GOLD if screen in ["home", "play", "results"] else TEAL, true)
	toast_time = 4.0

func _today() -> String:
	return Time.get_date_string_from_system(true)

func _sync_progress() -> void:
	if catalog.is_empty(): return
	var metrics: Dictionary = state.metrics()
	for achievement in catalog.get("achievements", []):
		if int(metrics.get(str(achievement.metric), 0)) >= int(achievement.threshold) and not state.unlocked.has(str(achievement.key)):
			state.unlocked[str(achievement.key)] = true
			if service != null: service.unlock(str(achievement.key))
	if service != null:
		for board in catalog.get("leaderboards", []):
			service.submit(str(board.key), int(metrics.get(str(board.metric), 0)))

func _load() -> void:
	for file in [SAVE, SAVE + ".bak"]:
		if FileAccess.file_exists(file):
			var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
			if state.load_data(raw): return

func _save() -> void:
	if smoke or not capture_screen.is_empty(): return
	if FileAccess.file_exists(SAVE):
		var existing: String = FileAccess.get_file_as_string(SAVE)
		if JSON.parse_string(existing) is Dictionary:
			var backup = FileAccess.open(SAVE + ".bak", FileAccess.WRITE)
			if backup: backup.store_string(existing)
	var file = FileAccess.open(SAVE, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(state.data()))

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image = get_viewport().get_texture().get_image()
	if capture_path.is_empty() or image.is_empty():
		push_error("Capture requires a rendered viewport and explicit output path")
		_quit_cleanly(1)
		return
	DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
	var result: int = image.save_png(capture_path)
	print("OUTLAW_CAPTURE screen=%s level=%d output=%s error=%d" % [capture_screen, capture_level, capture_path, result])
	_quit_cleanly(0 if result == OK else 1)

func _restart_music() -> void:
	if not _audio_shutting_down and state.settings.music:
		music.play()

func _stop_owned_audio() -> void:
	_audio_shutting_down = true
	if is_instance_valid(music) and music.finished.is_connected(_restart_music):
		music.finished.disconnect(_restart_music)
	for player in sounds.values():
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	if is_instance_valid(music):
		music.stop()
		music.stream = null

func shutdown_audio() -> void:
	# AudioServer.stop_playback_stream schedules FADE_OUT_TO_DELETION; stopping
	# nodes in _exit_tree alone can leave Ogg/WAV playbacks owned by the mixer.
	# Release our streams while the tree is alive, then give the mixer real time
	# to consume its stop commands before deleting the scene or quitting.
	if _audio_drained: return
	_stop_owned_audio()
	var drain_seconds := clampf(AudioServer.get_time_to_next_mix() * 3.0, 0.1, 0.25)
	await get_tree().create_timer(drain_seconds, true, false, true).timeout
	await get_tree().process_frame
	_audio_drained = true

func _quit_cleanly(code: int) -> void:
	if _quit_pending: return
	_quit_pending = true
	await shutdown_audio()
	get_tree().quit(code)

func _exit_tree() -> void:
	# Fallback for owners that remove this scene without using shutdown_audio.
	_stop_owned_audio()
