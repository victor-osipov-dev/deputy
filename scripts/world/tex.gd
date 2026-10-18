class_name Tex
extends RefCounted
## Текстуры Kenney (CC0) + генерация пиксельных пешеходов кодом.

const MC := preload("res://assets/city/mc_atlas.png")
## Атлас modern-city: 37 колонок, шаг 17px.
const MC_COLS := 37
const MC_PITCH := 17

static var _cache := {}

## Отдельный тайл tiny-town по номеру (tile_0000.png …).
static func tile(i: int) -> Texture2D:
	var k := "t%d" % i
	if _cache.has(k):
		return _cache[k]
	var t := load("res://assets/town/tile_%04d.png" % i) as Texture2D
	_cache[k] = t
	return t


## Тот же тайл, увеличенный до px пикселей (чёткие пиксели).
static func tile_big(i: int, px: int) -> ImageTexture:
	var k := "b%dx%d" % [i, px]
	if _cache.has(k):
		return _cache[k] as ImageTexture
	var img := (tile(i) as Texture2D).get_image()
	img.resize(px, px, Image.INTERPOLATE_NEAREST)
	var it := ImageTexture.create_from_image(img)
	_cache[k] = it
	return it


## Отдельный тайл modern-city (assets/city/tile_NNNN.png).
static func ctile(i: int) -> Texture2D:
	var k := "c%d" % i
	if _cache.has(k):
		return _cache[k]
	var t := load("res://assets/city/tile_%04d.png" % i) as Texture2D
	_cache[k] = t
	return t


## Тот же modern-тайл, увеличенный до px пикселей.
static func ctile_big(i: int, px: int) -> ImageTexture:
	var k := "cb%dx%d" % [i, px]
	if _cache.has(k):
		return _cache[k] as ImageTexture
	var img := (ctile(i) as Texture2D).get_image()
	img.resize(px, px, Image.INTERPOLATE_NEAREST)
	var it := ImageTexture.create_from_image(img)
	_cache[k] = it
	return it


## Мозаика из атласа modern-city: col,row — левый верхний тайл, w,h — размер в тайлах.
static func mc(col: int, row: int, w: int = 1, h: int = 1) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = MC
	a.region = Rect2(col * MC_PITCH, row * MC_PITCH, w * 16 + (w - 1), h * 16 + (h - 1))
	return a


## Один тайл modern-city по индексу (row*37+col), увеличенный до px пикселей.
static func mc_big(i: int, px: int) -> ImageTexture:
	var k := "mcb%dx%d" % [i, px]
	if _cache.has(k):
		return _cache[k] as ImageTexture
	var img := MC.get_image()
	var col := i % MC_COLS
	var row := i / MC_COLS
	var t := img.get_region(Rect2(col * MC_PITCH, row * MC_PITCH, 16, 16))
	t.resize(px, px, Image.INTERPOLATE_NEAREST)
	var it := ImageTexture.create_from_image(t)
	_cache[k] = it
	return it


## Кто как выглядит: индекс варианта пешехода (16x24, генерируется кодом).
static func char_for(npc_id: String) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = person_tex(person_index(npc_id))
	a.region = Rect2(0, 0, 16, 24)
	return a


## Случайный прохожий для толпы.
static func ambient_char(i: int) -> ImageTexture:
	var pool := [11, 1, 9, 3, 6, 10]
	return person_tex(pool[posmod(i, pool.size())])


# ---------- пиксельные пешеходы (генерация в рантайме) ----------

static var _people: Array[ImageTexture] = []

