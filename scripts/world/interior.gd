extends "res://scripts/world/world_base.gd"
## Интерьер здания из data/interiors.json: пол, мебель, NPC по постам, объекты.
## Текстуры: Kenney Roguelike Modern City (CC0), сетка 80px.

const PX := 80

var conf := {}
var loc := ""

# индексы тайлов modern-city (row*37+col)
const T_WOOD := 745 # (28,20) бежевая брусчатка
const T_WALL := 227 # (5,6) серый кирпич

# мебель: индекс тайла-«облицовки» прямоугольника-препятствия
const FURN := {
	"Стол": 546, # принтерный ящик
	"Принтерная": 545, # ящик с кнопкой
	"Диван-кровать": 849, # шкаф-тумба
	"Класс 1": 543, # коробки-парта
	"Класс 2": 544,
	"Кабинет директора": 886, # шкафчик
	"Приёмная": 548, # ящик с ручкой
	"Зал заседаний": 805, # тёмный шкаф
	"Палата": 886, # шкафчик
	"Склад лекарств": 579, # шкафчик с окошком
	"Отдел новостей": 804, # тёмная стойка
	"Архив": 875, # тёмный хват-шкаф
}


func build_map() -> void:
	loc = Game.current_location
	map_id = loc
	y_sort_enabled = true
	conf = _load_json("res://data/interiors.json").get(loc, {})
	if conf.is_empty():
		conf = {"name": loc, "size": [1100, 700], "floor": [0.2, 0.2, 0.2], "obstacles": [], "npc_spots": {}, "props": []}
	var sz: Array = conf.get("size", [1100, 700])
	add_child(Tex.tiled(Tex.mc_big(T_WOOD, PX), Rect2(0, 0, sz[0], sz[1])))
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
	var rects := [Rect2(-40, -40, w + 80, 40), Rect2(-40, h, w + 80, 40), Rect2(-40, 0, 40, h), Rect2(w, 0, 40, h)]
	for r in rects:
		add_child(Tex.tiled(Tex.mc_big(T_WALL, PX), r))
		_solid_body(r)


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
	var idx: int = FURN.get(str(o.get("label", "")), 546)
	var s := Tex.tiled(Tex.mc_big(idx, PX), r)
	add_child(s)
	_solid_body(r)


var PROP_TILE := {"printer": 545, "paper": 547, "bed": 849, "info_board": 616, "flavor": 543}


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
	var s := Tex.spr(Tex.mc_big(PROP_TILE.get(kind, 542), PX), 1.0)
	s.position = pos + Vector2(0, -16)
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
