extends Node

# ————— PLAYFAB —————
const PLAYFAB_URL = "https://139617.playfabapi.com"
const PLAYFAB_TITLE_ID = "139617"
const LEADERBOARD_NAME = "rating_score"
var _my_moves_cache: Array = []

# ————— TICKET W PAMIĘCI (aktualny, odświeżony) —————
var _cached_ticket: String = ""
const MAX_LEVEL = 80
# ——————————————————————————————————————————
#  ODŚWIEŻANIE SESJI
# ——————————————————————————————————————————
func refresh_session(cfg: ConfigFile) -> void:
	var device_id = cfg.get_value("session", "device_id", "")

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
		# ← DODAJ entity_token
		var entity_token = parsed.get("data", {}).get("EntityToken", {}).get("EntityToken", "")
		var entity_id = parsed.get("data", {}).get("EntityToken", {}).get("Entity", {}).get("Id", "")
		if entity_token != "":
			cfg.set_value("session", "entity_token", entity_token)
		if entity_id != "":
			cfg.set_value("session", "entity_id", entity_id)
		cfg.save("user://session.cfg")
		await _fetch_and_sync_player_data(new_ticket, cfg)
	else:
		_cached_ticket = cfg.get_value("session", "ticket", "")

# ——————————————————————————————————————————
#  SYNC DANYCH Z PLAYFAB (gold, current_level, skiny)
# ——————————————————————————————————————————
func _fetch_and_sync_player_data(ticket: String, cfg: ConfigFile) -> void:
	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-Authorization: " + ticket
	]
	var body = { "Keys": ["gold", "score", "wins", "losses", "current_level", "owned_skins", "equipped_skin"] }
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
	var gold_str         = data.get("gold",          {}).get("Value", "")
	var score_str        = data.get("score",         {}).get("Value", "")
	var wins_str         = data.get("wins",          {}).get("Value", "")
	var losses_str       = data.get("losses",        {}).get("Value", "")
	var level_str        = data.get("current_level", {}).get("Value", "")
	var owned_skins_str  = data.get("owned_skins",   {}).get("Value", "")
	var equipped_str     = data.get("equipped_skin", {}).get("Value", "")

	# Aktualizuj session.cfg danymi z PlayFab (PlayFab = źródło prawdy)
	# Jeśli gold nie istnieje w PlayFab — nowe konto, zainicjalizuj dane
	var is_new_account = (gold_str == "")
	if gold_str != "": cfg.set_value("session", "gold", int(gold_str))
	else: cfg.set_value("session", "gold", 20)
		
	if score_str  != "": cfg.set_value("session", "score",  int(score_str))
	else: cfg.set_value("session", "score", 0)
	
	if wins_str   != "": cfg.set_value("session", "wins",   int(wins_str))
	else: cfg.set_value("session", "wins", 0)

	if losses_str != "": cfg.set_value("session", "losses", int(losses_str))
	else: cfg.set_value("session", "losses", 0)

	if level_str  != "": cfg.set_value("session", "current_level", int(level_str))
	else: cfg.set_value("session", "current_level", 1)

	# Skiny — PlayFab przechowuje jako "0,1,5" (indeksy posiadanych skinów)
	if owned_skins_str != "":
		if owned_skins_str.begins_with("["):
			cfg.set_value("session", "owned_skins", "0")
		else:
			cfg.set_value("session", "owned_skins", owned_skins_str)
	else:
		if cfg.get_value("session", "owned_skins", "") == "":
			cfg.set_value("session", "owned_skins", "0")

	if equipped_str != "":
		cfg.set_value("session", "equipped_skin", int(equipped_str))
	else:
		if cfg.get_value("session", "equipped_skin", -1) == -1:
			cfg.set_value("session", "equipped_skin", 0)

	cfg.save("user://session.cfg")

	# Nowe konto — wyślij domyślne dane do PlayFab
	if is_new_account and ticket != "":
		await _init_default_player_data(ticket)

