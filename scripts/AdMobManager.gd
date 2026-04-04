extends Node
# AdMob Manager — Path Game
# Autoload: Project → Project Settings → Autoload → "AdMobManager"

const AdRequestClass                  = preload("res://addons/admob/src/api/core/AdRequest.gd")
const AdListenerClass                 = preload("res://addons/admob/src/api/listeners/AdListener.gd")
const MobileAdsClass                  = preload("res://addons/admob/src/api/MobileAds.gd")
const InterstitialAdLoaderClass       = preload("res://addons/admob/src/api/InterstitialAdLoader.gd")
const InterstitialAdLoadCallbackClass = preload("res://addons/admob/src/api/listeners/InterstitialAdLoadCallback.gd")
const FullScreenContentCallbackClass  = preload("res://addons/admob/src/api/listeners/FullScreenContentCallback.gd")

# ===== TWOJE ID — WSTAW PO UTWORZENIU W ADMOB =====
const INTERSTITIAL_ID = "ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX"  # <-- zmień

const TEST_INTERSTITIAL_ID = "ca-app-pub-3940256099942544/1033173712"

# Zmień na false przed wysłaniem do Google Play!
const USE_TEST_ADS = true

# ===== STAN =====
var _interstitial_ad = null
var _is_android: bool = false
var ads_disabled: bool = false

signal interstitial_closed

func _ready():
	_is_android = OS.get_name() == "Android"
	if not _is_android:
		return
	_check_ads_disabled()
	if ads_disabled:
		return
	MobileAdsClass.initialize()

func _check_ads_disabled():
	var cfg = ConfigFile.new()
	if cfg.load("user://session.cfg") == OK:
		ads_disabled = cfg.get_value("iap", "no_ads", false)

# ================================================================
#  INTERSTITIAL (pełnoekranowa przy wygranej)
# ================================================================

func _load_interstitial():
	if not _is_android or ads_disabled: return
	var unit_id = TEST_INTERSTITIAL_ID if USE_TEST_ADS else INTERSTITIAL_ID
	var callback = InterstitialAdLoadCallbackClass.new()
	callback.on_ad_loaded = _on_interstitial_loaded
	callback.on_ad_failed_to_load = _on_interstitial_failed
	InterstitialAdLoaderClass.new().load(unit_id, AdRequestClass.new(), callback)

func show_interstitial():
	if ads_disabled or not _is_android:
		interstitial_closed.emit()
		return
	if _interstitial_ad:
		var cb = FullScreenContentCallbackClass.new()
		cb.on_ad_dismissed_full_screen_content = _on_interstitial_dismissed
		_interstitial_ad.full_screen_content_callback = cb
		_interstitial_ad.show()
	else:
		# Nie gotowy — emituj od razu żeby gra nie utknęła
		interstitial_closed.emit()
		_load_interstitial()

func _on_interstitial_loaded(ad):
	_interstitial_ad = ad

func _on_interstitial_failed(error):
	print("Interstitial error: ", error)
	_interstitial_ad = null

func _on_interstitial_dismissed():
	interstitial_closed.emit()
	if _interstitial_ad:
		_interstitial_ad.destroy()
		_interstitial_ad = null
	_load_interstitial()

# ================================================================
#  UTILITY
# ================================================================

func disable_ads():
	ads_disabled = true
	if _interstitial_ad:
		_interstitial_ad.destroy()
		_interstitial_ad = null
	# Zapisz do pliku
	var cfg = ConfigFile.new()
	cfg.load("user://session.cfg")
	cfg.set_value("iap", "no_ads", true)
	cfg.save("user://session.cfg")
