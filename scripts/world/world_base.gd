extends Node2D
## Общий слой мира: игрок, время от ходьбы, близость-взаимодействие, ночь.
## City и Interior наследуют и реализуют build_map().

const WALK_MIN_PER_SEC := 1.0 / 0.8 # 1 игровая минута = 0.8 реальной секунды
const IDLE_MIN_PER_SEC := 0.05
const IDLE_LIMIT := 30.0

var map_id := "city"
var player: WorldPlayer
var ui: WorldUI
var tint_layer: CanvasLayer
var tint_rect: ColorRect
var still := 0.0
var idle_warned := false
var target: Area2D


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.05, 0.07, 0.05))
	build_map()
	_place_player()
	_make_tint()
	ui = WorldUI.new()
	ui.base = self
	add_child(ui)
	ui.build()
	Game.state_changed.connect(_on_state)
	for note in Game.enter_map(map_id):
		ui.toast(note)
	_drain_unlocks()
	ui.refresh_hud()
	ui.refresh_objective()
	_intro_hints()


func build_map() -> void:
	pass


func default_spawn() -> Vector2:
	return Vector2(400, 400)


func _place_player() -> void:
	player = WorldPlayer.new()
	add_child(player)
	var sp: Vector2 = default_spawn()
	var so = Game.get("spawn_override")
	if so != null and str(so.get("map", map_id)) == map_id:
		sp = so.get("pos", sp)
	Game.set("spawn_override", null)
	player.position = sp


func _make_tint() -> void:
	tint_layer = CanvasLayer.new()
	tint_layer.layer = -1
	add_child(tint_layer)
	tint_rect = ColorRect.new()
	tint_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint_rect.color = Color(1, 1, 1, 0)
	tint_layer.add_child(tint_rect)


func _on_state() -> void:
	if is_instance_valid(ui):
		ui.refresh_hud()


func _intro_hints() -> void:
	if Game.seen_hint("move"):
		if DisplayServer.is_touchscreen_available():
			ui.toast("Тяни левый круг — идти. Подходи к людям.")
		else:
			ui.toast("WASD — идти, E — говорить. Найди свой офис.")


func _process(delta: float) -> void:
	_update_tint()
	if ui.blocks_world():
		still = 0.0
		return
	if player.is_moving():
		still = 0.0
		idle_warned = false
		var note := Game.tick_time(delta * WALK_MIN_PER_SEC)
		_after_action(note)
		_check_zone()
	else:
		still += delta
		var rate := IDLE_MIN_PER_SEC
		if still >= IDLE_LIMIT:
			rate = 0.5
			if not idle_warned:
				idle_warned = true
				ui.toast("Прошло время… Стоять — тоже выбор.")
		var note2 := Game.tick_time(delta * rate)
		_after_action(note2)


func _check_zone() -> void:
	pass


func _physics_process(_delta: float) -> void:
	if ui.blocks_world():
		ui.set_prompt("", null)
		target = null
		return
	var areas := player.sensor().get_overlapping_areas()
	var best: Area2D = null
	var best_d := 1e9
	for a in areas:
		if not (a is Area2D):
			continue
		if not a.has_meta("kind"):
			continue
		var d := player.position.distance_to(a.global_position)
		if d < best_d:
			best_d = d
			best = a
	target = best
	if target == null:
		ui.set_prompt("", null)
	else:
		ui.set_prompt(prompt_for(target), target)


func prompt_for(a: Area2D) -> String:
	var kind := str(a.get_meta("kind"))
	match kind:
		"npc":
			var n := Game.npc_by_id(str(a.get_meta("npc")))
			return "💬 Поговорить: %s" % str(n.get("name", "?"))
		"door":
			return "🚪 Войти: %s" % str(a.get_meta("label", "?"))
		"exit":
			return "🚪 Выйти в город"
		"printer":
			if Game.is_unlocked("printing"):
				return "🖨 Печатать листовки (30 мин, 150€)"
			return "🖨 Принтер (пока молчит…)"
		"paper":
			if Game.paper_unread():
				return "📰 Взять газету (новое!)"
			return "📰 Газета"
		"bed":
			return "🛏 Спать до утра"
		"board":
			return "📌 Стенд объявлений"
		"flavor":
			return "❔ %s" % str(a.get_meta("label", "Осмотреть"))
		"bus":
			return "🚌 Автобус: 8 мин, 5€"
		"mailbox":
			return "📮 Опустить листовки (массово)"
	return "E"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if target != null and not ui.blocks_world():
			do_interact(target)
			_ack_input()
	elif event.is_action_pressed("phone"):
		ui.toggle_phone()
		_ack_input()
	elif event.is_action_pressed("menu"):
		ui.toggle_menu()
		_ack_input()


