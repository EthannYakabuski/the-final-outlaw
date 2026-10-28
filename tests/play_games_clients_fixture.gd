extends RefCounted
## Test-only SDK subclasses. Load this helper after autoload startup, not from
## the SceneTree --script entrypoint. No method here calls the native SDK.

class FakeSignIn extends PlayGamesSignInClient:
	var checks := 0
	var interactive_requests := 0
	func _ready() -> void: pass
	func is_authenticated() -> void: checks += 1
	func sign_in() -> void: interactive_requests += 1
	func complete(authenticated: bool) -> void: user_authenticated.emit(authenticated)

class FakeAchievements extends PlayGamesAchievementsClient:
	var unlocks: Array[String] = []
	var incremental_requests := 0
	var opened := 0
	func _ready() -> void: pass
	func unlock_achievement(achievement_id: String) -> void: unlocks.append(achievement_id)
	func show_achievements() -> void: opened += 1
	func increment_achievement(_achievement_id: String, _amount: int) -> void: incremental_requests += 1
	func set_achievement_steps(_achievement_id: String, _num_steps: int) -> void: incremental_requests += 1
	func complete(achievement_id: String, accepted: bool) -> void: achievement_unlocked.emit(accepted, achievement_id)

class FakeBoards extends PlayGamesLeaderboardsClient:
	var submissions: Array[Dictionary] = []
	var opened: Array[String] = []
	var opened_all := 0
	func _ready() -> void: pass
	func show_leaderboard(leaderboard_id: String) -> void: opened.append(leaderboard_id)
	func show_all_leaderboards() -> void: opened_all += 1
	func submit_score(leaderboard_id: String, score: int) -> void:
		submissions.append({"remote_id": leaderboard_id, "value": score})
	func complete(leaderboard_id: String, accepted: bool) -> void: score_submitted.emit(accepted, leaderboard_id)
	func count_for(remote_id: String) -> int:
		var result := 0
		for item in submissions:
			if str(item.remote_id) == remote_id: result += 1
		return result
	func latest_value(remote_id: String) -> int:
		for index in range(submissions.size() - 1, -1, -1):
			if str(submissions[index].remote_id) == remote_id: return int(submissions[index].value)
		return -1
