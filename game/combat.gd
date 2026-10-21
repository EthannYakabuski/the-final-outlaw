extends RefCounted
## Deterministic combat simulation, shared by the running game and model tests.

const Town = preload("res://game/town.gd")
const ARENA = Rect2(22, 140, 496, 608)
const TYPES = {
	"drifter": {"speed": 64.0, "hp": 18.0, "damage": 9.0, "sprite": 4, "shot": 0.0},
	"runner": {"speed": 128.0, "hp": 12.0, "damage": 7.0, "sprite": 0, "shot": 0.0},
	"gunner": {"speed": 52.0, "hp": 25.0, "damage": 9.0, "sprite": 12, "shot": 2.7},
	"tank": {"speed": 41.0, "hp": 68.0, "damage": 15.0, "sprite": 8, "shot": 0.0},
	"sniper": {"speed": 43.0, "hp": 29.0, "damage": 15.0, "sprite": 14, "shot": 3.8},
	"boss": {"speed": 40.0, "hp": 200.0, "damage": 18.0, "sprite": 13, "shot": 2.4}
}
var level: Dictionary = {}
var stats: Dictionary = {}
var rng = RandomNumberGenerator.new()
var player: Vector2 = Vector2(270, 495)
var health: float = 100.0
var max_health: float = 100.0
var enemies: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var events: Array[Dictionary] = []
var obstacles: Array[Rect2] = []
var town: Dictionary = {}
var navigation: AStarGrid2D = AStarGrid2D.new()
var free_cells: Array[Vector2i] = []
var edge_points: Array[Vector2] = []
var elapsed: float = 0.0
var kills: int = 0
var supplies: int = 0
var hold_time: float = 0.0
var score: int = 0
var result: String = ""
var fire_timer: float = 0.0
var magazine: int = 20
var ammo: int = 20
var reload_time: float = 0.0
var reload_duration: float = 1.65
var spawn_timer: float = 0.0
var invincible: float = 0.0
var dash_cooldown: float = 0.0
var dash_time: float = 0.0
var dash_direction: Vector2 = Vector2.UP
var last_move: Vector2 = Vector2.UP
var rapid_time: float = 0.0
var spread_time: float = 0.0
var shield_time: float = 0.0
var aim: Vector2 = Vector2.UP
var boss_spawned: bool = false
var boss_defeated: bool = false
var revived: bool = false
var survival: bool = false
var contact_timer: float = 0.0
var hazard_clock: float = 0.0
var wave_index: int = 0
var wave_spawned: int = 0
var total_spawned: int = 0

func start(definition: Dictionary, player_stats: Dictionary, seed_value: int = 1, endless: bool = false) -> void:
	level = definition.duplicate(true)
	stats = player_stats.duplicate(true)
	rng.seed = seed_value
	max_health = float(stats.get("health", 100.0))
	health = max_health
	magazine = int(stats.get("magazine", 20))
	ammo = magazine
	reload_duration = float(stats.get("reload_seconds", 1.65))
	survival = endless
	_build_obstacles()
	if str(level.get("mode", "clear")) == "supply":
		for i in range(3):
			pickups.append({"p": _free_point(Vector2(105 + i * 165, 355 + (i % 2) * 140)), "kind": "supply", "life": 600.0})
	spawn_timer = 2.0 if int(level.get("id", 1)) < 3 else 0.8

func _build_obstacles() -> void:
	town = Town.for_stage(int(level.get("id",1)) if int(level.get("id",1))>0 else 1+int(rng.seed)%100)
	for parcel in town.buildings: obstacles.append(Town.rectangle(parcel))
	for cell in town.cover: obstacles.append(Rect2(Town.center(cell)-Vector2(12,12),Vector2(24,24)))
	navigation.region = Rect2i(0,0,48,58)
	navigation.cell_size = Vector2(10,10)
	navigation.offset = ARENA.position+Vector2(15,15)
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	for y in range(58):
		for x in range(48):
			var cell := Vector2i(x,y)
			var point := navigation.get_point_position(cell)
			var solid := blocked(point,15.0) or not ARENA.grow(-15).has_point(point)
			navigation.set_point_solid(cell,solid)
			if not solid:
				free_cells.append(cell)
				if x==0 or x==46 or y==0 or y==57: edge_points.append(point)
	player = _free_point(player)

