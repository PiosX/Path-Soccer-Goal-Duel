extends Node
# IAP Manager — Path Game
# Autoload: Project → Project Settings → Autoload → "IAPManager"

var billing_client = null
var is_ready = false
var owned_products: Array = []

signal purchase_completed(product_id: String)
signal purchase_failed(error_message: String)
signal purchase_cancelled
signal restore_completed(restored_count: int)

# ===== PRODUKTY — uzupełnij ID gdy utworzysz w Google Play Console =====
var PRODUCTS = {
	"no_ads": {
		"type": "non_consumable",
		"title": "Remove Ads Forever",
		"description": "Removes all advertisements permanently",
		"price_display": "$1.99"
	},
	"coins_200": {
		"type": "consumable",
		"title": "200 Coins",
		"amount": 200,
		"price_display": "$0.99"
	},
	"coins_450": {
		"type": "consumable",
		"title": "450 Coins",
		"amount": 450,
		"price_display": "$1.99"
	},
	"coins_900": {
		"type": "consumable",
		"title": "900 Coins",
		"amount": 900,
		"price_display": "$2.99"
	},
	"coins_2000": {
		"type": "consumable",
		"title": "2000 Coins",
		"amount": 2000,
		"price_display": "$4.99"
	},
	"coins_4500": {
		"type": "consumable",
		"title": "4500 Coins",
		"amount": 4500,
		"price_display": "$9.99"
	},
	"coins_10000": {
		"type": "consumable",
		"title": "10000 Coins",
		"amount": 10000,
		"price_display": "$19.99"
	},
}

func _ready():
	if OS.get_name() == "Android":
		billing_client = BillingClient.new()
		billing_client.connected.connect(_on_billing_connected)
		billing_client.disconnected.connect(_on_billing_disconnected)
		billing_client.connect_error.connect(_on_billing_connect_error)
		billing_client.on_purchase_updated.connect(_on_purchases_updated)
		billing_client.query_purchases_response.connect(_on_query_purchases)
		billing_client.query_product_details_response.connect(_on_product_details_completed)
		billing_client.acknowledge_purchase_response.connect(_on_purchase_acknowledged)
		billing_client.consume_purchase_response.connect(_on_purchase_consumed)
		billing_client.start_connection()
	else:
		print("IAP skipped - not on Android")

func _on_billing_connected():
	is_ready = true
	query_product_details()
	query_purchases()

func _on_billing_disconnected():
	is_ready = false

func _on_billing_connect_error(error_code: int, error_message: String):
	print("Billing error [%d]: %s" % [error_code, error_message])
	is_ready = false

func query_purchases():
	if not is_ready or not billing_client: return
	billing_client.query_purchases(BillingClient.ProductType.INAPP)

func query_product_details():
	if not is_ready or not billing_client: return
	billing_client.query_product_details(PRODUCTS.keys(), BillingClient.ProductType.INAPP)

func _on_query_purchases(result: Dictionary):
	if result.get("response_code", -1) != BillingClient.BillingResponseCode.OK: return
	var purchases = result.get("purchases", [])
	owned_products.clear()
	for purchase in purchases:
		var product_id = purchase.get("product_ids", [""])[0]
		var purchase_token = purchase.get("purchase_token", "")
		var is_acknowledged = purchase.get("is_acknowledged", false)
		owned_products.append(product_id)
		handle_owned_product(product_id)
		if not is_acknowledged:
			billing_client.acknowledge_purchase(purchase_token)
	restore_completed.emit(purchases.size())

func _on_purchases_updated(result: Dictionary):
	if result.get("response_code", -1) != BillingClient.BillingResponseCode.OK:
		if result.get("response_code", -1) == 1:
			purchase_cancelled.emit()
		else:
			purchase_failed.emit(result.get("debug_message", "Unknown error"))
		return
	for purchase in result.get("purchases", []):
		handle_new_purchase(purchase)

func _on_product_details_completed(result: Dictionary):
	if result.get("response_code", -1) != BillingClient.BillingResponseCode.OK: return
	for detail in result.get("product_details", []):
		var sku = detail.get("product_id", "")
		if PRODUCTS.has(sku):
			PRODUCTS[sku]["price"] = detail.get("price", "")

func purchase_product(product_id: String):
	print("=== purchase_product wywołane: ", product_id)
	if not is_ready or not billing_client:
		print("=== ODRZUCONO - billing nie gotowy")
		purchase_failed.emit("Billing system not ready")
		return
	if not PRODUCTS.has(product_id):
		print("=== ODRZUCONO - nieznany produkt")
		purchase_failed.emit("Unknown product")
		return
	if PRODUCTS[product_id].type == "non_consumable" and owns_product(product_id):
		print("=== ODRZUCONO - już posiadany")
		purchase_failed.emit("Already owned")
		return
	print("=== wywołuję billing_client.purchase")
	billing_client.purchase(product_id)

func _on_purchase_acknowledged(response: Dictionary):
	print("=== acknowledged: ", response)

func _on_purchase_consumed(response: Dictionary):
	print("=== consumed: ", response)

func handle_new_purchase(purchase: Dictionary):
	print("=== handle_new_purchase: ", purchase)
	var product_id = purchase.get("product_ids", [""])[0]
	print("=== product_id: ", product_id)
	var purchase_token = purchase.get("purchase_token", "")
	var purchase_state = purchase.get("purchase_state", 0)
	print("=== purchase_state: ", purchase_state)
	if purchase.get("purchase_state", 0) != 1: 
		print("=== ODRZUCONO - purchase_state nie jest 1")
		return
	if not PRODUCTS.has(product_id): 
		print("=== ODRZUCONO - nieznany produkt: ", product_id)
		return

	var product = PRODUCTS[product_id]
	print("=== typ produktu: ", product.type)

	if product.type == "non_consumable":
		if product_id == "no_ads":
			print("=== no_ads kupione!")
			var admob = get_node_or_null("/root/AdMobManager")
			print("=== admob node: ", admob)
			if admob:
				admob.disable_ads()
				var cfg2 = ConfigFile.new()
				cfg2.load("user://session.cfg")
				cfg2.set_value("iap", "no_ads", true)
				cfg2.save("user://session.cfg")
		billing_client.acknowledge_purchase(purchase_token)

	elif product.type == "consumable":
		var amount = product.get("amount", 0)
		PlayerData.add_gold(amount)
		billing_client.consume_purchase(purchase_token)

	purchase_completed.emit(product_id)

func handle_owned_product(product_id: String):
	if product_id == "no_ads":
		var admob = get_node_or_null("/root/AdMobManager")
		if admob:
			admob.disable_ads()
			var cfg2 = ConfigFile.new()
			cfg2.load("user://session.cfg")
			cfg2.set_value("iap", "no_ads", true)
			cfg2.save("user://session.cfg")

func restore_purchases():
	query_purchases()

func owns_product(product_id: String) -> bool:
	return product_id in owned_products

func get_product_price(product_id: String) -> String:
	var product = PRODUCTS.get(product_id, {})
	return product.get("price", product.get("price_display", ""))

func is_available() -> bool:
	return is_ready