# ——————————————————————————————————————————
#  POBIERZ AKTUALNY TICKET
# ——————————————————————————————————————————
func _init_default_player_data(ticket: String) -> void:
	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-Authorization: " + ticket
	]
	var body = {
		"Data": {
			"gold":          "20",
			"score":         "0",
			"wins":          "0",
			"losses":        "0",
			"current_level": "1",
			"owned_skins":   "0",
			"equipped_skin": "0"
		}
	}
	var http = HTTPRequest.new()
	add_child(http)
	http.request(PLAYFAB_URL + "/Client/UpdateUserData",
		headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	await http.request_completed
	http.queue_free()

func get_ticket() -> String:
	if _cached_ticket != "":
		return _cached_ticket
	var cfg = ConfigFile.new()
	if cfg.load("user://session.cfg") == OK:
		return cfg.get_value("session", "ticket", "")
	return ""

# ——————————————————————————————————————————
#  SKINY — HELPER: aktualnie założony skin (indeks 0-19)
# ——————————————————————————————————————————
func get_equipped_skin() -> int:
	var cfg = ConfigFile.new()
	if cfg.load("user://session.cfg") != OK:
		return 0
	return cfg.get_value("session", "equipped_skin", 0)

# ——————————————————————————————————————————
#  SKINY — WYŚLIJ DO PLAYFAB
#  Wywołaj po zakupie lub zmianie skina
# ——————————————————————————————————————————
func save_skin_data_to_playfab() -> void:
	var ticket = get_ticket()
	if ticket == "":
		return
	var cfg = ConfigFile.new()
	if cfg.load("user://session.cfg") != OK:
		return

	var owned_skins = cfg.get_value("session", "owned_skins", "0")
	var equipped_skin = cfg.get_value("session", "equipped_skin", 0)
	var gold = cfg.get_value("session", "gold", 0)

	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-Authorization: " + ticket
	]
	var data_body = {
		"Data": {
			"owned_skins":   owned_skins,
			"equipped_skin": str(equipped_skin),
			"gold":          str(gold),
		}
	}
	var http = HTTPRequest.new()
	add_child(http)
	http.request(PLAYFAB_URL + "/Client/UpdateUserData",
		headers, HTTPClient.METHOD_POST, JSON.stringify(data_body))
	await http.request_completed
	http.queue_free()


var current_level_data: Dictionary = {}
var vs_ai: bool = true
var current_level_index: int = 0

# ——————————————————————————————————————————
#  ONLINE DUEL — stan
# ——————————————————————————————————————————
var online_mode: bool = false
var online_opponent_name: String = ""
var online_opponent_rank: String = ""
var my_rank: String = "#0"
var player1_is_me: bool = true
var player1_decided: bool = false
var _matchmaking_ticket_id: String = ""
var _matchmaking_active: bool = false

const MATCHMAKING_QUEUE = "StandardQueue"
const MATCHMAKING_TIMEOUT = 30.0

signal matchmaking_found()
signal matchmaking_timeout()

