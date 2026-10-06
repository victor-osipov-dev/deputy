extends "res://scripts/world/world_base.gd"
## Хаб города: современный город (Kenney Roguelike Modern City, CC0).
## Сетка 80px. Здания, асфальт с разметкой, тротуары, машины, фонари.

const PX := 80

var city := {}
var district_rect := Rect2()
var _rng := RandomNumberGenerator.new()

# стиль зданий: стена (ctile modern), крыша (ctile modern), дверь-мозаика [col,row]
# индексы проверены визуально по файлам
const STYLE := {
	"office": [14, 8, [29, 13]],
	"school": [1, 1, [29, 13]],
	"city_hall": [123, 21, [31, 13]],
	"hospital": [745, 8, [29, 13]],
	"news": [8, 14, [31, 13]],
}
# индексы modern-city (row*37+col)
const T_GRASS := 669
const T_DIRT := 677
const T_SIDE := 740
const T_TAN := 745
const T_ASPH := 750
const T_EDGE := 749
const T_YEL := 752
const T_CROSS := 714


func build_map() -> void:
	map_id = "city"
	y_sort_enabled = true
	_rng.seed = 12345
	city = _load_json("res://data/city.json")
	var W: float = city.get("size", [2400, 1600])[0]
	var H: float = city.get("size", [2400, 1600])[1]
	add_child(Tex.tiled(Tex.tile_big(0, PX), Rect2(0, 0, W, H)))
	_walls(W, H)
	for r in city.get("roads", []):
		_road(Rect2(r[0], r[1], r[2], r[3]))
	var pl: Array = city.get("plaza", [1080, 640, 260, 220])
	add_child(Tex.tiled(Tex.ctile_big(T_TAN, PX), Rect2(pl[0], pl[1], pl[2], pl[3])))
	_crosswalk(Vector2(pl[0] + pl[2] * 0.5, 740), Vector2(pl[0] + pl[2] * 0.5, 850))
	_label("⛲ ПЛОЩАДЬ", Vector2(pl[0] + 30, pl[1] + 10), 20)
	_bench(Vector2(pl[0] + 40, pl[1] + 140))
	_bench(Vector2(pl[0] + pl[2] - 230, pl[1] + 140))
	var dd: Dictionary = city.get("district", {})
	district_rect = Rect2(dd.get("x", 1900), dd.get("y", 560), dd.get("w", 460), dd.get("h", 560))
	add_child(Tex.tiled(Tex.tile_big(13, PX), Rect2(district_rect.position.x, district_rect.position.y + 200, district_rect.size.x, 220)))
	_label("🏠 " + str(dd.get("name", "Район")), Vector2(district_rect.position.x + 120, district_rect.position.y + 10), 20)
	var pk: Dictionary = city.get("park", {})
	_label("🌳 " + str(pk.get("label", "ПУСТЫРЬ")), Vector2(pk.get("x", 1650) + 200, pk.get("y", 120) + 10), 20)
	_bench(Vector2(1750, 300))
	for b in city.get("buildings", []):
		_building(b)
	for h in city.get("houses", []):
		_house(Rect2(h[0], h[1], h[2], h[3]))
	for t in city.get("trees", []):
		_tree(Vector2(t[0], t[1]))
	for s in city.get("bus_stops", []):
		_bus_stop(s)
	_dropbox(Vector2(2100, 950))
	_dropbox(Vector2(1230, 470))
	_lamps_row(Vector2(100, 720), 5, 460.0)
	_lamps_row(Vector2(1120, 100), 4, 340.0)
	_car(Vector2(700, 795), 0)
	_car(Vector2(1500, 795), 2)
	_car(Vector2(1185, 1150), 1)
	_prop_mc(14, 14, Vector2(1450, 700), 3.0) # гидрант
	_prop_mc(15, 17, Vector2(1900, 860), 3.0) # конус
	_prop_mc(13, 15, Vector2(2290, 660), 3.0) # ящик у депо
	_prop_mc(13, 18, Vector2(2150, 1010), 3.0) # клумба
	_spawn_npcs()
	_spawn_ambient()


func default_spawn() -> Vector2:
	var s: Array = city.get("spawn", [460, 930])
	return Vector2(s[0], s[1])


