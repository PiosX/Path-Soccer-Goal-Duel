# MusicManager.gd — Autoload (Project > Project Settings > Autoload)
# Nazwa: MusicManager
#
# NIE wymaga busów Sound/Music — działa na samym Master busie.
# Osobne wyciszanie dźwięków SFX vs muzyki odbywa się przez volume_db
# poszczególnych graczy lub przez dedykowane busy jeśli je masz.
#
# JAK UŻYWAĆ BUSÓW (opcjonalnie, jeśli chcesz osobne kontrolki):
#   W Godot: Audio > Audio Bus Layout > dodaj bus "Music" i bus "Sound"
#   Każdy AudioStreamPlayer ma pole "Bus" — ustaw odpowiednio.
#   Bez tego toggle działa na MASTER (wycisza wszystko razem).

extends Node

const AUDIO_CFG_PATH = "user://audio_settings.cfg"
const MUSIC_VOLUME_DB = -30.0  # ~50% głośności

var _music_player: AudioStreamPlayer = null
var _current_stream_path: String = ""

# Które sceny mają grać muzykę menu (music.mp3)
# Które sceny mają grać muzykę gry (game.mp3) — game.tscn robi to sama przez własny player
const MENU_MUSIC_PATH = "res://sounds/music.mp3"
const GAME_MUSIC_PATH = "res://sounds/game.mp3"

# Sceny gdzie MusicManager NIE gra niczego (mają własną muzykę lub ciszę)
const SCENES_WITH_OWN_MUSIC = ["game.tscn", "match_intro.tscn"]

func _ready():
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicManagerPlayer"
	add_child(_music_player)
	_load_and_apply_audio_settings()

	# Śledź zmiany scen żeby zatrzymać/zmienić muzykę
	get_tree().root.child_order_changed.connect(_on_scene_changed)

func _on_scene_changed():
	# Daj chwilę żeby scena się załadowała
	await get_tree().process_frame
	_update_music_for_current_scene()

func _update_music_for_current_scene():
	var scene = get_tree().current_scene
	if scene == null:
		return
	var scene_file = scene.scene_file_path.get_file()  # np. "game.tscn"
	if scene_file in SCENES_WITH_OWN_MUSIC:
		stop_music()
	else:
		play_music(MENU_MUSIC_PATH)

# ——— PUBLICZNE API ———

func play_music(stream_path: String):
	if _current_stream_path == stream_path and _music_player.playing:
		return
	_current_stream_path = stream_path
	var stream = load(stream_path) as AudioStream
	if stream == null:
		push_warning("MusicManager: nie znaleziono pliku " + stream_path)
		return
	# Ustaw loop
	if stream is AudioStreamMP3:
		stream.loop = true
	_music_player.stream = stream
	_music_player.volume_db = MUSIC_VOLUME_DB
	_music_player.bus = _get_bus_name("Music")
	_music_player.stream.loop = true
	_music_player.play()

func stop_music():
	_music_player.stop()
	_current_stream_path = ""

func set_sound_enabled(enabled: bool):
	_set_bus_mute("Sound", not enabled)
	_save_audio_settings()

func set_music_enabled(enabled: bool):
	_set_bus_mute("Music", not enabled)
	# Też wycisz/odcisz gracza muzyki jeśli bus nie istnieje
	if AudioServer.get_bus_index("Music") < 0:
		_music_player.volume_db = MUSIC_VOLUME_DB if enabled else -80.0
	_save_audio_settings()

func is_sound_enabled() -> bool:
	var idx = AudioServer.get_bus_index("Sound")
	if idx < 0:
		# Brak busa Sound — sprawdź czy zapisano stan
		var cfg = ConfigFile.new()
		if cfg.load(AUDIO_CFG_PATH) == OK:
			return cfg.get_value("audio", "sound_on", true)
		return true
	return not AudioServer.is_bus_mute(idx)

func is_music_enabled() -> bool:
	var idx = AudioServer.get_bus_index("Music")
	if idx < 0:
		var cfg = ConfigFile.new()
		if cfg.load(AUDIO_CFG_PATH) == OK:
			return cfg.get_value("audio", "music_on", true)
		return true
	return not AudioServer.is_bus_mute(idx)

# ——— PRYWATNE ———

func _get_bus_name(preferred: String) -> String:
	if AudioServer.get_bus_index(preferred) >= 0:
		return preferred
	return "Master"

func _set_bus_mute(bus_name: String, muted: bool):
	var idx = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, muted)
	else:
		# Brak busa — zapisz tylko do pliku, zastosuj przy starcie
		push_warning("MusicManager: brak busa '" + bus_name + "'. Dodaj go w Audio Bus Layout.")

func _load_and_apply_audio_settings():
	var cfg = ConfigFile.new()
	if cfg.load(AUDIO_CFG_PATH) != OK:
		return
	var sound_on = cfg.get_value("audio", "sound_on", true)
	var music_on = cfg.get_value("audio", "music_on", true)
	_set_bus_mute("Sound", not sound_on)
	_set_bus_mute("Music", not music_on)
	# Fallback gdy brak busa Music
	if AudioServer.get_bus_index("Music") < 0:
		_music_player.volume_db = MUSIC_VOLUME_DB if music_on else -80.0

func _save_audio_settings():
	var cfg = ConfigFile.new()
	cfg.set_value("audio", "sound_on", is_sound_enabled())
	cfg.set_value("audio", "music_on", is_music_enabled())
	cfg.save(AUDIO_CFG_PATH)
