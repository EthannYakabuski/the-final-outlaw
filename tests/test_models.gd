extends SceneTree

const State = preload("res://game/state.gd")
const Fight = preload("res://game/combat.gd")
var checks: int = 0
var failures: int = 0
var campaign: Array = []

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	campaign = JSON.parse_string(FileAccess.get_file_as_string("res://game/campaign.json"))
	_test_state()
	_test_catalog_and_campaign()
	_test_combat()
	_test_campaign_reachability()
	print("OUTLAW_MODEL_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_state() -> void:
	var s = State.new()
	check(s.open_level(1) and not s.open_level(2) and not s.open_level(101), "sequential initial unlock")
	s.roll_day("2026-10-20")
	check(s.claim_login("2026-10-20") == 35 and s.streak == 1, "first UTC login gift")
	check(s.claim_login("2026-10-20") == 0 and s.claim_login("2026-10-19") == 0, "same-day and rollback gifts rejected")
	for date in range(21, 27): s.claim_login("2026-10-%02d" % date)
	check(s.streak == 7 and s.claim_login("2026-10-27") == 35 and s.streak == 1, "seven-day reward cycle")
	s.claim_login("2026-10-29")
	check(s.streak == 1, "missed day resets streak")
	check(not s.roll_day("2026-10-28"), "day cannot roll backwards")
	check(not s.roll_day("2026-02-31") and s.claim_login("bad") == 0, "invalid dates rejected safely")
	check(s.reward_crate("2026-10-29") and not s.reward_crate("2026-10-29") and not s.reward_crate("2026-10-28"), "earned crate once per monotonic day")
	var r: Dictionary = s.record_run(1, true, 20, 45.0, .8, 2200)
	check(r.first and r.stars == 3 and s.open_level(2), "campaign completion stars/unlock")
	var repeat: Dictionary = s.record_run(1, true, 20, 45.0, .1, 2200)
	check(not repeat.first and repeat.coins < r.coins and int(s.completed["1"]) == 3, "replay reward lower and best stars retained")
	check(s.claim_quest("kills") == 80 and s.claim_quest("kills") == 0, "quest target and idempotent claim")
	check(s.claim_quest("invented") == 0, "unknown quest rejected")
	s.record_run(0, false, 2, 67, .0, 900, true)
	s.record_run(0, false, 1, 20, .0, 100, true)
	check(s.best_survival == 900 and s.best_seconds == 67, "survival records monotonic")
	var old_level: int = s.player_level()
	var old_coins: int = s.coins
	var bonus: int = s.add_xp(750)
	check(s.player_level() > old_level and bonus == (s.player_level() - old_level) * 50 and s.coins == old_coins + bonus, "player levels award coins")
	s.coins = 100000
	var old_stats: Dictionary = s.stats()
	check(s.buy_upgrade("power") and s.stats().damage > old_stats.damage, "weapon purchase affects combat")
	for i in range(12): s.buy_upgrade("boots")
	check(s.upgrades.boots == 8 and s.upgrade_cost("boots") == -1 and not s.buy_upgrade("unknown"), "upgrade cap and bad key")
	var restored = State.new()
	check(restored.load_data(JSON.parse_string(JSON.stringify(s.data()))), "JSON roundtrip load")
	check(restored.data() == s.data(), "all saved progression survives JSON numeric conversion")
	check(not restored.load_data([]) and not restored.load_data(null), "corrupt root rejected")
	var malformed = State.new()
	check(malformed.load_data({"coins": -40, "xp": -4, "completed": {"101": 3, "2": 8}, "upgrades": {"power": 999, "heart": -3}, "day":"2026-99-90", "daily":[]} ), "malformed fields load defensively")
	check(malformed.coins == 0 and malformed.xp == 0 and malformed.upgrades.power == 8 and malformed.upgrades.heart == 0 and malformed.completed == {"2":3} and malformed.day.is_empty(), "malformed fields clamped")
	var fresh = State.new()
	check(fresh.claim_quest("wins") == 0, "unearned quest cannot be claimed")
	fresh.roll_day("2026-10-20")
	fresh.record_run(1, true, 3, 20, .5, 100)
	fresh.roll_day("2026-10-21")
	check(fresh.daily.kills == 0 and fresh.daily_claimed.is_empty(), "new UTC day resets quests only")
	check(fresh.completed.has("1"), "day reset keeps permanent progression")

func _test_catalog_and_campaign() -> void:
	check(campaign.size() == 100, "exactly 100 shipped trails")
	var signatures: Dictionary = {}
	var names: Dictionary = {}
	var modes: Dictionary = {}
	var chapters: Dictionary = {}
	for i in range(campaign.size()):
		var d: Dictionary = campaign[i]
		check(int(d.id) == i + 1 and int(d.chapter) == i / 10 + 1, "ordered trail/chapter %d" % (i + 1))
		check(d.difficulty >= 1 and (i == 0 or d.difficulty > campaign[i - 1].difficulty), "increasing stat difficulty %d" % (i + 1))
		var signature: String = JSON.stringify([d.mode,d.target,d.layout,d.enemies,d.rule,d.waves,d.hazard])
		check(not signatures.has(signature) and not names.has(d.name), "unique encounter contract %d" % (i + 1))
		signatures[signature] = true; names[d.name] = true; modes[d.mode] = true; chapters[d.chapter_name] = true
		var budget: int = 0
		var last_at: float = -1
		for wave in d.waves:
			check(wave.count > 0 and wave.gap >= .4 and wave.at > last_at and not wave.roster.is_empty(), "valid wave %d" % (i + 1))
			for kind in wave.roster: check(Fight.TYPES.has(kind), "known enemy %s" % kind)
			budget += int(wave.count); last_at = float(wave.at)
		check(d.time_limit > last_at + float(d.waves[-1].count) * float(d.waves[-1].gap), "deadline includes final wave %d" % (i + 1))
		if d.mode == "clear": check(budget >= d.target, "elimination goal supported by budget")
		if d.mode == "supply": check(3 + budget / 2 >= d.target, "supply goal supported by drops")
	check(modes.size() == 5 and chapters.size() == 10, "five objective types and ten themes")
	check(campaign[0].target == 3 and campaign[1].mode == "survive" and campaign[1].target == 20 and campaign[0].hazard == "none", "first two tutorial contracts")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/catalog.json"))
	var metrics: Dictionary = State.new().metrics()
	var keys: Dictionary = {}
	for achievement in catalog.achievements:
		check(metrics.has(achievement.metric) and achievement.threshold > 0 and not keys.has(achievement.key), "valid unique achievement " + str(achievement.key))
		keys[achievement.key] = true
	for board in catalog.leaderboards: check(metrics.has(board.metric), "known leaderboard metric")
	check(catalog.achievements.size() >= 20 and catalog.leaderboards.size() >= 4, "full achievement/leaderboard catalog")

func _test_combat() -> void:
	var a = Fight.new(); var b = Fight.new()
	a.start(campaign[12], State.new().stats(), 987)
	b.start(campaign[12], State.new().stats(), 987)
	for i in range(800):
		var move: Vector2 = Vector2(cos(i * .01), sin(i * .01))
		a.step(.02, move, i % 200 == 0); b.step(.02, move, i % 200 == 0)
	check(a.player == b.player and a.kills == b.kills and a.health == b.health and a.enemies == b.enemies and a.bullets == b.bullets, "seeded combat deterministic")
	check(a.health >= 0 and a.enemies.size() <= 18 and a.particles.size() <= 120, "bounded combat pools")
	var d = Fight.new(); d.start(campaign[0], State.new().stats(), 1)
	var initial: Vector2 = d.player
	d.step(.05, Vector2.RIGHT, true)
	check(d.player.x - initial.x > 20 and d.invincible > 0 and d.dash_cooldown > 2, "dash moves and protects")
	var cooldown: float = d.dash_cooldown
	d.step(.05, Vector2.RIGHT, true)
	check(d.dash_cooldown < cooldown, "dash cannot restart on cooldown")
	var wall: Rect2 = d.obstacles[0]
	var next: Vector2 = d.move_actor(wall.position - Vector2(20,-10), Vector2(25,0),15)
	check(not d.blocked(next,15), "actor cannot enter obstacle")
	d.health = 30; d.pickups.assign([{"p":d.player,"kind":"heart","life":1.0}]); d.step(.01,Vector2.ZERO)
	check(d.health > 30, "heart collectible heals")
	d.pickups.assign([{"p":d.player,"kind":"shield","life":1.0}]); d.step(.01,Vector2.ZERO)
	var hp: float = d.health; d.invincible = 0; d._damage(20)
	check(d.health == hp and d.shield_time > 0, "shield blocks damage")
	d.result = "lost"; d.elapsed = float(d.level.time_limit) + 1
	check(d.revive() and d.health > 0 and d.invincible == 3 and d.level.time_limit > d.elapsed and not d.revive(), "one earned continue and timeout grace")
	d.result = "lost"; check(not d.revive(), "second continue denied")
	var endless = Fight.new(); endless.start(campaign[99], {"health":100000,"damage":30,"speed":210,"fire_interval":.25}, 123, true)
	for i in range(4000): endless.step(.05, Vector2(cos(i*.009),sin(i*.009)), i%70==0)
	check(endless.elapsed > 190 and endless.result.is_empty() and endless.total_spawned > 40 and endless.enemies.size() <= 18, "endless continues beyond campaign deadline with bounded population")
	var early = Fight.new(); early.start(campaign[0],State.new().stats(),1)
	var late = Fight.new(); late.start(campaign[99],State.new().stats(),1)
	early._spawn_enemy("drifter",Vector2(50,200)); late._spawn_enemy("drifter",Vector2(50,200))
	check(late.enemies[0].hp > early.enemies[0].hp and late.enemies[0].damage > early.enemies[0].damage, "later campaign stats harder")
	for tutorial in range(2):
		var practice = Fight.new(); practice.start(campaign[tutorial],State.new().stats(),12)
		for tick in range(3000):
			practice.step(.05,Vector2(cos(tick*.004),sin(tick*.004))*.5,tick%100==0)
			if not practice.result.is_empty(): break
		check(practice.result == "win", "tutorial completable with starting gear and normal damage %d" % (tutorial+1))

func _test_campaign_reachability() -> void:
	# Goal navigation and real enemy/projectile simulation. Invulnerability here
	# isolates completion/reachability from subjective human difficulty balancing.
	var victories: int = 0
	for definition in campaign:
		var battle = Fight.new()
		battle.start(definition, {"health":196.0,"damage":13.0,"speed":229.0,"fire_interval":.36}, 77 + int(definition.id))
		check(not battle.blocked(battle.player,15) and not battle.blocked(battle.hold_center(),15), "free player/goal spawn %d" % int(definition.id))
		var navigation: Dictionary = _navigation(battle)
		check(navigation.size() > 1000, "connected navigable arena %d" % int(definition.id))
		for pickup in battle.pickups:
			check(navigation.has(_cell(pickup.p)), "reachable supply %d" % int(definition.id))
		var time_cap: int = int(float(definition.time_limit) / .05) + 5
		for tick in range(time_cap):
			battle.invincible = 1000
			var target: Vector2 = Vector2(270,455)
			if definition.mode == "supply" and not battle.pickups.is_empty():
				var dist: float = INF
				for pickup in battle.pickups:
					if pickup.kind == "supply" and battle.player.distance_to(pickup.p) < dist:
						dist = battle.player.distance_to(pickup.p); target = pickup.p
			elif definition.mode != "hold":
				if not battle.enemies.is_empty():
					target = battle.enemies[0].p
					for enemy in battle.enemies:
						if battle.player.distance_to(enemy.p) < battle.player.distance_to(target): target = enemy.p
					if battle.player.distance_to(target) < 120 and battle.line_clear(battle.player,target): target = battle.player
				else: target = Vector2(270,455)
			var movement: Vector2 = battle.player.direction_to(target) if battle.player.distance_to(target)>6 else Vector2.ZERO
			if battle.blocked(battle.player + movement * 20,15): movement = movement.rotated(PI/2)
			battle.step(.05,movement,false)
			if not battle.result.is_empty(): break
		if battle.result == "win": victories += 1
		check(battle.result == "win", "simulated reachable victory %d mode=%s kills=%d supplies=%d" % [definition.id,definition.mode,battle.kills,battle.supplies])
	print("OUTLAW_CAMPAIGN_SIMULATIONS victories=%d/100 (max gear, test invulnerability; not a human balance claim)" % victories)

func _cell(point: Vector2) -> Vector2i:
	return Vector2i(roundi((point.x-38)/12), roundi((point.y-156)/12))

func _navigation(battle) -> Dictionary:
	var start: Vector2i = _cell(battle.player)
	var visited: Dictionary = {start:true}
	var todo: Array[Vector2i] = [start]
	var head: int = 0
	while head < todo.size():
		var cell: Vector2i = todo[head]; head += 1
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			var point: Vector2 = Vector2(next)*12 + Vector2(38,156)
			if next.x < 0 or next.x > 38 or next.y < 0 or next.y > 48 or visited.has(next) or battle.blocked(point,15): continue
			visited[next] = true; todo.append(next)
	return visited