func _nearest_cell(point: Vector2) -> Vector2i:
	var local := (point-navigation.offset)/navigation.cell_size
	var cell := Vector2i(clampi(roundi(local.x),0,47),clampi(roundi(local.y),0,57))
	if not navigation.is_point_solid(cell): return cell
	var best := free_cells[0]
	var distance := INF
	for candidate in free_cells:
		var d := navigation.get_point_position(candidate).distance_squared_to(point)
		if d<distance: distance=d;best=candidate
	return best

func _free_point(point: Vector2) -> Vector2:
	return navigation.get_point_position(_nearest_cell(point))

func actor_line_clear(origin: Vector2,target: Vector2) -> bool:
	var steps := maxi(1,ceili(origin.distance_to(target)/7.0))
	for i in range(1,steps+1):
		var point := origin.lerp(target,float(i)/steps)
		if blocked(point,14.0) or not ARENA.grow(-14.0).has_point(point): return false
	return true

func route(origin: Vector2,target: Vector2) -> PackedVector2Array:
	return navigation.get_point_path(_nearest_cell(origin),_nearest_cell(target))

func route_direction(origin: Vector2,target: Vector2) -> Vector2:
	if actor_line_clear(origin,target): return origin.direction_to(target)
	var points := route(origin,target)
	for point in points:
		if origin.distance_to(point)>7.0: return origin.direction_to(point)
	return Vector2.ZERO

func step(delta: float, movement: Vector2, request_dash: bool = false, request_fire: bool = false, request_reload: bool = false) -> void:
	events.clear()
	if not result.is_empty():
		return
	delta = clampf(delta, 0.0, 0.05)
	elapsed += delta
	invincible = maxf(0.0, invincible - delta)
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	dash_time = maxf(0.0, dash_time - delta)
	rapid_time = maxf(0.0, rapid_time - delta)
	spread_time = maxf(0.0, spread_time - delta)
	shield_time = maxf(0.0, shield_time - delta)
	contact_timer = maxf(0.0, contact_timer - delta)
	if movement.length() > 0.1:
		last_move = movement.normalized()
	if request_dash and dash_cooldown <= 0.0:
		dash_time = 0.2
		dash_cooldown = float(stats.get("dash_cooldown", 2.1))
		invincible = maxf(invincible, 0.3)
		dash_direction = last_move
		events.append({"kind": "dash", "p": player})
	var direction: Vector2 = dash_direction if dash_time > 0.0 else movement.limit_length(1.0)
	var speed: float = float(stats.get("speed", 165.0)) * (3.7 if dash_time > 0.0 else 1.0)
	player = move_actor(player, direction * speed * delta, 15.0)
	spawn_timer -= delta
	if str(level.get("mode", "")) == "duel" and not boss_spawned:
		_spawn_enemy("boss", _edge_spawn())
		boss_spawned = true
	_spawn_wave()
	_update_enemies(delta)
	fire_timer = maxf(0.0, fire_timer - delta)
	if reload_time > 0.0:
		reload_time = maxf(0.0, reload_time - delta)
		if reload_time <= 0.0:
			ammo = magazine
			events.append({"kind":"reload_ready", "p":player})
	elif request_reload and ammo < magazine:
		begin_reload()
	elif request_fire and fire_timer <= 0.0:
		if ammo > 0: _fire()
		else: begin_reload()
	_update_bullets(delta)
	_update_pickups(delta)
	_update_particles(delta)
	_update_hazard(delta)
	if str(level.get("mode", "")) == "hold":
		var ring: Vector2 = hold_center()
		if player.distance_to(ring) <= 66.0:
			hold_time += delta
		else:
			hold_time = maxf(0.0, hold_time - delta * 0.18)
	if health <= 0.0:
		result = "lost"
	elif not survival and objective_complete():
		result = "win"
	elif not survival and elapsed >= float(level.get("time_limit", 150.0)):
		result = "lost"
	score = kills * 100 + int(elapsed) * 3 + supplies * 30

func _spawn_wave() -> void:
	if spawn_timer > 0.0 or enemies.size() >= 18:
		return
	var roster: Array = level.get("enemies", ["drifter"])
	var gap: float = float(level.get("spawn", 1.8))
	if not survival and level.has("waves"):
		var waves: Array = level.waves
		if wave_index >= waves.size():
			return
		var wave: Dictionary = waves[wave_index]
		if elapsed < float(wave.at):
			return
		roster = wave.roster
		gap = float(wave.gap)
		wave_spawned += 1
		if wave_spawned >= int(wave.count):
			wave_spawned = 0
			wave_index += 1
	_spawn_enemy(str(roster[rng.randi_range(0, roster.size() - 1)]), _edge_spawn())
	total_spawned += 1
	var ramp: float = 1.0 + elapsed / 120.0 if survival else 1.0
	spawn_timer = maxf(0.4, gap / ramp)