# ——————————————————————————————————————————
#  POBIERZ MOJĄ RANGĘ Z LEADERBOARD
# ——————————————————————————————————————————
func fetch_my_rank() -> void:
	var ticket = get_ticket()
	if ticket == "":
		my_rank = "#0"
		return
	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-Authorization: " + ticket
	]
	var body = { "StatisticName": LEADERBOARD_NAME, "MaxResultsCount": 1 }
	var http = HTTPRequest.new()
	add_child(http)
	http.request(PLAYFAB_URL + "/Client/GetLeaderboardAroundPlayer",
		headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	var response = await http.request_completed
	http.queue_free()
	if response[1] != 200:
		my_rank = "#0"
		return
	var json = JSON.new()
	if json.parse(response[3].get_string_from_utf8()) != OK:
		my_rank = "#0"
		return
	var board = json.get_data().get("data", {}).get("Leaderboard", [])
	my_rank = "#" + str(int(board[0].get("Position", 0)) + 1) if board.size() > 0 else "#0"

# ——————————————————————————————————————————
#  URUCHOM ONLINE DUEL
# ——————————————————————————————————————————
func launch_online_duel() -> void:
	online_mode = true
	player1_decided = false
	current_level_data = {}
	current_level_index = 0
	vs_ai = (online_opponent_name == "")
	SceneTransition.go_to("res://scenes/match_intro.tscn")

# ——————————————————————————————————————————
#  MATCHMAKING
# ——————————————————————————————————————————
func start_matchmaking() -> bool:
	var entity_token = get_entity_token()
	print("=== entity_token: '", entity_token, "'")
	
	# Brak tokenu — spróbuj odświeżyć sesję
	if entity_token == "":
		print("=== brak entity_token, odświeżam sesję...")
		var cfg = ConfigFile.new()
		if cfg.load("user://session.cfg") == OK:
			await refresh_session(cfg)
			entity_token = get_entity_token()
			print("=== entity_token po refresh: '", entity_token, "'")
	
	if entity_token == "":
		return false
	
	_matchmaking_active = true
	_matchmaking_ticket_id = ""
	online_opponent_name = ""
	online_opponent_rank = ""
	_create_matchmaking_ticket(entity_token)
	return true

func stop_matchmaking() -> void:
	_matchmaking_active = false
	_matchmaking_ticket_id = ""
	if matchmaking_found.is_connected(_dummy_slot):
		pass

func _create_matchmaking_ticket(ticket: String) -> void:
	var cfg = ConfigFile.new()
	cfg.load("user://session.cfg")
	var nick = cfg.get_value("session", "nick", "Player")
	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-EntityToken: " + ticket
	]
	var entity_id = get_entity_id()
	var cfg2 = ConfigFile.new()
	cfg2.load("user://session.cfg")
	var my_playfab_id = cfg2.get_value("session", "playfab_id", "")

	var body = {
		"Creator": {
			"Entity": { "Type": "title_player_account", "Id": entity_id },
			"Attributes": { "DataObject": { 
				"nick": nick, 
				"rank": my_rank,
				"playfab_id": my_playfab_id  # ← DODAJ
			}}
		},
		"GiveUpAfterSeconds": int(MATCHMAKING_TIMEOUT),
		"QueueName": MATCHMAKING_QUEUE
	}
	var http = HTTPRequest.new()
	add_child(http)
	print("=== matchmaking body: ", JSON.stringify(body))
	http.request(PLAYFAB_URL + "/Match/CreateMatchmakingTicket",
		headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	var response = await http.request_completed
	http.queue_free()
	print("=== matchmaking response: ", response[3].get_string_from_utf8())

	if not _matchmaking_active:
		return
	if response[1] != 200:
		push_warning("PlayerData: matchmaking API error %d — bot fallback" % response[1])
		await get_tree().create_timer(29.0).timeout
		if not _matchmaking_active: return
		_matchmaking_active = false
		matchmaking_timeout.emit()
		return

	var json = JSON.new()
	if json.parse(response[3].get_string_from_utf8()) != OK:
		_matchmaking_active = false
		matchmaking_timeout.emit()
		return
	var ticket_id = json.get_data().get("data", {}).get("TicketId", "")
	if ticket_id == "":
		_matchmaking_active = false
		matchmaking_timeout.emit()
		return
	_matchmaking_ticket_id = ticket_id
	_poll_matchmaking(ticket)

func _poll_matchmaking(auth_ticket: String) -> void:
	var elapsed = 0.0
	while _matchmaking_active and _matchmaking_ticket_id != "":
		await get_tree().create_timer(6.0).timeout
		if not _matchmaking_active: return
		elapsed += 3.0
		var headers = [
			"Content-Type: application/json",
			"Accept-Encoding: identity",
			"X-EntityToken: " + auth_ticket
		]
		var http = HTTPRequest.new()
		add_child(http)
		http.request(
			PLAYFAB_URL + "/Match/GetMatchmakingTicket",
			headers, HTTPClient.METHOD_POST,
			JSON.stringify({
				"TicketId": _matchmaking_ticket_id,
				"QueueName": MATCHMAKING_QUEUE
			}))
		var response = await http.request_completed
		http.queue_free()
		if not _matchmaking_active: return
		if response[1] != 200:
			print("=== poll błąd HTTP: ", response[1])
			print("=== body: ", response[3].get_string_from_utf8())
			if elapsed >= MATCHMAKING_TIMEOUT:
				_matchmaking_active = false
				matchmaking_timeout.emit()
			continue
		var json = JSON.new()
		if json.parse(response[3].get_string_from_utf8()) != OK: continue
		var data = json.get_data().get("data", {})
		var status = data.get("Status", "")
		print("=== matchmaking status: ", status)
		print("=== full data: ", data)
		if status == "Matched":
			var match_id = data.get("MatchId", "")
			print("=== MatchId: ", match_id)
			# Pobierz szczegóły meczu
			var match_http = HTTPRequest.new()
			add_child(match_http)
			match_http.request(
				PLAYFAB_URL + "/Match/GetMatch",
				headers, HTTPClient.METHOD_POST,
				JSON.stringify({
					"MatchId": match_id,
					"QueueName": MATCHMAKING_QUEUE,
					"ReturnMemberAttributes": true
				}))
			var match_response = await match_http.request_completed
			match_http.queue_free()
			print("=== GetMatch response: ", match_response[3].get_string_from_utf8())
			var match_json = JSON.new()
			if match_json.parse(match_response[3].get_string_from_utf8()) == OK:
				var match_data = match_json.get_data().get("data", {})
				var match_members = match_data.get("Members", [])
				var my_id_cfg = ConfigFile.new()
				my_id_cfg.load("user://session.cfg")
				var my_entity_id = my_id_cfg.get_value("session", "entity_id", "")
				for member in match_members:
					var member_id = member.get("Entity", {}).get("Id", "")
					if member_id != my_entity_id:
						var attrs = member.get("Attributes", {}).get("DataObject", {})
						online_opponent_name = attrs.get("nick", "Rival")
						online_opponent_rank = attrs.get("rank", "#0")
						var opponent_playfab_id = attrs.get("playfab_id", "")
						my_id_cfg.set_value("session", "opponent_playfab_id", opponent_playfab_id)
						my_id_cfg.save("user://session.cfg")
						online_match_id = match_id
						break
			_matchmaking_active = false
			matchmaking_found.emit()
			return
		elif status == "Cancelled" or status == "Failed":
			_matchmaking_active = false
			matchmaking_timeout.emit()
			return
		elif elapsed >= MATCHMAKING_TIMEOUT:
			_cancel_matchmaking_ticket(auth_ticket)
			_matchmaking_active = false
			matchmaking_timeout.emit()
			return

func _cancel_matchmaking_ticket(auth_ticket: String) -> void:
	if _matchmaking_ticket_id == "": return
	var headers = ["Content-Type: application/json", "Accept-Encoding: identity",
		"X-Authorization: " + auth_ticket]
	var http = HTTPRequest.new()
	add_child(http)
	http.request(PLAYFAB_URL + "/Match/CancelMatchmakingTicket", headers,
		HTTPClient.METHOD_POST, JSON.stringify({"QueueName": MATCHMAKING_QUEUE, "TicketId": _matchmaking_ticket_id}))
	await http.request_completed
	http.queue_free()
	_matchmaking_ticket_id = ""

func _dummy_slot(): pass

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
	SceneTransition.go_to("res://scenes/game.tscn")

# ——————————————————————————————————————————
#  OPUSZCZENIE GRY
# ——————————————————————————————————————————
func leave_game() -> void:
	if online_mode and not vs_ai:
		save_game_result(false, 0, 0, false)
	online_mode = false
	SceneTransition.go_to("res://scenes/play.tscn")

func on_level_win(level_index: int) -> void:
	var current = get_current_level()
	if level_index >= current:
		set_current_level(mini(level_index + 1, MAX_LEVEL))

# ——————————————————————————————————————————
#  WZÓR RANKINGOWY
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

	if vs_ai_mode and is_win:
		on_level_win(current_level_index)

	var gold   = cfg.get_value("session", "gold",   0)
	var score  = cfg.get_value("session", "score",  0)
	var wins   = cfg.get_value("session", "wins",   0)
	var losses = cfg.get_value("session", "losses", 0)

	gold  += reward
	if is_win:
		score += game_score

	if not vs_ai_mode:
		if is_win:
			wins += 1
		else:
			losses += 1

	cfg.set_value("session", "gold",   gold)
	cfg.set_value("session", "score",  score)
	cfg.set_value("session", "wins",   wins)
	cfg.set_value("session", "losses", losses)
	cfg.save("user://session.cfg")

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

	var cfg = ConfigFile.new()
	cfg.load("user://session.cfg")
	var owned_skins  = cfg.get_value("session", "owned_skins",   "0")
	var equipped_skin = cfg.get_value("session", "equipped_skin", 0)

	# 1. Zapisz surowe dane gracza
	var data_body = {
		"Data": {
			"gold":          str(gold),
			"score":         str(score),
			"wins":          str(wins),
			"losses":        str(losses),
			"current_level": str(current_level),
			"owned_skins":   owned_skins,
			"equipped_skin": str(equipped_skin),
		}
	}
	var http1 = HTTPRequest.new()
	add_child(http1)
	http1.request(PLAYFAB_URL + "/Client/UpdateUserData",
		headers, HTTPClient.METHOD_POST, JSON.stringify(data_body))
	await http1.request_completed
	http1.queue_free()

	# 2. Zaktualizuj statystykę rankingową
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
	
func add_gold(amount: int) -> void:
	var cfg = ConfigFile.new()
	cfg.load("user://session.cfg")
	var gold = cfg.get_value("session", "gold", 0)
	gold += amount
	cfg.set_value("session", "gold", gold)
	cfg.save("user://session.cfg")
	# Zapisz też na PlayFab
	var ticket = get_ticket()
	if ticket != "":
		var score = cfg.get_value("session", "score", 0)
		var wins = cfg.get_value("session", "wins", 0)
		var losses = cfg.get_value("session", "losses", 0)
		var rating = _calc_rating(wins, losses, score)
		var level = get_current_level()
		_push_to_playfab(ticket, gold, score, wins, losses, rating, level)

func get_entity_token() -> String:
	var cfg = ConfigFile.new()
	if cfg.load("user://session.cfg") == OK:
		var token = cfg.get_value("session", "entity_token", "")
		print("=== get_entity_token: '", token.substr(0, 20), "...'")
		return token
	return ""

func get_entity_id() -> String:
	var cfg = ConfigFile.new()
	if cfg.load("user://session.cfg") == OK:
		return cfg.get_value("session", "entity_id", "")
	return ""

# ══════════════════════════════════════════
#  ONLINE GAME SYNC
# ══════════════════════════════════════════

var online_match_id: String = ""
var online_move_index: int = 0  # ile ruchów już zaaplikowałem od przeciwnika

func _get_my_move_key() -> String:
	var role = "p1" if player1_is_me else "p2"
	return "m" + online_match_id.replace("-", "").left(16) + "_" + role

func _get_opponent_move_key() -> String:
	var role = "p2" if player1_is_me else "p1"
	return "m" + online_match_id.replace("-", "").left(16) + "_" + role

func push_online_move(from: Vector2i, to: Vector2i) -> void:
	var ticket = get_ticket()
	if ticket == "" or online_match_id == "": return
	var key = _get_my_move_key()
	print("=== push_online_move key: ", key, " from: ", from, " to: ", to)
	
	_my_moves_cache.append({
		"fx": from.x, "fy": from.y,
		"tx": to.x, "ty": to.y
	})
	
	# Trzymaj tylko ostatnie 50 ruchów
	if _my_moves_cache.size() > 50:
		_my_moves_cache = _my_moves_cache.slice(_my_moves_cache.size() - 50)
	
	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-Authorization: " + ticket
	]
	var http = HTTPRequest.new()
	add_child(http)
	http.request(PLAYFAB_URL + "/Client/UpdateUserData",
		headers, HTTPClient.METHOD_POST,
		JSON.stringify({"Data": {key: JSON.stringify(_my_moves_cache)}, "Permission": "Public"}))
	await http.request_completed
	http.queue_free()

