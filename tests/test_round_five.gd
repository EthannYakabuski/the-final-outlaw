extends SceneTree
## Controlled model fixtures. No player save, ad callback, device or backend proof.
const Combat = preload("res://game/combat.gd")
const State = preload("res://game/state.gd")
var checks := 0
var failures := 0
var pursuit_trials := 0
var campaign: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

func close(actual: float, expected: float, label: String) -> void:
	check(is_equal_approx(actual, expected), "%s actual=%f expected=%f" % [label, actual, expected])

func _initialize() -> void:
	campaign = JSON.parse_string(FileAccess.get_file_as_string("res://game/campaign.json"))
	_test_runner_reduction()
	_test_first_minute()
	_test_all_towns_and_corners()
	print("OUTLAW_ROUND_FIVE_TESTS checks=%d failures=%d campaign_towns=100 endless_seeds=100 corner_attack_trials=%d (controlled model only)" % [checks, failures, pursuit_trials])
	quit(0 if failures == 0 else 1)

func _test_runner_reduction() -> void:
	var battle = Combat.new()
	battle.start(campaign[0], State.new().stats(), 13)
	for difficulty in [1.0, 3.5, 20.0]:
		for rule in ["steady", "swift"]:
			battle.level.difficulty = difficulty
			battle.level.rule = rule
			for kind in Combat.TYPES:
				battle.enemies.clear()
				battle._spawn_enemy(kind, Vector2(270, 400))
				var expected := float(Combat.TYPES[kind].speed) * minf(1.7, 1.0 + difficulty * 0.04) * (1.2 if rule == "swift" else 1.0) * 1.25
				close(float(battle.enemies[0].speed), expected * (0.85 if kind == "runner" else 1.0), "15 percent reduction only affects runner after existing scalars")
	battle.obstacles.clear()
	battle.level.difficulty = 1.0
	battle.level.rule = "steady"
	battle.player = Vector2(270, 650)
	battle.enemies.clear()
	battle._spawn_enemy("runner", Vector2(270, 400))
	battle._update_enemies(0.05)
	close(Vector2(battle.enemies[0].p).y - 400.0, 128.0 * 1.04 * 1.25 * 0.85 * 0.05, "real runner movement uses reduced speed once")

func endless_definition() -> Dictionary:
	return {"id":0, "difficulty":2.0, "spawn":1.45, "enemies":["drifter","runner","gunner","tank","sniper"], "chapter":10, "mode":"survive", "target":100000, "time_limit":100000, "hazard":"sandburst", "layout":42, "rule":"steady"}

func _test_first_minute() -> void:
	var battle = Combat.new()
	battle.start(endless_definition(), State.new().stats(), 23, true)
	close(battle.spawn_timer, 3.0, "endless starts with a calm three-second introduction")
	var previous_difficulty := 0.0
	var previous_gap := 100.0
	for second in [0.0, 10.0, 20.0, 30.0, 40.0, 50.0, 59.999, 60.0, 120.0]:
		battle.elapsed = second
		var expected: float = 1.0 + (4.0 / 3.0) * second / 60.0 if second < 60.0 else 2.0 + second / 180.0
		close(battle.endless_difficulty(), expected, "continuous first-minute strength ramp")
		check(battle.endless_difficulty() >= previous_difficulty, "endless strength never drops as time advances")
		check(battle.endless_spawn_gap() <= previous_gap, "spawn cadence grows gradually")
		if second < 60.0:
			check(battle.endless_spawn_gap() > 1.45 / (1.0 + second / 120.0), "warmup spawns slower than the former immediate challenge")
		else:
			close(battle.endless_spawn_gap(), maxf(0.4, 1.45 / (1.0 + second / 120.0)), "established post-minute cadence retained")
		previous_difficulty = battle.endless_difficulty()
		previous_gap = battle.endless_spawn_gap()
		for sample in range(24):
			battle.rng.seed = sample
			battle.enemies.clear()
			battle.spawn_timer = 0.0
			battle._spawn_wave()
			var kind := str(battle.enemies[0].kind)
			if second < 20.0: check(kind == "drifter", "opening only spawns basic drifters")
			elif second < 40.0: check(kind in ["drifter","runner"], "runners join before ranged enemies")
			elif second < 60.0: check(kind in ["drifter","runner","gunner"], "heavy and sniper enemies wait until minute one")
	battle.elapsed = 0.0
	check(battle.endless_enemy_limit() == 4 and battle.hazard_points().is_empty(), "opening limits crowd and hazards")
	battle.elapsed = 30.0
	check(battle.endless_enemy_limit() == 11 and battle.hazard_points().size() == 1, "middle minute gradually adds pressure")
	battle.elapsed = 60.0
	check(battle.endless_enemy_limit() == 18 and battle.hazard_points().size() == 2, "full crowd and hazards arrive after warmup")
	var campaign_battle = Combat.new()
	campaign_battle.start(campaign[0], State.new().stats(), 24)
	close(campaign_battle.spawn_timer, 2.0, "campaign tutorial timing remains unchanged")

