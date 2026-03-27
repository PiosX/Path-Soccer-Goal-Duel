extends Node

# ————— PLAYFAB —————
const PLAYFAB_URL = "https://139617.playfabapi.com"
const PLAYFAB_TITLE_ID = "139617"
const LEADERBOARD_NAME = "rating_score"

# ————— TICKET W PAMIĘCI (aktualny, odświeżony) —————
var _cached_ticket: String = ""

# ——————————————————————————————————————————
#  ODŚWIEŻANIE SESJI
#  - Goście: LoginWithCustomID (device_id)
#  - Konta z hasłem: LoginWithCustomID też działa, bo PlayFab
#    powiązał CustomID z kontem podczas rejestracji na tym urządzeniu.
#    Jeśli jednak device_id nie ma w cfg (np. stara sesja), zostawiamy
#    stary ticket i kierujemy do formularza logowania.
# ——————————————————————————————————————————
func refresh_session(cfg: ConfigFile) -> void:
	var device_id = cfg.get_value("session", "device_id", "")

	# Brak device_id = nie możemy odświeżyć przez CustomID
	# (np. stara sesja zapisana przed tą zmianą)
	if device_id == "":
		_cached_ticket = cfg.get_value("session", "ticket", "")
		return

	var body = {
		"TitleId":  PLAYFAB_TITLE_ID,
		"CustomId": device_id,
		"CreateAccount": false
	}
	var headers = ["Content-Type: application/json", "Accept-Encoding: identity"]
	var http = HTTPRequest.new()
	add_child(http)
	http.request(PLAYFAB_URL + "/Client/LoginWithCustomID",
		headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	var response = await http.request_completed
	http.queue_free()

	if response[1] != 200:
		_cached_ticket = cfg.get_value("session", "ticket", "")
		return

	var json = JSON.new()
	if json.parse(response[3].get_string_from_utf8()) != OK:
		_cached_ticket = cfg.get_value("session", "ticket", "")
		return

	var parsed = json.get_data()
	if parsed.get("code", 0) != 200:
		_cached_ticket = cfg.get_value("session", "ticket", "")
		return

	var new_ticket = parsed.get("data", {}).get("SessionTicket", "")
	if new_ticket != "":
		_cached_ticket = new_ticket
		cfg.set_value("session", "ticket", new_ticket)
		cfg.save("user://session.cfg")
		# Pobierz dane gracza z PlayFab (gold, current_level itp.)
		await _fetch_and_sync_player_data(new_ticket, cfg)
	else:
		_cached_ticket = cfg.get_value("session", "ticket", "")

# ——————————————————————————————————————————
#  SYNC DANYCH Z PLAYFAB (gold, current_level)
# ——————————————————————————————————————————
func _fetch_and_sync_player_data(ticket: String, cfg: ConfigFile) -> void:
	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-Authorization: " + ticket
	]
	var body = { "Keys": ["gold", "score", "wins", "losses", "current_level"] }
	var http = HTTPRequest.new()
	add_child(http)
	http.request(PLAYFAB_URL + "/Client/GetUserData",
		headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	var response = await http.request_completed
	http.queue_free()

	if response[1] != 200:
		return
	var json = JSON.new()
	if json.parse(response[3].get_string_from_utf8()) != OK:
		return
	var parsed = json.get_data()
	if parsed.get("code", 0) != 200:
		return

	var data = parsed.get("data", {}).get("Data", {})
	var gold_str  = data.get("gold",          {}).get("Value", "")
	var score_str = data.get("score",         {}).get("Value", "")
	var wins_str  = data.get("wins",          {}).get("Value", "")
	var losses_str= data.get("losses",        {}).get("Value", "")
	var level_str = data.get("current_level", {}).get("Value", "")

	# Aktualizuj session.cfg danymi z PlayFab (PlayFab = źródło prawdy)
	if gold_str   != "": cfg.set_value("session", "gold",          int(gold_str))
	if score_str  != "": cfg.set_value("session", "score",         int(score_str))
	if wins_str   != "": cfg.set_value("session", "wins",          int(wins_str))
	if losses_str != "": cfg.set_value("session", "losses",        int(losses_str))
	if level_str  != "": cfg.set_value("session", "current_level", int(level_str))
	cfg.save("user://session.cfg")

# ——————————————————————————————————————————
#  POBIERZ AKTUALNY TICKET
#  Używaj tej funkcji zamiast czytać ticket z cfg bezpośrednio
# ——————————————————————————————————————————
func get_ticket() -> String:
	if _cached_ticket != "":
		return _cached_ticket
	var cfg = ConfigFile.new()
	if cfg.load("user://session.cfg") == OK:
		return cfg.get_value("session", "ticket", "")
	return ""


var current_level_data: Dictionary = {}
var vs_ai: bool = true
var current_level_index: int = 0

# ——————————————————————————————————————————
#  POSTĘP POZIOMÓW
# ——————————————————————————————————————————
func get_current_level() -> int:
	var cfg = ConfigFile.new()
	if cfg.load("user://session.cfg") != OK:
		return 1
	return cfg.get_value("session", "current_level", 1)

func set_current_level(level: int) -> void:
	var cfg = ConfigFile.new()
	cfg.load("user://session.cfg")
	cfg.set_value("session", "current_level", level)
	cfg.save("user://session.cfg")

# ——————————————————————————————————————————
#  URUCHOM POZIOM
# ——————————————————————————————————————————
func launch_level(level_index: int) -> void:
	var path = "res://levels/level_%03d.json" % level_index
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("PlayerData: brak pliku poziomu: " + path)
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("PlayerData: blad parsowania JSON: " + path)
		return
	current_level_data  = json.get_data()
	vs_ai               = true
	current_level_index = level_index
	get_tree().change_scene_to_file("res://scenes/game.tscn")

# ——————————————————————————————————————————
#  WYGRANA W POZIOMIE
# ——————————————————————————————————————————
func on_level_win(level_index: int) -> void:
	var current = get_current_level()
	if level_index >= current:
		set_current_level(level_index + 1)

# ——————————————————————————————————————————
#  WZÓR RANKINGOWY
#  wins * 1000 + win_ratio * 500 + score / 1000
#  Win/lose TYLKO z PvP, score z kampanii jako tiebreaker
# ——————————————————————————————————————————
func _calc_rating(wins: int, losses: int, score: int) -> int:
	var total = wins + losses
	var win_ratio = float(wins) / float(total) if total > 0 else 0.0
	return int(wins * 1000 + win_ratio * 500 + score / 1000)

# ——————————————————————————————————————————
#  GŁÓWNA FUNKCJA — wywołaj po każdej grze
# ——————————————————————————————————————————
func save_game_result(is_win: bool, reward: int, game_score: int, vs_ai_mode: bool) -> void:
	var cfg = ConfigFile.new()
	if cfg.load("user://session.cfg") != OK:
		return
	var ticket = get_ticket()
	if ticket == "":
		return

	# Awansuj poziom jeśli wygrana w kampanii
	if vs_ai_mode and is_win:
		on_level_win(current_level_index)

	var gold   = cfg.get_value("session", "gold",   0)
	var score  = cfg.get_value("session", "score",  0)
	var wins   = cfg.get_value("session", "wins",   0)
	var losses = cfg.get_value("session", "losses", 0)

	gold  += reward
	if is_win:
		score += game_score

	if not vs_ai_mode:  # win/lose TYLKO z PvP
		if is_win:
			wins += 1
		else:
			losses += 1

	cfg.set_value("session", "gold",   gold)
	cfg.set_value("session", "score",  score)
	cfg.set_value("session", "wins",   wins)
	cfg.set_value("session", "losses", losses)
	cfg.save("user://session.cfg")

	# Policz nowy rating i wyślij do PlayFab
	# Zapisz też aktualny poziom (mógł się zmienić przez on_level_win wyżej)
	var updated_cfg = ConfigFile.new()
	updated_cfg.load("user://session.cfg")
	var current_level = updated_cfg.get_value("session", "current_level", 1)

	var rating = _calc_rating(wins, losses, score)
	_push_to_playfab(ticket, gold, score, wins, losses, rating, current_level)

# ——————————————————————————————————————————
#  PLAYFAB — UserData + Statystyka rankingowa
# ——————————————————————————————————————————
func _push_to_playfab(ticket: String, gold: int, score: int,
		wins: int, losses: int, rating: int, current_level: int = 1) -> void:
	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-Authorization: " + ticket
	]

	# 1. Zapisz surowe dane gracza (gold, score, wins, losses, current_level)
	var data_body = {
		"Data": {
			"gold":          str(gold),
			"score":         str(score),
			"wins":          str(wins),
			"losses":        str(losses),
			"current_level": str(current_level),
		}
	}
	var http1 = HTTPRequest.new()
	add_child(http1)
	http1.request(PLAYFAB_URL + "/Client/UpdateUserData",
		headers, HTTPClient.METHOD_POST, JSON.stringify(data_body))
	await http1.request_completed
	http1.queue_free()

	# 2. Zaktualizuj statystykę rankingową (leaderboard)
	var stat_body = {
		"Statistics": [
			{ "StatisticName": LEADERBOARD_NAME, "Value": rating },
			{ "StatisticName": "wins",            "Value": wins  },
			{ "StatisticName": "losses",          "Value": losses },
			{ "StatisticName": "score",           "Value": score  },
		]
	}
	var http2 = HTTPRequest.new()
	add_child(http2)
	http2.request(PLAYFAB_URL + "/Client/UpdatePlayerStatistics",
		headers, HTTPClient.METHOD_POST, JSON.stringify(stat_body))
	await http2.request_completed
	http2.queue_free()