func _get_my_moves() -> Array:
	var ticket = get_ticket()
	if ticket == "": return []
	var key = _get_my_move_key()
	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-Authorization: " + ticket
	]
	var http = HTTPRequest.new()
	add_child(http)
	http.request(PLAYFAB_URL + "/Client/GetUserData",
		headers, HTTPClient.METHOD_POST,
		JSON.stringify({"Keys": [key]}))
	var response = await http.request_completed
	http.queue_free()
	if response[1] != 200: return []
	var json = JSON.new()
	if json.parse(response[3].get_string_from_utf8()) != OK: return []
	var val = json.get_data().get("data", {}).get("Data", {}).get(key, {}).get("Value", "")
	if val == "": return []
	var json2 = JSON.new()
	if json2.parse(val) != OK: return []
	return json2.get_data()

func poll_opponent_moves() -> Array:
	var ticket = get_ticket()
	if ticket == "" or online_match_id == "": return []
	var cfg = ConfigFile.new()
	cfg.load("user://session.cfg")
	var opponent_id = cfg.get_value("session", "opponent_playfab_id", "")
	if opponent_id == "": return []
	var key = _get_opponent_move_key()
	print("=== polling opponent key: ", key, " opponent_id: ", opponent_id)
	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-Authorization: " + ticket
	]
	var http = HTTPRequest.new()
	add_child(http)
	# Prawidłowy endpoint do pobierania publicznych danych innego gracza
	http.request(PLAYFAB_URL + "/Client/GetUserData",
		headers, HTTPClient.METHOD_POST,
		JSON.stringify({
			"PlayFabId": opponent_id,
			"Keys": [key]
		}))
	var response = await http.request_completed
	http.queue_free()
	print("=== poll response: ", response[1], " body: ", response[3].get_string_from_utf8().left(200))
	if response[1] != 200: return []
	var json = JSON.new()
	if json.parse(response[3].get_string_from_utf8()) != OK: return []
	var val = json.get_data().get("data", {}).get("Data", {}).get(key, {}).get("Value", "")
	if val == "": return []
	var json2 = JSON.new()
	if json2.parse(val) != OK: return []
	var all_moves: Array = json2.get_data()
	if online_move_index > all_moves.size():
		online_move_index = all_moves.size()
		return []
	var new_moves = all_moves.slice(online_move_index)
	online_move_index = all_moves.size()
	return new_moves

