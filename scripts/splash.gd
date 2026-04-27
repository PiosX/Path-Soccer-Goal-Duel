extends Control

func _ready():
	var cfg = ConfigFile.new()
	if cfg.load("user://session.cfg") == OK:
		var device_id = cfg.get_value("session", "device_id", "")
		if device_id != "":
			await PlayerData.refresh_session(cfg)
			if PlayerData.get_ticket() != "":
				SceneTransition.go_to("res://scenes/play.tscn")
				return
	
	# Brak sesji - idź do loginu
	SceneTransition.go_to("res://scenes/login.tscn")