# [цвет волос, цвет пиджака/платья, цвет брюк]
const P_PAL := [
	[Color(0.28, 0.19, 0.12), Color(0.16, 0.2, 0.32), Color(0.1, 0.1, 0.14)], # игрок: депутат
	[Color(0.85, 0.7, 0.4), Color(0.6, 0.62, 0.66), Color(0.25, 0.27, 0.3)], # помощник
	[Color(0.2, 0.15, 0.1), Color(0.2, 0.45, 0.45), Color(0.2, 0.24, 0.28)], # учительница
	[Color(0.7, 0.7, 0.7), Color(0.45, 0.2, 0.24), Color(0.15, 0.15, 0.18)], # директор
	[Color(0.12, 0.1, 0.1), Color(0.2, 0.3, 0.22), Color(0.1, 0.1, 0.1)], # чиновник
	[Color(0.6, 0.45, 0.3), Color(0.35, 0.25, 0.45), Color(0.15, 0.15, 0.2)], # коллега
	[Color(0.1, 0.1, 0.12), Color(0.25, 0.35, 0.55), Color(0.12, 0.12, 0.16)], # журналист
	[Color(0.35, 0.24, 0.14), Color(0.92, 0.92, 0.92), Color(0.35, 0.4, 0.45)], # врач
	[Color(0.85, 0.85, 0.85), Color(0.75, 0.5, 0.55), Color(0.5, 0.35, 0.4)], # бабушка
	[Color(0.2, 0.15, 0.1), Color(0.8, 0.45, 0.15), Color(0.2, 0.2, 0.25)], # водитель
	[Color(0.1, 0.08, 0.08), Color(0.5, 0.35, 0.2), Color(0.3, 0.3, 0.34)], # строитель
	[Color(0.7, 0.3, 0.15), Color(0.3, 0.5, 0.3), Color(0.2, 0.2, 0.24)], # активист
]


static func person_index(npc_id: String) -> int:
	match npc_id:
		"player":
			return 0
		"assistant":
			return 1
		"teacher_anna":
			return 2
		"principal":
			return 3
		"official":
			return 4
		"deputy_kol":
			return 5
		"journalist":
			return 6
		"doctor_elena":
			return 7
		"patient_granny":
			return 8
		"driver_sergey":
			return 9
		"builder":
			return 10
		"activist":
			return 11
		_:
			return 4


## Спрайт-текстура пешехода по индексу.
static func person_tex(i: int) -> ImageTexture:
	if _people.is_empty():
		_build_people()
	return _people[abs(i) % _people.size()]


static func _build_people() -> void:
	for v in P_PAL.size():
		var img := Image.create(16, 24, false, Image.FORMAT_RGBA8)
		_one_person(img, P_PAL[v])
		_people.append(ImageTexture.create_from_image(img))


static func _one_person(img: Image, p: Array) -> void:
	var hair: Color = p[0]
	var suit: Color = p[1]
	var pants: Color = p[2]
	var skin := Color(0.92, 0.78, 0.64)
	var shirt := Color(1, 1, 1)
	var dark := Color(0.13, 0.12, 0.12)
	var eye := Color(0.08, 0.07, 0.07)
	# волосы
	for y in 3:
		for x in range(4, 12):
			img.set_pixel(x, y, hair)
	# лицо
	for y in range(3, 8):
		for x in range(4, 12):
			img.set_pixel(x, y, skin)
	for y in range(3, 5):
		img.set_pixel(3, y, hair)
		img.set_pixel(12, y, hair)
	img.set_pixel(6, 5, eye)
	img.set_pixel(9, 5, eye)
	# пиджак
	for y in range(8, 17):
		for x in range(3, 13):
			img.set_pixel(x, y, suit)
	for x in range(7, 9):
		img.set_pixel(x, 8, shirt)
	img.set_pixel(3, 16, skin)
	img.set_pixel(12, 16, skin)
	# штанины
	for y in range(17, 22):
		for x in range(4, 7):
			img.set_pixel(x, y, pants)
		for x in range(9, 12):
			img.set_pixel(x, y, pants)
	# обувь
	for x in range(3, 7):
		img.set_pixel(x, 22, dark)
	for x in range(9, 13):
		img.set_pixel(x, 22, dark)


## Заливка прямоугольника тайлом (земля, дороги, стены, полы).
static func tiled(tex: Texture2D, r: Rect2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.position = r.position
	t.size = r.size
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_TILE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Одиночный спрайт.
static func spr(tex: Texture2D, scale_f: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.scale = Vector2(scale_f, scale_f)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return s