func reset_online_game(match_id: String) -> void:
	online_match_id = match_id
	online_move_index = 0
	_my_moves_cache = []
	# Nie czyść natychmiast — zamiast tego zapisz pusty array tylko raz
	# żeby przeciwnik wiedział że jesteś gotowy
	var ticket = get_ticket()
	if ticket == "": return
	var key = _get_my_move_key()
	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-Authorization: " + ticket
	]
	var http = HTTPRequest.new()
	add_child(http)
	http.request(PLAYFAB_URL + "/Client/UpdateUserData",
		headers, HTTPClient.METHOD_POST,
		JSON.stringify({"Data": {key: "[]"}, "Permission": "Public"}))
	await http.request_completed
	http.queue_free()
	print("=== reset_online_game done, key: ", key)

func push_forfeit() -> void:
	var ticket = get_ticket()
	if ticket == "" or online_match_id == "": return
	var key = _get_my_move_key() + "_quit"
	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-Authorization: " + ticket
	]
	var http = HTTPRequest.new()
	add_child(http)
	http.request(PLAYFAB_URL + "/Client/UpdateUserData",
		headers, HTTPClient.METHOD_POST,
		JSON.stringify({"Data": {key: "1"}, "Permission": "Public"}))
	await http.request_completed
	http.queue_free()

