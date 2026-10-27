extends RefCounted
## Local item definitions; quantities/ownership live in inventory_store.gd.
## Books are dynamic: "book:<story id>" for every story in the player's library
## (world/books/book_library.gd). Copies of one story share an id, so they stack.
const LIBRARY := preload("res://world/books/book_library.gd")
const FOOD := preload("res://world/food/food_catalog.gd")
const SHOP := preload("res://world/shop/shop_items.gd")
const RESOURCE_IMAGE := preload("res://world/resource_image.gd")
const IDENTITY := preload("res://world/inventory/item_identity.gd")
## Finished paintings are "art:<id>" (world/painting/painting_registry.gd); their scene and icon
## scripts load only where a painting exists.
const PAINTINGS := preload("res://world/painting/painting_registry.gd")
const ART_SCENE := "res://world/painting/art_item.tscn"
const ART_SCRIPT := "res://world/painting/art_item.gd"
static var _icons: Dictionary = {}
const BOOK_SCENE := "res://world/books/book_item.tscn"
const BOOK_STACK := 16
## The taser builds its own scene and icon (no model or .svg to import, so a code patch carries it).
const TASER := preload("res://world/inventory/assets/taser.gd")
const ITEMS := {
	"spray-bottle": {"name": "Water spray bottle", "description": "Aim and squeeze trigger / click to spray plain water.", "stack": 1},
	"notebook": {"name": "Notebook", "description": "A small notebook for a day in Equestria.", "stack": 1},
	"river-fish": {"name": "River fish", "description": "Caught from Ponyville's river.", "stack": 16},
	"taser": {"name": "Taser", "description": "Aim and squeeze trigger / click: a pony it hits drops and twitches for a few seconds, then gets up. She will remember it. Never fires at a foal.", "stack": 1},
}
static func is_book(id: String) -> bool:
	return id.begins_with("book:") and id.substr(5).is_valid_int()
static func canonical(id: String) -> String:
	return IDENTITY.canonical(id)
## The id format only; a painting whose file is missing is still a painting.
static func is_art(id: String) -> bool:
	return PAINTINGS.is_art(id)
static func has(id: String) -> bool:
	id = canonical(id)
	return ITEMS.has(id) or is_book(id) or FOOD.has(id) or SHOP.has(id) or is_art(id)
static func stack(id: String) -> int:
	return int(definition(id).get("stack", 1))
static func definition(id: String) -> Dictionary:
	id = canonical(id)
	if FOOD.has(id): return FOOD.definition(id)
	if ITEMS.has(id): return ITEMS[id]
	if SHOP.has(id): return SHOP.definition(id)
	if is_art(id):
		if PAINTINGS.is_photo(PAINTINGS.art_id(id)):
			return {"name": "Photo", "description": "A photo you took. Hang it, set it down, keep it, or show it to a pony.", "stack": 1, "art": true}
		var label := str(PAINTINGS.art(PAINTINGS.art_id(id)).get("label", ""))
		return {"name": "Painting: " + label if not label.is_empty() else "Painting", "description": "Your own painting from the easel. Hang it on a wall at home, set it down anywhere, or keep it.", "stack": 1, "art": true}
	if is_book(id):
		var meta := LIBRARY.book(id)
		if meta.is_empty(): return {"name": "A book", "description": "Not in your library any more.", "stack": BOOK_STACK, "book": true}
		return {"name": str(meta.get("title", "A book")), "description": "by %s  ·  hold it and press trigger or click to read" % meta.get("author", "unknown"), "stack": BOOK_STACK, "book": true}
	return {}
static func scene(id: String) -> PackedScene:
	id = canonical(id)
	if is_book(id): return load(BOOK_SCENE)
	if is_art(id): return load(ART_SCENE) as PackedScene
	if FOOD.has(id): return FOOD.scene(id)
	if SHOP.has(id): return SHOP.scene(id)
	if id == "taser": return TASER.scene()
	return load("res://world/inventory/assets/%s.tscn" % id) if ITEMS.has(id) else null
## Baked renders of the items themselves (tools/inventory/bake_item_icons.gd, dev 2026-10-01),
## before the drawn fallbacks below.
const BAKED := "res://world/inventory/icons/baked/%s.png"
static func icon(id: String) -> Texture2D:
	id = canonical(id)
	if is_book(id): return LIBRARY.icon(id)
	if is_art(id):
		var art: Script = load(ART_SCRIPT) as Script
		return art.call("icon", PAINTINGS.art_id(id)) as Texture2D if art != null else null
	if _icons.has(id): return _icons[id]
	if id == "taser": return TASER.icon()
	var baked := BAKED % id.replace(":", "_")
	if ResourceLoader.exists(baked) or FileAccess.file_exists(baked):
		var picture: Image = RESOURCE_IMAGE.read(baked)
		if picture != null and not picture.is_empty():
			_icons[id] = ImageTexture.create_from_image(picture)
			return _icons[id]
	if FOOD.has(id): return FOOD.icon(id)
	if SHOP.has(id): return SHOP.icon(id)
	if not ITEMS.has(id): return null
	if _icons.has(id): return _icons[id]
	var image: Image = RESOURCE_IMAGE.read("res://world/inventory/icons/%s.svg" % id)
	if image == null: return null
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_icons[id] = texture
	return texture