func corners() -> Array[Vector2]:
	var area: Rect2 = Combat.ARENA.grow(-Combat.PLAYER_RADIUS)
	return [area.position + Vector2(0.01,0.01), Vector2(area.end.x-0.01,area.position.y+0.01), area.end-Vector2(0.01,0.01), Vector2(area.position.x+0.01,area.end.y-0.01)]

func _test_all_towns_and_corners() -> void:
	var audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/ROUND_FIVE_LAYOUT_AUDIT.json"))
	check(audit.house_count_before == 650 and audit.house_count_after == 650, "all 650 original houses retained")
	var signatures := {}
	for index in range(100):
		var definition: Dictionary = campaign[index]
		var battle = Combat.new()
		battle.start(definition, State.new().stats(), 112)
		check(battle.town.buildings.size() == int(audit.rows[index].houses_before), "per-town house count retained")
		var physical: Array = []
		for parcel in battle.town.buildings:
			var wall: Rect2 = Combat.Town.rectangle(parcel)
			check(wall.position.x - Combat.ARENA.position.x >= 62.0 and Combat.ARENA.end.x-wall.end.x >= 62.0, "house leaves both horizontal edge lanes clear")
			check(wall.position.y - Combat.ARENA.position.y >= 64.0 and Combat.ARENA.end.y-wall.end.y >= 64.0, "house leaves both vertical edge lanes clear")
			physical.append([parcel.x,parcel.y,parcel.w,parcel.h])
		var signature := JSON.stringify([physical,battle.town.cover])
		check(not signatures.has(signature), "town physical identity remains distinct")
		signatures[signature] = true
		# The largest actual movement collider is the player's15px; all enemy
		# archetypes use14px. Check a conservative27px envelope along the ring
		# as well, matching the boss projectile-hit radius without changing combat.
		for x in range(32, 496-31, 10):
			for y in [32.0, 608.0-32.0]:
				check(not battle.blocked(Combat.ARENA.position+Vector2(x,y),27.0), "wide top/bottom perimeter envelope is unobstructed")
		for y in range(32, 608-31, 10):
			for x in [32.0, 496.0-32.0]:
				check(not battle.blocked(Combat.ARENA.position+Vector2(x,y),27.0), "wide left/right perimeter envelope is unobstructed")
		for target in corners():
			check(not battle.blocked(target,Combat.PLAYER_RADIUS), "player corner remains a legal location")
			var spawn: Vector2 = battle.edge_points[0]
			for point in battle.edge_points:
				if point.distance_squared_to(target) > spawn.distance_squared_to(target): spawn = point
			check(not battle.route(spawn,target).is_empty(), "opposite-edge spawn can route to every corner")
			var kinds: Array = ["runner","tank"]
			if index % 10 == 0 or index == 99: kinds = Combat.TYPES.keys()
			for kind in kinds: _assert_corner_can_be_attacked(battle, spawn, target, str(kind), index + 1)
	# Endless actually selects from the same corrected100layouts by seed.
	for seed_value in range(100):
		var endless = Combat.new()
		endless.start(endless_definition(), State.new().stats(), seed_value, true)
		check(int(endless.town.id) == seed_value + 1, "all hundred endless layout selections are audited")
		for target in corners():
			check(not endless.route(endless.edge_points[0],target).is_empty(), "endless corner remains connected")

func _assert_corner_can_be_attacked(battle, spawn: Vector2, target: Vector2, kind: String, stage: int) -> void:
	# Only the objective/timer is neutralized so a short survive stage cannot
	# terminate the navigation fixture before the slowest pursuer arrives.
	# Player remains stationary with ordinary health and no firing/ads/rewards.
	battle.level.mode = "clear"
	battle.level.target = 100000
	battle.level.time_limit = 100000
	battle.level.hazard = "none"
	battle.player = target
	battle.health = battle.max_health
	battle.invincible = 0.0
	battle.contact_timer = 0.0
	battle.elapsed = 0.0
	battle.result = ""
	battle.spawn_timer = 9999.0
	battle.enemies.clear()
	battle.bullets.clear()
	battle._spawn_enemy(kind,spawn)
	for tick in range(800):
		battle.step(0.05,Vector2.ZERO)
		if battle.health < battle.max_health: break
	pursuit_trials += 1
	check(battle.health < battle.max_health, "stage%d %s can reach or shoot corner %s through actual movement/projectiles" % [stage,kind,target])