func _ack_input() -> void:
	# Действие могло сменить сцену (дверь/выход) — тогда мы уже вне дерева.
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func do_interact(a: Area2D) -> void:
	var kind := str(a.get_meta("kind"))
	match kind:
		"npc":
			var nid := str(a.get_meta("npc"))
			if Game.unlock_mechanic("talking"):
				ui.toast(Game.mech_toast("talking"))
			if Game.seen_hint("talk"):
				ui.toast("Выбирай реплики — слова имеют цену и последствия.")
			ui.open_dialog(nid)
		"door":
			goto_map(str(a.get_meta("loc")), Vector2(550, 600))
		"exit":
			var d: Dictionary = a.get_meta("out")
			goto_map("city", d.get("pos", Vector2(400, 400)))
		"printer":
			if not Game.is_unlocked("printing"):
				ui.toast("Принтер молчит. Загляни позже.")
				return
			ui.toast(Game.print_leaflets())
			_drain_unlocks()
			_after_action("")
		"paper":
			Game.mark_paper_read()
			ui.open_paper(Game.pickup_paper())
			_drain_unlocks()
		"bed":
			_after_action(Game.end_day())
		"board":
			ui.toast(board_text())
		"flavor":
			ui.toast(str(a.get_meta("text", "...")))
		"bus":
			ride_bus(a)
		"mailbox":
			if not Game.is_unlocked("campaigning"):
				ui.toast("Сначала напечатай листовки в офисе.")
				return
			ui.toast(Game.distribute("mass"))
			_drain_unlocks()
			_after_action("")


func board_text() -> String:
	return "На стенде — объявления и жалобы родителей."


func ride_bus(a: Area2D) -> void:
	if Game.money < 5:
		ui.toast("Нужно 5€ на билет.")
		return
	Game.money -= 5
	var to: Vector2 = a.get_meta("to_pos", player.position)
	player.position = to
	still = 0.0
	ui.toast("🚌 Автобус (−5€, −8 мин).")
	_after_action(Game.tick_time(8.0))


func goto_map(next: String, spawn: Vector2) -> void:
	# Фиксируем назначение ДО смены сцены: интерьер строится по current_location.
	Game.current_location = next
	if not next in Game.visited:
		Game.visited.append(next)
	Game.set("spawn_override", {"map": next, "pos": spawn})
	if next == "city":
		get_tree().change_scene_to_file("res://scenes/City.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Interior.tscn")


func _after_action(note: String) -> void:
	_drain_unlocks()
	if Game.game_over:
		ui.show_election()
		return
	if Game.just_slept:
		Game.just_slept = false
		ui.show_night(Game.last_night)
		_wake_home_later()
	elif note != "":
		ui.show_night(note)
		_wake_home_later()


func _wake_home_later() -> void:
	# После закрытия ночи игрок проснётся в офисе (делает show_night).
	pass


func wake_home() -> void:
	if map_id == "office":
		player.position = Vector2(220, 480)
	else:
		goto_map("office", Vector2(220, 480))


func _drain_unlocks() -> void:
	for t in Game.drain_unlocks():
		ui.toast(t)
	ui.refresh_objective()


func _update_tint() -> void:
	var h := float(Game.minutes) / 60.0
	var c := Color(1, 1, 1, 0)
	if h < 10.0:
		c = Color(1.0, 0.95, 0.85, 0.06)
	elif h >= 16.0 and h < 18.0:
		c = Color(1.0, 0.8, 0.55, 0.10)
	elif h >= 18.0:
		c = Color(0.85, 0.6, 0.75, 0.16)
	tint_rect.color = c
