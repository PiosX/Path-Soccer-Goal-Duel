extends Node
# AdMob Manager — Path Soccer
# Autoload: Project → Project Settings → Autoload → "AdMobManager"

const AdRequestClass                  = preload("res://addons/admob/src/api/core/AdRequest.gd")
const AdListenerClass                 = preload("res://addons/admob/src/api/listeners/AdListener.gd")
const MobileAdsClass                  = preload("res://addons/admob/src/api/MobileAds.gd")
const InterstitialAdLoaderClass       = preload("res://addons/admob/src/api/InterstitialAdLoader.gd")
const InterstitialAdLoadCallbackClass = preload("res://addons/admob/src/api/listeners/InterstitialAdLoadCallback.gd")
const FullScreenContentCallbackClass  = preload("res://addons/admob/src/api/listeners/FullScreenContentCallback.gd")

const INTERSTITIAL_ID      = "ca-app-pub-1542056164177824/7625751912"
const TEST_INTERSTITIAL_ID = "ca-app-pub-3940256099942544/1033173712"

# Zmień na false przed wysłaniem do Google Play!
const USE_TEST_ADS = false

var _interstitial_ad = null
var _is_android: bool = false
var ads_disabled: bool = false
var _initialized: bool = false

signal interstitial_closed

func _ready():
	print("=== AdMobManager _ready ===")
	_is_android = OS.get_name() == "Android"
	if not _is_android:
		print("AdMobManager: nie Android, pomijam")
		_initialized = true
		return
	_check_ads_disabled()
	if ads_disabled:
		print("AdMobManager: reklamy wyłączone (IAP)")
		_initialized = true
		return
	print("AdMobManager: inicjalizuje MobileAds...")
	MobileAdsClass.initialize()
	await get_tree().create_timer(1.0).timeout
	# NIE ładuj tu reklamy — ConsentManager zrobi to po sprawdzeniu zgody
	_initialized = true
	print("AdMobManager: SDK gotowe, czekam na ConsentManager")

func _check_ads_disabled():
	var cfg = ConfigFile.new()
	if cfg.load("user://session.cfg") == OK:
		ads_disabled = cfg.get_value("iap", "no_ads", false)

func _load_interstitial():
	if not _is_android or ads_disabled: return
	var unit_id = TEST_INTERSTITIAL_ID if USE_TEST_ADS else INTERSTITIAL_ID
	print("AdMobManager: ładuję interstitial ID: ", unit_id)
	var callback = InterstitialAdLoadCallbackClass.new()
	callback.on_ad_loaded = _on_interstitial_loaded
	callback.on_ad_failed_to_load = _on_interstitial_failed
	InterstitialAdLoaderClass.new().load(unit_id, AdRequestClass.new(), callback)

func show_interstitial():
	if ads_disabled or not _is_android:
		interstitial_closed.emit()
		return
	if _interstitial_ad:
		print("AdMobManager: pokazuję interstitial")
		var cb = FullScreenContentCallbackClass.new()
		cb.on_ad_dismissed_full_screen_content = _on_interstitial_dismissed
		cb.on_ad_failed_to_show_full_screen_content = _on_show_failed
		_interstitial_ad.full_screen_content_callback = cb
		_interstitial_ad.show()
	else:
		print("AdMobManager: brak reklamy — emituję closed, ładuję nową")
		interstitial_closed.emit()
		_load_interstitial()

func _on_interstitial_loaded(ad):
	print("AdMobManager: interstitial załadowany OK")
	_interstitial_ad = ad

func _on_interstitial_failed(error):
	print("AdMobManager: BŁĄD ładowania: ", error)
	_interstitial_ad = null

func _on_show_failed(error):
	print("AdMobManager: BŁĄD pokazywania: ", error)
	interstitial_closed.emit()
	_interstitial_ad = null
	_load_interstitial()

func _on_interstitial_dismissed():
	print("AdMobManager: interstitial zamknięty")
	interstitial_closed.emit()
	if _interstitial_ad:
		_interstitial_ad.destroy()
		_interstitial_ad = null
	_load_interstitial()

func disable_ads():
	ads_disabled = true
	if _interstitial_ad:
		_interstitial_ad.destroy()
		_interstitial_ad = null
		
	var ticket = PlayerData.get_ticket()
	if ticket != "":
		var headers = [
			"Content-Type: application/json",
			"Accept-Encoding: identity",
			"X-Authorization: " + ticket
		]
		var http = HTTPRequest.new()
		add_child(http)
		http.request(
			"https://139617.playfabapi.com/Client/UpdateUserData",
			headers, HTTPClient.METHOD_POST,
			JSON.stringify({"Data": {"no_ads": "true"}})
		)
		await http.request_completed
		http.queue_free()

func is_initialized() -> bool:
	return _initialized