func poll_opponent_forfeit() -> bool:
	var ticket = get_ticket()
	if ticket == "" or online_match_id == "": return false
	var cfg = ConfigFile.new()
	cfg.load("user://session.cfg")
	var opponent_id = cfg.get_value("session", "opponent_playfab_id", "")
	if opponent_id == "": return false
	var key = _get_opponent_move_key() + "_quit"
	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-Authorization: " + ticket
	]
	var http = HTTPRequest.new()
	add_child(http)
	http.request(PLAYFAB_URL + "/Client/GetUserData",
		headers, HTTPClient.METHOD_POST,
		JSON.stringify({"PlayFabId": opponent_id, "Keys": [key]}))
	var response = await http.request_completed
	http.queue_free()
	if response[1] != 200: return false
	var json = JSON.new()
	if json.parse(response[3].get_string_from_utf8()) != OK: return false
	var val = json.get_data().get("data", {}).get("Data", {}).get(key, {}).get("Value", "")
	return val == "1"

# ── READY HANDSHAKE ─────────────────────────────────
# Każdy gracz wysyła "gotowy" gdy board jest załadowany.
# Timer startuje dopiero gdy obaj są gotowi.

func push_board_ready() -> void:
	var ticket = get_ticket()
	if ticket == "" or online_match_id == "": return
	var role = "p1" if player1_is_me else "p2"
	var key = "m" + online_match_id.replace("-", "").left(16) + "_boardready_" + role
	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-Authorization: " + ticket
	]
	var http = HTTPRequest.new()
	add_child(http)
	http.request(PLAYFAB_URL + "/Client/UpdateUserData",
		headers, HTTPClient.METHOD_POST,
		JSON.stringify({"Data": {key: "1"}, "Permission": "Public"}))
	await http.request_completed
	http.queue_free()

