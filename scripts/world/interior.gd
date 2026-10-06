extends "res://scripts/world/world_base.gd"
## Интерьер здания из data/interiors.json: пол, мебель, NPC по постам, объекты.
## Текстуры: Kenney Tiny Town (CC0), сетка 80px.

const PX := 80

var conf := {}
var loc := ""

# пол по зданию
const FLOOR := {
	"office": 1,
	"school": 1,
	"city_hall": 1,
	"hospital": 1,
	"news": 1,
}

# мебель: тайл и высота спрайта
const FURN := {
	"Стол": [103, 4.0],
	"Принтерная": [102, 4.0],
	"Диван-кровать": [106, 4.0],
	"Класс 1": [108, 4.0],
	"Класс 2": [108, 4.0],
	"Кабинет директора": [103, 4.0],
	"Приёмная": [108, 4.0],
	"Зал заседаний": [103, 4.0],
	"Палата": [106, 4.0],
	"Склад лекарств": [102, 4.0],
	"Отдел новостей": [108, 4.0],
	"Архив": [102, 4.0],
}


func build_map() -> void:
	loc = Game.current_location
	map_id = loc
	y_sort_enabled = true
	conf = _load_json("res://data/interiors.json").get(loc, {})
	if conf.is_empty():
		conf = {"name": loc, "size": [1100, 700], "floor": [0.2, 0.2, 0.2], "obstacles": [], "npc_spots": {}, "props": []}
	var sz: Array = conf.get("size", [1100, 700])
	var floor_i: int = FLOOR.get(loc, 13)
	add_child(Tex.tiled(Tex.tile_big(floor_i, PX), Rect2(0, 0, sz[0], sz[1])))
	_walls(sz[0], sz[1])
	_label(str(conf.get("name", loc)), Vector2(30, 16), 24)
	for o in conf.get("obstacles", []):
		_furniture(o)
	for p in conf.get("props", []):
		_prop(p)
	_spawn_npcs()


func default_spawn() -> Vector2:
	return Vector2(550, 600)


func board_text() -> String:
	for p in conf.get("props", []):
		if str(p.get("kind", "")) == "info_board":
			var topic := str(p.get("topic", "school"))
			if Game.is_unlocked("agenda_view"):
				return "Стенд: %s — %s" % [Game.topic_name(topic), Game.agenda_word(int(Game.agenda.get(topic, 0)))]
			return "Стенд: объявления, жалобы. Кажется, людей волнует %s." % Game.topic_name(topic)
	return "Стенд объявлений."


func _load_json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _walls(w: float, h: float) -> void:
	_solid_body(Rect2(-40, -40, w + 80, 40))
	_solid_body(Rect2(-40, h, w + 80, 40))
	_solid_body(Rect2(-40, 0, 40, h))
	_solid_body(Rect2(w, 0, 40, h))


func _label(text: String, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	l.position = pos
	add_child(l)
	return l


func _solid_body(r: Rect2) -> void:
	var st := StaticBody2D.new()
	st.position = r.position + r.size * 0.5
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = r.size
	cs.shape = rs
	st.add_child(cs)
	add_child(st)


func _furniture(o: Dictionary) -> void:
	var r := Rect2(o["x"], o["y"], o["w"], o["h"])
	var st: Array = FURN.get(str(o.get("label", "")), [102, 4.0])
	var s := Tex.spr(Tex.tile(st[0]), st[1])
	s.position = r.position + r.size * 0.5 + Vector2(0, -20)
	add_child(s)
	_solid_body(r)


var PROP_TILE := {"printer": 102, "paper": 102, "bed": 106, "info_board": 102, "flavor": 102}


func _prop(p: Dictionary) -> void:
	var pos := Vector2(p["x"], p["y"])
	var kind := str(p.get("kind", "flavor"))
	if kind == "exit":
		var a := Area2D.new()
		a.position = pos
		a.add_to_group("interact")
		a.set_meta("kind", "exit")
		a.set_meta("out", {"pos": _door_out()})
		var cs := CollisionShape2D.new()
		var cc := CircleShape2D.new()
		cc.radius = 60.0
		cs.shape = cc
		a.add_child(cs)
		add_child(a)
		_label(str(p.get("label", "Выход")), pos + Vector2(-60, 20), 15)
		return
	var a2 := Area2D.new()
	a2.position = pos
	a2.add_to_group("interact")
	a2.set_meta("kind", kind)
	if kind == "flavor":
		a2.set_meta("label", str(p.get("label", "")))
		a2.set_meta("text", str(p.get("text", "...")))
	var cs2 := CollisionShape2D.new()
	var cc2 := CircleShape2D.new()
	cc2.radius = 60.0
	cs2.shape = cc2
	a2.add_child(cs2)
	add_child(a2)
	var s := Tex.spr(Tex.tile(PROP_TILE.get(kind, 102)), 4.0)
	s.position = pos + Vector2(0, -20)
	add_child(s)
	_label(str(p.get("label", "")), pos + Vector2(-60, 20), 15)


func _door_out() -> Vector2:
	var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/city.json"))
	for b in c.get("buildings", []):
		if str(b.get("id", "")) == loc:
			var d: Array = b.get("door", [400, 400])
			return Vector2(d[0], d[1] + 60)
	return Vector2(400, 400)


func _spawn_npcs() -> void:
	var spots: Dictionary = conf.get("npc_spots", {})
	for n in Game.D.get("npcs", {}).get("npcs", []):
		var post: Dictionary = Game.npc_where(str(n["id"]))
		if post.is_empty():
			continue
		if str(post.get("loc", "")) != loc:
			continue
		var s: Array = spots.get(str(n["id"]), [550, 350])
		var npc := WorldNPC.make_id(str(n["id"]), str(n.get("emoji", "🧍")), str(n.get("name", "?")))
		npc.position = Vector2(s[0], s[1])
		add_child(npc)
		var touch: Area2D = npc.get_node("Touch")
		touch.add_to_group("interact")
		touch.set_meta("kind", "npc")
		touch.set_meta("npc", str(n["id"]))
