extends RefCounted
## Persistent progression. No advertising entitlement is manufactured here.

const VERSION = 1
const UPGRADE_CAP = 8
const DAILY_TARGETS = {"kills": 18, "wins": 2, "seconds": 90}
var coins: int = 120
var xp: int = 0
var eliminations: int = 0
var runs: int = 0
var campaign_wins: int = 0
var best_survival: int = 0
var best_seconds: int = 0
var completed: Dictionary = {}
var upgrades: Dictionary = {"power": 0, "heart": 0, "boots": 0, "magazine": 0, "reload": 0, "dash": 0, "armor": 0}
var unlocked: Dictionary = {}
var day: String = ""
var login_day: String = ""
var streak: int = 0
var daily: Dictionary = {"kills": 0, "wins": 0, "seconds": 0}
var daily_claimed: Dictionary = {}
var rewarded_day: String = ""
var settings: Dictionary = {"sound": true, "music": true}

func player_level() -> int:
	return 1 + int(floor(sqrt(float(xp) / 75.0)))

func level_xp(level: int) -> int:
	return maxi(0, level - 1) * maxi(0, level - 1) * 75

func add_xp(amount: int) -> int:
	var before: int = player_level()
	xp = mini(2000000000, xp + maxi(0, amount))
	var bonus: int = maxi(0, player_level() - before) * 50
	coins = mini(2000000000, coins + bonus)
	return bonus

func stats() -> Dictionary:
	return {"health": 100.0 + 12.0 * int(upgrades.heart), "damage": 5.0 + float(upgrades.power), "speed": 165.0 + 8.0 * int(upgrades.boots), "fire_interval": 0.30, "magazine": 20 + 4 * int(upgrades.magazine), "reload_seconds": 1.65 - 0.12 * int(upgrades.reload), "dash_cooldown": 2.1 - 0.13 * int(upgrades.dash), "armor": 0.035 * int(upgrades.armor)}

func upgrade_cost(key: String) -> int:
	if not upgrades.has(key) or int(upgrades[key]) >= UPGRADE_CAP:
		return -1
	return int(round(75.0 * pow(1.62, int(upgrades[key]))))

func buy_upgrade(key: String) -> bool:
	var cost: int = upgrade_cost(key)
	if cost < 0 or coins < cost:
		return false
	coins -= cost
	upgrades[key] = int(upgrades[key]) + 1
	return true

func open_level(number: int) -> bool:
	return number == 1 or (number > 1 and number <= 100 and completed.has(str(number - 1)))

func stars_total() -> int:
	var total: int = 0
	for value in completed.values():
		total += int(value)
	return total

func record_run(number: int, won: bool, kills: int, seconds: float, health_fraction: float, score: int, survival: bool = false) -> Dictionary:
	kills = clampi(kills, 0, 100000)
	var played: int = clampi(int(seconds), 0, 86400)
	var first: bool = won and not completed.has(str(number)) and not survival
	var reward: int = kills * 2
	var gained_xp: int = kills * 5 + mini(played / 4, 40)
	var stars: int = 0
	if won and not survival and number >= 1 and number <= 100:
		stars = 1 + int(health_fraction >= 0.35) + int(health_fraction >= 0.7)
		completed[str(number)] = maxi(stars, int(completed.get(str(number), 0)))
		campaign_wins += 1
		reward += (45 + number * 3) if first else 15
		gained_xp += (35 + number * 2) if first else 12
	if survival:
		best_survival = maxi(best_survival, maxi(0, score))
		best_seconds = maxi(best_seconds, played)
	eliminations += kills
	if kills > 0 or played >= 10:
		runs += 1
	coins = mini(2000000000, coins + reward)
	var level_bonus: int = add_xp(gained_xp)
	daily.kills = mini(1000000, int(daily.kills) + kills)
	daily.wins = mini(1000000, int(daily.wins) + int(won and not survival))
	daily.seconds = mini(1000000, int(daily.seconds) + played)
	return {"coins": reward + level_bonus, "xp": gained_xp, "stars": stars, "first": first, "level_bonus": level_bonus}

func roll_day(today: String) -> bool:
	if _valid_day(today).is_empty() or today <= day:
		return false
	day = today
	daily = {"kills": 0, "wins": 0, "seconds": 0}
	daily_claimed.clear()
	return true

func can_claim_login(today: String) -> bool:
	return not _valid_day(today).is_empty() and today >= day and today > login_day

