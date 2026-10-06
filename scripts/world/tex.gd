class_name Tex
extends RefCounted
## Текстуры Kenney (CC0, см. assets/town/License-*): тайлы города и персонажи.

const ATLAS := preload("res://assets/town/atlas.png")
const CHARS := preload("res://assets/town/chars.png")
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


## Прямоугольник из атласа персонажей (координаты листа).
static func char_rect(r: Rect2) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = CHARS
	a.region = r
	return a


## Кто как выглядит: col,row в сетке листа (фигуры ~17x25).
static func char_for(npc_id: String) -> AtlasTexture:
	var col := 1
	var row := 8
	match npc_id:
		"player":
			col = 1
			row = 9
		"assistant":
			col = 1
			row = 7
		"teacher_anna":
			col = 0
			row = 7
		"principal":
			col = 0
			row = 8
		"official":
			col = 1
			row = 10
		"deputy_kol":
			col = 1
			row = 6
		"journalist":
			col = 0
			row = 9
		"doctor_elena":
			col = 0
			row = 11
		"patient_granny":
			col = 1
			row = 5
		"driver_sergey":
			col = 0
			row = 6
		"builder":
			col = 0
			row = 10
		"activist":
			col = 0
			row = 5
	var y := row * 17 - 4
	if y < 0.0:
		y = 0.0
	return char_rect(Rect2(col * 17, y, 17, 25))


## Случайный прохожий для толпы.
static func ambient_char(i: int) -> AtlasTexture:
	var pool := [Vector2(1, 8), Vector2(0, 2), Vector2(1, 2), Vector2(0, 1), Vector2(1, 1), Vector2(0, 8)]
	var c: Vector2 = pool[i % pool.size()]
	return char_rect(Rect2(c.x * 17, c.y * 17 - 4, 17, 25))


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