func hold_center() -> Vector2:
	return _free_point(Vector2(270.0 + float(int(level.get("layout", 0)) % 3 - 1) * 28.0, 455.0))

func move_actor(origin: Vector2, change: Vector2, radius: float) -> Vector2:
	var target: Vector2 = origin
	var test_x: Vector2 = origin + Vector2(change.x, 0)
	if not blocked(test_x, radius):
		target.x = test_x.x
	var test_y: Vector2 = target + Vector2(0, change.y)
	if not blocked(test_y, radius):
		target.y = test_y.y
	target.x = clampf(target.x, ARENA.position.x + radius, ARENA.end.x - radius)
	target.y = clampf(target.y, ARENA.position.y + radius, ARENA.end.y - radius)
	return target

func blocked(point: Vector2, radius: float) -> bool:
	for wall in obstacles:
		if wall.grow(radius * 0.75).has_point(point):
			return true
	return false

func _edge_spawn() -> Vector2:
	return edge_points[rng.randi_range(0,edge_points.size()-1)]

func _spawn_enemy(kind: String, point: Vector2) -> void:
	if not TYPES.has(kind):
		kind = "drifter"
	var info: Dictionary = TYPES[kind]
	var difficulty: float = float(level.get("difficulty", 1.0))
	if survival:
		difficulty += elapsed / 180.0
	var health_multiplier: float = 1.0 + (difficulty - 1.0) * 0.22
	var rule: String = str(level.get("rule", "steady"))
	if rule == "armored": health_multiplier *= 1.25
	var hp: float = float(info.hp) * health_multiplier
	var enemy_speed: float = float(info.speed) * minf(1.7, 1.0 + difficulty * 0.04) * (1.2 if rule == "swift" else 1.0)
	enemies.append({"p": point, "kind": kind, "hp": hp, "max_hp": hp, "speed": enemy_speed, "damage": float(info.damage) * minf(2.0, 1.0 + difficulty * 0.07), "timer": rng.randf_range(0.8, 2.0), "flash": 0.0, "path":PackedVector2Array(), "repath":0.0, "skin":rng.randi_range(0,1)})

func _update_enemies(delta: float) -> void:
	for enemy in enemies:
		var point: Vector2 = enemy.p
		var direction: Vector2 = point.direction_to(player)
		var distance: float = point.distance_to(player)
		var info: Dictionary = TYPES[str(enemy.kind)]
		var wanted: Vector2 = direction
		var visible := actor_line_clear(point,player)
		if visible and float(info.shot)>0.0 and distance<205.0:
			wanted = direction.rotated(PI*0.5)*0.55 if distance>125.0 else -direction
		if not visible or blocked(point+wanted*20.0,14.0):
			enemy.repath = float(enemy.repath)-delta
			if float(enemy.repath)<=0.0 or enemy.path.is_empty():
				enemy.path = route(point,player)
				enemy.repath = 0.35
			while not enemy.path.is_empty() and point.distance_to(enemy.path[0])<8.0:
				enemy.path.remove_at(0)
			wanted = point.direction_to(enemy.path[0]) if not enemy.path.is_empty() else Vector2.ZERO
		else:
			enemy.path = PackedVector2Array()
		var next: Vector2 = move_actor(point,wanted*float(enemy.speed)*delta,14.0)

		enemy.p = next
		enemy.flash = maxf(0.0, float(enemy.flash) - delta)
		enemy.timer = float(enemy.timer) - delta
		if float(info.shot) > 0.0 and float(enemy.timer) <= 0.0 and distance < 470.0 and line_clear(next,player):
			enemy.timer = float(info.shot) * (0.72 if str(level.get("rule", "")) == "quickdraw" else 1.0)
			var angles: Array = [-0.25, 0.0, 0.25] if str(enemy.kind) == "boss" or str(level.get("rule", "")) == "crossfire" else [0.0]
			for offset in angles:
				bullets.append({"p": next, "v": direction.rotated(float(offset)) * (205.0 if str(enemy.kind) == "sniper" else 145.0) * (1.18 if str(level.get("rule", "")) == "longshot" else 1.0), "enemy": true, "damage": float(enemy.damage), "life": 4.0})
		if next.distance_to(player) < (30.0 if str(enemy.kind) == "boss" else 24.0) and contact_timer <= 0.0:
			_damage(float(enemy.damage))
			contact_timer = 0.65