# Zwraca true gdy przeciwnik jest gotowy (lub timeout 15s)
func wait_for_opponent_board_ready() -> void:
	var ticket = get_ticket()
	if ticket == "" or online_match_id == "": return
	var cfg = ConfigFile.new()
	cfg.load("user://session.cfg")
	var opponent_id = cfg.get_value("session", "opponent_playfab_id", "")
	if opponent_id == "": return  # bot — od razu
	var opp_role = "p2" if player1_is_me else "p1"
	var key = "m" + online_match_id.replace("-", "").left(16) + "_boardready_" + opp_role
	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-Authorization: " + ticket
	]
	var elapsed = 0.0
	const TIMEOUT = 15.0
	const INTERVAL = 0.8
	while elapsed < TIMEOUT:
		await get_tree().create_timer(INTERVAL).timeout
		elapsed += INTERVAL
		var http = HTTPRequest.new()
		add_child(http)
		http.request(PLAYFAB_URL + "/Client/GetUserData",
			headers, HTTPClient.METHOD_POST,
			JSON.stringify({"PlayFabId": opponent_id, "Keys": [key]}))
		var response = await http.request_completed
		http.queue_free()
		if response[1] != 200: continue
		var json = JSON.new()
		if json.parse(response[3].get_string_from_utf8()) != OK: continue
		var val = json.get_data().get("data", {}).get("Data", {}).get(key, {}).get("Value", "")
		if val == "1": return
	push_warning("wait_for_opponent_board_ready: timeout — startujemy mimo to")