func _check_zone() -> void:
	var z := "district" if district_rect.has_point(player.position) else "city"
	if z != Game.current_location and (Game.current_location == "city" or Game.current_location == "district"):
		Game.current_location = z


func _load_json(path: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	return JSON.parse_string(txt)


func _walls(w: float, h: float) -> void:
	_solid_body(Rect2(-40, -40, w + 80, 40))
	_solid_body(Rect2(-40, h, w + 80, 40))
	_solid_body(Rect2(-40, 0, 40, h))
	_solid_body(Rect2(w, 0, 40, h))


func _solid_body(r: Rect2) -> void:
	var st := StaticBody2D.new()
	st.position = r.position + r.size * 0.5
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = r.size
	cs.shape = rs
	st.add_child(cs)
	add_child(st)


func _label(text: String, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.position = pos
	add_child(l)
	return l


## Дорога: асфальт + жёлтая середина + тротуары по бокам.
func _road(r: Rect2) -> void:
	add_child(Tex.tiled(Tex.ctile_big(T_ASPH, PX), r))
	if r.size.x >= r.size.y:
		var mid := r.position.y + r.size.y * 0.5 - PX * 0.5
		add_child(Tex.tiled(Tex.ctile_big(T_YEL, PX), Rect2(r.position.x, mid, r.size.x, PX)))
		add_child(Tex.tiled(Tex.ctile_big(T_SIDE, PX), Rect2(r.position.x, r.position.y - PX, r.size.x, PX)))
		add_child(Tex.tiled(Tex.ctile_big(T_SIDE, PX), Rect2(r.position.x, r.position.y + r.size.y, r.size.x, PX)))
	else:
		var mid := r.position.x + r.size.x * 0.5 - PX * 0.5
		add_child(Tex.tiled(Tex.ctile_big(T_YEL, PX), Rect2(mid, r.position.y, PX, r.size.y)))
		add_child(Tex.tiled(Tex.ctile_big(T_SIDE, PX), Rect2(r.position.x - PX, r.position.y, PX, r.size.y)))
		add_child(Tex.tiled(Tex.ctile_big(T_SIDE, PX), Rect2(r.position.x + r.size.x, r.position.y, PX, r.size.y)))


## Зебра между двумя точками (вертикальная полоса).
func _crosswalk(a: Vector2, b: Vector2) -> void:
	var w := T_EDGE
	var x := (a.x + b.x) * 0.5 - PX * 0.5
	var y0 := minf(a.y, b.y)
	var y1 := maxf(a.y, b.y)
	var y := y0
	while y < y1:
		add_child(Tex.tiled(Tex.ctile_big(w, PX), Rect2(x, y, PX, PX)))
		y += PX


func _mosaic(col: int, row: int, w: int, h: int, sc: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Tex.mc(col, row, w, h)
	s.scale = Vector2(sc, sc)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return s


func _building(b: Dictionary) -> void:
	var r := Rect2(b["x"], b["y"], b["w"], b["h"])
	var st: Array = STYLE.get(str(b.get("id", "")), [156, 8, [31, 13]])
	add_child(Tex.tiled(Tex.ctile_big(st[0], PX), r))
	_solid_body(r)
	add_child(Tex.tiled(Tex.ctile_big(st[1], PX), Rect2(r.position.x, r.position.y - 40, r.size.x, 64)))
	_label("%s %s" % [str(b.get("icon", "")), str(b.get("sign", ""))], Vector2(r.position.x + 20, r.position.y - 44), 22)
	var d: Array = b.get("door", [r.position.x + r.size.x * 0.5, r.position.y + r.size.y])
	_door(Vector2(d[0], d[1]), str(b["id"]), "Войти: %s" % str(b.get("name", "")), st[2])


func _house(r: Rect2) -> void:
	add_child(Tex.tiled(Tex.ctile_big(745, PX), r))
	_solid_body(r)
	add_child(Tex.tiled(Tex.ctile_big(1, PX), Rect2(r.position.x, r.position.y - 30, r.size.x, 48)))


func _door(pos: Vector2, loc: String, label: String, dcell: Array) -> void:
	var look := _mosaic(dcell[0], dcell[1], 1, 2, 4.0)
	look.position = pos + Vector2(0, -62)
	add_child(look)
	var a := Area2D.new()
	a.position = pos
	a.add_to_group("interact")
	a.set_meta("kind", "door")
	a.set_meta("loc", loc)
	a.set_meta("label", label)
	var cs := CollisionShape2D.new()
	var cc := CircleShape2D.new()
	cc.radius = 55.0
	cs.shape = cc
	a.add_child(cs)
	add_child(a)


func _tree(pos: Vector2) -> void:
	var kinds := [29, 30, 31, 32, 33]
	var s := _mosaic(kinds[_rng.randi() % kinds.size()], 9, 1, 3, 4.0)
	s.position = pos + Vector2(0, -80)
	add_child(s)


func _lamps_row(pos: Vector2, n: int, step: float) -> void:
	var cells := [[0, 14], [6, 14], [10, 16]]
	for i in n:
		var c: Array = cells[i % cells.size()]
		var s := _mosaic(c[0], c[1], 1, 3, 4.0)
		s.position = pos + Vector2(i * step, -90)
		add_child(s)


func _car(pos: Vector2, v: int) -> void:
	var s := _mosaic(30, 15 + v * 2, 3, 2, 4.0)
	s.position = pos
	add_child(s)


func _bench(pos: Vector2) -> void:
	var s := _mosaic(32, 13, 3, 1, 4.0)
	s.position = pos
	add_child(s)


func _prop_mc(col: int, row: int, pos: Vector2, sc: float) -> void:
	var s := _mosaic(col, row, 1, 1, sc)
	s.position = pos
	add_child(s)


func _bus_stop(s: Dictionary) -> void:
	var pos := Vector2(s["x"], s["y"])
	var other := {}
	for o in city.get("bus_stops", []):
		if str(o["id"]) != str(s["id"]):
			other = o
	_bench(pos + Vector2(0, -30))
	var a := Area2D.new()
	a.position = pos
	a.add_to_group("interact")
	a.set_meta("kind", "bus")
	a.set_meta("to_pos", Vector2(other.get("x", pos.x), other.get("y", pos.y) + 40))
	var cs := CollisionShape2D.new()
	var cc := CircleShape2D.new()
	cc.radius = 60.0
	cs.shape = cc
	a.add_child(cs)
	add_child(a)
	_label("🚌 " + str(s.get("label", "Остановка")), pos + Vector2(-70, 22), 15)


func _dropbox(pos: Vector2) -> void:
	_prop_mc(32, 12, pos + Vector2(0, -20), 4.0)
	var a := Area2D.new()
	a.position = pos
	a.add_to_group("interact")
	a.set_meta("kind", "mailbox")
	var cs := CollisionShape2D.new()
	var cc := CircleShape2D.new()
	cc.radius = 55.0
	cs.shape = cc
	a.add_child(cs)
	add_child(a)
	_label("Ящик", pos + Vector2(-24, 22), 15)


func _spawn_npcs() -> void:
	var spots: Dictionary = city.get("npc_spots", {})
	for n in Game.D.get("npcs", {}).get("npcs", []):
		var post: Dictionary = Game.npc_where(str(n["id"]))
		if post.is_empty():
			continue
		if not (str(post.get("loc", "")) in ["city", "district"]):
			continue
		var sv: Array = spots.get(str(n["id"]), [100, 100])
		var pos := Vector2(sv[0], sv[1])
		if post.has("cx"):
			pos = Vector2(post["cx"], post["cy"])
		var npc := WorldNPC.make_id(str(n["id"]), str(n.get("emoji", "🧍")), str(n.get("name", "?")))
		npc.position = pos
		add_child(npc)
		var touch: Area2D = npc.get_node("Touch")
		touch.add_to_group("interact")
		touch.set_meta("kind", "npc")
		touch.set_meta("npc", str(n["id"]))


func _spawn_ambient() -> void:
	for rule in city.get("ambient", []):
		if Game.day < int(rule.get("day_min", 1)):
			continue
		if rule.has("day_max") and Game.day > int(rule["day_max"]):
			continue
		for i in int(rule.get("count", 1)):
			var a := WorldNPC.make_ambient(str(rule.get("emoji", "🧍")), str(rule.get("line", "...")))
			a.position = Vector2(rule["x"], rule["y"]) + Vector2((i % 3) * 55 - 55, (i / 3) * 50)
			add_child(a)