func _fire() -> void:
	var closest: Dictionary = {}
	var distance: float = 390.0
	for enemy in enemies:
		var test_distance: float = player.distance_to(enemy.p)
		if test_distance < distance and line_clear(player, enemy.p):
			distance = test_distance
			closest = enemy
	if not closest.is_empty(): aim = player.direction_to(closest.p)
	elif last_move.length() > 0.1: aim = last_move
	ammo -= 1
	var angles: Array = [-0.16, 0.0, 0.16] if spread_time > 0.0 else [0.0]
	for offset in angles:
		bullets.append({"p": player + aim * 10, "v": aim.rotated(float(offset)) * 520.0, "enemy": false, "damage": float(stats.get("damage", 5.0)), "life": 1.0})
	fire_timer = float(stats.get("fire_interval", 0.36)) * (0.5 if rapid_time > 0.0 else 1.0)
	events.append({"kind": "shot", "p": player})

func begin_reload() -> bool:
	if reload_time > 0.0 or ammo >= magazine: return false
	reload_time = reload_duration
	events.append({"kind":"reload", "p":player})
	return true

func line_clear(origin: Vector2, target: Vector2) -> bool:
	var length: float = origin.distance_to(target)
	var steps: int = maxi(1, ceili(length / 12.0))
	for i in range(1, steps):
		if blocked(origin.lerp(target, float(i) / steps), 0.0): return false
	return true

func _segment_circle_t(origin:Vector2,end:Vector2,center:Vector2,radius:float) -> float:
	var direction:=end-origin
	var offset:=origin-center
	var c:=offset.length_squared()-radius*radius
	if c<=0.0:return 0.0
	var a:=direction.length_squared()
	if a<0.00001:return INF
	var b:=offset.dot(direction)
	var discriminant:=b*b-a*c
	if discriminant<0.0:return INF
	var time:=(-b-sqrt(discriminant))/a
	return time if time>=0.0 and time<=1.0 else INF

func _segment_wall_t(origin:Vector2,end:Vector2,wall:Rect2) -> float:
	var direction:=end-origin
	var near:=0.0
	var far:=1.0
	for axis in range(2):
		if absf(direction[axis])<0.00001:
			if origin[axis]<wall.position[axis] or origin[axis]>wall.end[axis]:return INF
		else:
			var first:float=(wall.position[axis]-origin[axis])/direction[axis]
			var second:float=(wall.end[axis]-origin[axis])/direction[axis]
			near=maxf(near,minf(first,second));far=minf(far,maxf(first,second))
			if near>far:return INF
	return near

func _update_bullets(delta:float) -> void:
	for i in range(bullets.size()-1,-1,-1):
		var bullet:Dictionary=bullets[i]
		var origin:Vector2=bullet.p
		var end:Vector2=origin+Vector2(bullet.v)*delta
		bullet.life=float(bullet.life)-delta
		var nearest:=INF
		var hit_enemy:=-1
		for wall in obstacles:nearest=minf(nearest,_segment_wall_t(origin,end,wall))
		if bool(bullet.enemy):
			var time:=_segment_circle_t(origin,end,player,16.0)
			if time<nearest:nearest=time;hit_enemy=-2
		else:
			for index in range(enemies.size()):
				var enemy:Dictionary=enemies[index]
				var time:=_segment_circle_t(origin,end,enemy.p,27.0 if str(enemy.kind)=="boss" else 18.0)
				if time<nearest:nearest=time;hit_enemy=index
		bullet.p=origin.lerp(end,nearest) if nearest<=1.0 else end
		if nearest<=1.0:
			if hit_enemy==-2:_damage(float(bullet.damage))
			elif hit_enemy>=0:
				var enemy:Dictionary=enemies[hit_enemy]
				enemy.hp=float(enemy.hp)-float(bullet.damage);enemy.flash=.11
				_burst(enemy.p,Color("f5d486"),3)
				if float(enemy.hp)<=0.0:_defeat(hit_enemy)
			bullets.remove_at(i)
		elif float(bullet.life)<=0.0 or not ARENA.grow(30).has_point(end):bullets.remove_at(i)

