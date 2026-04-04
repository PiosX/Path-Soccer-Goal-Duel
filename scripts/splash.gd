extends Control

func _ready():
	# Sprawdź sesję w tle — splash czeka na wynik
	var cfg = ConfigFile.new()
	if cfg.load("user://session.cfg") == OK:
		var device_id = cfg.get_value("session", "device_id", "")
		if device_id != "":
			# Sesja istnieje — odśwież w tle, potem idź do play
			await PlayerData.refresh_session(cfg)
			SceneTransition.go_to("res://scenes/play.tscn")
			return
	# Brak sesji — idź do loginu
	SceneTransition.go_to("res://scenes/login.tscn")
