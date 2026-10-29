extends SceneTree
## Deterministic source fixtures; these do not establish native or human balance QA.
const State = preload("res://game/state.gd")
const Combat = preload("res://game/combat.gd")
var checks := 0
var failures := 0
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
	_test_persistent_ranks()
	_test_spawn_matrix()
	_test_actual_shots()
	_test_damage_paths()
	_test_player_movement()
	print("OUTLAW_ROUND_THREE_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_persistent_ranks() -> void:
	for rank in range(State.UPGRADE_CAP + 1):
		var legacy = State.new()
		legacy.coins = 1700
		legacy.xp = 858
		legacy.completed = {"1": 3, "2": 3}
		for key in legacy.upgrades: legacy.upgrades[key] = rank
		var saved: Dictionary = legacy.data()
		var restored = State.new()
		restored.load_data(saved)
		check(restored.data() == saved, "existing profile/ranks round-trip without migration rank%d" % rank)
		var stats: Dictionary = restored.stats()
		close(stats.health, (100.0 + rank * 12.0) * 0.60, "whole health including upgrades rank%d" % rank)
		close(stats.speed, (165.0 + rank * 8.0) * 0.88, "whole speed including upgrades rank%d" % rank)
		close(stats.damage, 5.0 + rank, "power unchanged rank%d" % rank)
		check(stats.magazine == 20 + rank * 4, "manual-fire capacity unchanged rank%d" % rank)
		close(stats.fire_interval, 0.30, "manual-fire cadence unchanged rank%d" % rank)
		close(stats.reload_seconds, 1.65 - rank * 0.12, "reload benefit unchanged rank%d" % rank)
		close(stats.dash_cooldown, 2.1 - rank * 0.13, "dash benefit unchanged rank%d" % rank)
		close(stats.armor, rank * 0.035, "armor benefit unchanged rank%d" % rank)
		if rank < State.UPGRADE_CAP:
			restored.upgrades.heart += 1
			close(restored.stats().health - stats.health, 7.2, "effective heart increment rank%d" % rank)
			restored.upgrades.boots += 1
			close(restored.stats().speed - stats.speed, 7.04, "effective boots increment rank%d" % rank)

func _test_spawn_matrix() -> void:
	var combat = Combat.new()
	combat.start(campaign[0], State.new().stats(), 324)
	for definition in campaign:
		combat.level = definition.duplicate(true)
		for kind in Combat.TYPES:
			_assert_spawn(combat, kind, "trail%d" % int(definition.id))
	# Explicit rule combinations cover health armor, speed modifiers and capped endless scaling.
	for rule in ["steady", "armored", "swift", "quickdraw", "crossfire", "longshot"]:
		for difficulty in [1.0, 3.5, 12.0]:
			for seconds in [0.0, 180.0, 1800.0]:
				combat.level = {"difficulty": difficulty, "rule": rule}
				combat.survival = true
				combat.elapsed = seconds
				for kind in Combat.TYPES: _assert_spawn(combat, kind, "endless%s/%s/%s" % [rule, difficulty, seconds])

func _assert_spawn(combat, kind: String, label: String) -> void:
	combat.enemies.clear()
	combat._spawn_enemy(kind, Vector2(270, 350))
	var enemy: Dictionary = combat.enemies[0]
	var info: Dictionary = Combat.TYPES[kind]
	var difficulty: float = float(combat.level.get("difficulty", 1.0))
	if combat.survival:
		difficulty = lerpf(1.0, difficulty + 60.0 / 180.0, combat.elapsed / 60.0) if combat.elapsed < 60.0 else difficulty + combat.elapsed / 180.0
	var rule := str(combat.level.get("rule", "steady"))
	# Match the original arithmetic order: armor modifies the multiplier before base HP.
	var health_multiplier: float = 1.0 + (difficulty - 1.0) * 0.22
	if rule == "armored": health_multiplier *= 1.25
	var original_hp: float = float(info.hp) * health_multiplier
	close(enemy.hp, original_hp + 15.0, "%s %s additive post-scale HP" % [label, kind])
	close(enemy.max_hp, enemy.hp, "%s %s max HP agrees" % [label, kind])
	check(ceili(float(enemy.hp) / 5.0) - ceili(original_hp / 5.0) == 3, "%s %s exactly three extra baseline shots" % [label, kind])
	close(enemy.speed, float(info.speed) * minf(1.7, 1.0 + difficulty * 0.04) * (1.2 if rule == "swift" else 1.0) * 1.25 * (0.85 if kind == "runner" else 1.0), "%s %s speed buffs once" % [label, kind])
	close(enemy.damage, float(info.damage) * minf(2.0, 1.0 + difficulty * 0.07) * 1.15, "%s %s damage buff once" % [label, kind])

func _test_actual_shots() -> void:
	for kind in Combat.TYPES:
		for rule in ["steady", "armored"]:
			var combat = Combat.new()
			combat.start(campaign[0], State.new().stats(), 125)
			combat.level.difficulty = 3.5
			combat.level.rule = rule
			combat.obstacles.clear()
			combat.player = Vector2(270, 500)
			combat._spawn_enemy(kind, Vector2(270, 400))
			var original_hp := float(Combat.TYPES[kind].hp) * 1.55 * (1.25 if rule == "armored" else 1.0)
			var expected_shots := ceili(original_hp / 5.0) + 3
			for shot in range(expected_shots):
				# Exercise the real fired projectile and swept enemy hit, not direct HP subtraction.
				check(combat.kills == 0, "%s/%s survives before required shot%d" % [kind, rule, shot + 1])
				combat._fire()
				check(combat.bullets.size() == 1 and combat.bullets[0].damage == 5.0, "real unupgraded single projectile")
				combat._update_bullets(0.25)
			check(combat.kills == 1 and combat.enemies.is_empty(), "%s/%s defeated by expected real projectile count" % [kind, rule])

func _test_damage_paths() -> void:
	for armor_rank in [0, 8]:
		var state = State.new()
		state.upgrades.armor = armor_rank
		var armor := float(state.stats().armor)
		for kind in Combat.TYPES:
			var contact = Combat.new()
			contact.start(campaign[0], state.stats(), 915)
			contact.obstacles.clear()
			contact.player = Vector2(270, 500)
			contact._spawn_enemy(kind, contact.player)
			contact._update_enemies(0.0)
			var expected := float(Combat.TYPES[kind].damage) * 1.07 * 1.15 * (1.0 - armor)
			close(contact.max_health - contact.health, expected, "%s contact once then armor%d" % [kind, armor_rank])
			if float(Combat.TYPES[kind].shot) > 0.0:
				var ranged = Combat.new()
				ranged.start(campaign[0], state.stats(), 916)
				ranged.obstacles.clear()
				ranged.player = Vector2(270, 500)
				ranged._spawn_enemy(kind, Vector2(270, 350))
				ranged.enemies[0].timer = 0.0
				ranged._update_enemies(0.0)
				check(ranged.bullets.size() == (3 if kind == "boss" else 1), "%s real ranged emission" % kind)
				var projectile: Dictionary = ranged.bullets[ranged.bullets.size() / 2].duplicate(true)
				close(projectile.damage, float(Combat.TYPES[kind].damage) * 1.07 * 1.15, "projectile carries spawned buff once")
				projectile.p = Vector2(270, 450)
				projectile.v = Vector2(0, 145)
				ranged.bullets.clear()
				ranged.bullets.append(projectile)
				ranged._update_bullets(0.4)
				close(ranged.max_health - ranged.health, expected, "%s actual projectile once then armor%d" % [kind, armor_rank])
		var hazard = Combat.new()
		hazard.start(campaign[0], state.stats(), 917)
		hazard.level.hazard = "sandburst"
		hazard.player = hazard.hazard_points()[0]
		hazard.hazard_clock = 4.99
		hazard._update_hazard(0.02)
		close(hazard.max_health - hazard.health, 12.0 * (1.0 - armor), "environmental hazard unchanged armor%d" % armor_rank)

func _test_player_movement() -> void:
	for rank in [0, 8]:
		var state = State.new()
		state.upgrades.boots = rank
		var combat = Combat.new()
		combat.start(campaign[0], state.stats(), 44)
		combat.obstacles.clear()
		combat.player = Vector2(200, 500)
		var before: Vector2 = combat.player
		combat.step(0.05, Vector2.RIGHT)
		close(combat.player.x - before.x, (165.0 + rank * 8.0) * 0.88 * 0.05, "actual player movement scaled rank%d" % rank)
		close(combat.player.y, before.y, "horizontal movement remains horizontal")