func _defeat(index: int) -> void:
	var enemy: Dictionary = enemies[index]
	var point: Vector2 = enemy.p
	if str(enemy.kind) == "boss":
		boss_defeated = true
	kills += 1
	events.append({"kind": "defeat", "p": point})
	_burst(point, Color("c4a3ce"), 9)
	if str(level.get("mode", "")) == "supply" and kills % 2 == 0:
		pickups.append({"p": point, "kind": "supply", "life": 600.0})
	elif kills % (3 if str(level.get("rule", "")) == "windfall" else 4) == 0:
		var kinds: Array = ["heart", "shield", "rapid", "spread"]
		pickups.append({"p": point, "kind": kinds[rng.randi_range(0, 3)], "life": 18.0})
	enemies.remove_at(index)

func _damage(amount: float) -> void:
	if invincible > 0.0 or shield_time > 0.0:
		return
	health = maxf(0.0, health - amount * (1.0 - float(stats.get("armor", 0.0))))
	invincible = 0.7
	events.append({"kind": "hurt", "p": player})
	_burst(player, Color("ed8973"), 7)

func _update_pickups(delta: float) -> void:
	for i in range(pickups.size() - 1, -1, -1):
		var pickup: Dictionary = pickups[i]
		pickup.life = float(pickup.life) - delta
		if Vector2(pickup.p).distance_to(player) < 30:
			match str(pickup.kind):
				"heart": health = minf(max_health, health + max_health * 0.27)
				"shield": shield_time = 5.0
				"rapid": rapid_time = 8.0
				"spread": spread_time = 8.0
				"supply": supplies += 1
			events.append({"kind": "pickup", "p": player, "item": pickup.kind})
			pickups.remove_at(i)
		elif float(pickup.life) <= 0.0:
			pickups.remove_at(i)

func _update_hazard(delta: float) -> void:
	hazard_clock += delta
	var hazard: String = str(level.get("hazard", "none"))
	if hazard == "none":
		return
	var phase: float = fmod(hazard_clock, 7.0)
	if phase >= 5.0 and phase <= 5.55:
		for point in hazard_points():
			if player.distance_to(point) < 43.0:
				_damage(12.0)

func hazard_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	var shape: int = int(level.get("layout", 0))
	points.append(Vector2(130 + (shape % 4) * 80, 355))
	if int(level.get("chapter", 1)) > 4:
		points.append(Vector2(410 - (shape % 4) * 75, 595))
	return points

func _burst(point: Vector2, color: Color, count: int) -> void:
	for i in range(count):
		if particles.size() >= 120:
			break
		particles.append({"p": point, "v": Vector2.RIGHT.rotated(rng.randf_range(0, TAU)) * rng.randf_range(20, 90), "life": rng.randf_range(0.2, 0.5), "color": color})

func _update_particles(delta: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		particles[i].life = float(particles[i].life) - delta
		particles[i].p = Vector2(particles[i].p) + Vector2(particles[i].v) * delta
		if float(particles[i].life) <= 0.0:
			particles.remove_at(i)

func objective_complete() -> bool:
	match str(level.get("mode", "clear")):
		"clear": return kills >= int(level.get("target", 5))
		"survive": return elapsed >= float(level.get("target", 30))
		"supply": return supplies >= int(level.get("target", 5))
		"hold": return hold_time >= float(level.get("target", 15))
		"duel": return boss_defeated
	return false

func progress_text() -> String:
	match str(level.get("mode", "clear")):
		"clear": return "%d / %d foes" % [kills, int(level.target)]
		"survive": return "%d / %d seconds" % [mini(int(elapsed), int(level.target)), int(level.target)]
		"supply": return "%d / %d supplies" % [supplies, int(level.target)]
		"hold": return "%d / %d seconds in the circle" % [int(hold_time), int(level.target)]
		"duel": return "Defeat the chapter guardian"
	return ""

func revive() -> bool:
	if result != "lost" or revived:
		return false
	revived = true
	health = max_health * 0.65
	invincible = 3.0
	result = ""
	for i in range(enemies.size() - 1, -1, -1):
		if Vector2(enemies[i].p).distance_to(player) < 100:
			enemies[i].p = _edge_spawn()
	bullets.clear()
	ammo = magazine
	reload_time = 0.0
	# A timed-out contract needs a real second chance, not an immediate second loss.
	level.time_limit = maxf(float(level.get("time_limit", 150.0)), elapsed + 30.0)
	return true