func claim_login(today: String) -> int:
	if not can_claim_login(today):
		return 0
	roll_day(today)
	var yesterday: int = int(Time.get_unix_time_from_datetime_string(today + "T00:00:00")) - 86400
	var previous: int = int(Time.get_unix_time_from_datetime_string(login_day + "T00:00:00")) if not login_day.is_empty() else 0
	streak = (streak % 7) + 1 if previous == yesterday else 1
	login_day = today
	var prize: int = [35, 45, 60, 75, 95, 125, 200][streak - 1]
	coins += prize
	add_xp(10 + streak * 3)
	return prize

func claim_quest(key: String) -> int:
	if not DAILY_TARGETS.has(key) or daily_claimed.has(key):
		return 0
	if int(daily.get(key, 0)) < int(DAILY_TARGETS[key]):
		return 0
	daily_claimed[key] = true
	coins += 80
	add_xp(30)
	return 80

func reward_crate(today: String) -> bool:
	if _valid_day(today).is_empty() or today < day or today <= rewarded_day:
		return false
	rewarded_day = today
	coins += 120
	return true

func metrics() -> Dictionary:
	return {"kills": eliminations, "levels": completed.size(), "stars": stars_total(), "level": player_level(), "survival": best_survival, "seconds": best_seconds, "runs": runs, "upgrades": _total_upgrades(), "streak": streak}

func data() -> Dictionary:
	return {"version": VERSION, "coins": coins, "xp": xp, "eliminations": eliminations, "runs": runs, "campaign_wins": campaign_wins, "best_survival": best_survival, "best_seconds": best_seconds, "completed": completed.duplicate(true), "upgrades": upgrades.duplicate(true), "unlocked": unlocked.duplicate(true), "day": day, "login_day": login_day, "streak": streak, "daily": daily.duplicate(true), "daily_claimed": daily_claimed.duplicate(true), "rewarded_day": rewarded_day, "settings": settings.duplicate(true)}

func load_data(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	coins = _bounded(raw.get("coins", 120), 0, 2000000000)
	xp = _bounded(raw.get("xp", 0), 0, 2000000000)
	eliminations = _bounded(raw.get("eliminations", 0), 0, 2000000000)
	runs = _bounded(raw.get("runs", 0), 0, 2000000000)
	campaign_wins = _bounded(raw.get("campaign_wins", 0), 0, 2000000000)
	best_survival = _bounded(raw.get("best_survival", 0), 0, 2000000000)
	best_seconds = _bounded(raw.get("best_seconds", 0), 0, 86400)
	completed.clear()
	if raw.get("completed") is Dictionary:
		for key in raw.completed:
			var level_number: int = str(key).to_int()
			if level_number >= 1 and level_number <= 100:
				completed[str(level_number)] = _bounded(raw.completed[key], 1, 3)
	if raw.get("upgrades") is Dictionary:
		for key in upgrades:
			upgrades[key] = _bounded(raw.upgrades.get(key, 0), 0, UPGRADE_CAP)
	if raw.get("unlocked") is Dictionary:
		for key in raw.unlocked:
			if raw.unlocked[key] == true:
				unlocked[str(key)] = true
	day = _valid_day(str(raw.get("day", "")))
	login_day = _valid_day(str(raw.get("login_day", "")))
	rewarded_day = _valid_day(str(raw.get("rewarded_day", "")))
	streak = _bounded(raw.get("streak", 0), 0, 7)
	if raw.get("daily") is Dictionary:
		for key in daily:
			daily[key] = _bounded(raw.daily.get(key, 0), 0, 1000000)
	if raw.get("daily_claimed") is Dictionary:
		for key in DAILY_TARGETS:
			if raw.daily_claimed.get(key, false) == true:
				daily_claimed[key] = true
	if raw.get("settings") is Dictionary:
		settings.sound = bool(raw.settings.get("sound", true))
		settings.music = bool(raw.settings.get("music", true))
	return true

func _bounded(value: Variant, low: int, high: int) -> int:
	if value is int or value is float:
		return clampi(int(value), low, high)
	return low

func _valid_day(value: String) -> String:
	if value.length() != 10 or value[4] != "-" or value[7] != "-": return ""
	var parts: PackedStringArray = value.split("-")
	for part in parts:
		if not part.is_valid_int(): return ""
	var year: int = parts[0].to_int()
	var month: int = parts[1].to_int()
	var date: int = parts[2].to_int()
	if year < 1970 or year > 9999 or month < 1 or month > 12: return ""
	var lengths: Array = [31, 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	return value if date >= 1 and date <= int(lengths[month - 1]) else ""

func _total_upgrades() -> int:
	var total := 0
	for value in upgrades.values(): total += int(value)
	return total
