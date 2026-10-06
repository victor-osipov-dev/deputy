extends Control
## Main UI — только показывает данные Game. Вся логика в Game (autoload).
## Управление: клик/тап. Большие кнопки для телефона.

var hud_day: Label
var hud_time: Label
var hud_money: Label
var hud_leaf: Label
var hud_prom: Label
var content: VBoxContainer
var scroll: ScrollContainer
var task_label: Label
var last_tut_step := -1
var sup_tut := false
# Модальный попап: затемнение на весь экран + центрированная панель.
# Панель ограничена размером вьюпорта, текст крутится внутри,
# кнопка закрытия всегда видима внизу.
var popup: Control
var popup_panel: PanelContainer
var popup_title: Label
var popup_scroll: ScrollContainer
var popup_text: RichTextLabel
var dlg_panel: Control
var dlg_inner: PanelContainer
var dlg_title: Label
var dlg_scroll: ScrollContainer
var dlg_text: RichTextLabel
var dlg_opts_scroll: ScrollContainer
var dlg_opts: VBoxContainer

var screen := "city" # city | loc | promises | journal | paper
var first_show := true


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	build_chrome()
	Game.state_changed.connect(refresh)
	Game.day_started.connect(_on_day_started)
	Game.game_ended.connect(_on_game_ended)
	refresh()
	show_city()
	if first_show:
		first_show = false
		show_popup("Депутат: 7 дней до выборов", Game.morning_brief() + "\n\nКак играть: нажимай на локации → говори с людьми → собирай информацию → давай обещания → печатай и разноси листовки → выполняй обещания. Время 08:00–20:00. Поездки и разговоры тратят время и деньги.")


func big_font(lbl: Label, size: int) -> void:
	lbl.add_theme_font_size_override("font_size", size)


func mk_button(text: String, fsize: int = 19) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", fsize)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func mk_label(text: String, size: int = 18) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func build_chrome() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# HUD
	var hud := PanelContainer.new()
	root.add_child(hud)
	var hv := VBoxContainer.new()
	hud.add_child(hv)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 12)
	hv.add_child(row1)
	hud_day = mk_label("ДЕНЬ", 20)
	hud_time = mk_label("08:00", 20)
	hud_money = mk_label("€", 20)
	hud_leaf = mk_label("", 18)
	hud_prom = mk_label("", 18)
	row1.add_child(hud_day)
	row1.add_child(hud_time)
	row1.add_child(hud_money)
	row1.add_child(hud_leaf)
	row1.add_child(hud_prom)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	hv.add_child(nav)
	var specs := [["🗺 Карта", "city"], ["📰 Газета", "paper"], ["📝 Обещания", "promises"], ["📓 Журнал", "journal"], ["🎓 Задачи", "tasks"]]
	for s in specs:
		var b := mk_button(s[0], 16)
		b.pressed.connect(_on_nav.bind(s[1]))
		nav.add_child(b)
	var sleep_b := mk_button("😴 Спать", 16)
	sleep_b.pressed.connect(_on_sleep)
	nav.add_child(sleep_b)
	# Строка текущей задачи обучения — всегда на виду.
	task_label = mk_label("", 16)
	hv.add_child(task_label)

	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)

	# нижняя строка сейвов
	var saverow := HBoxContainer.new()
	saverow.add_theme_constant_override("separation", 6)
	root.add_child(saverow)
	var bs := mk_button("💾 Сохранить")
	bs.pressed.connect(func() -> void: show_popup("Сохранение", Game.save_game()))
	var bl := mk_button("📂 Загрузить")
	bl.pressed.connect(func() -> void:
		sup_tut = true
		var msg2: String = Game.load_game()
		last_tut_step = int(Game.tut.get("step", 0))
		screen = "city"
		show_city()
		show_popup("Загрузка", msg2))
	var br := mk_button("🔄 Заново")
	br.pressed.connect(_on_restart)
	saverow.add_child(bs)
	saverow.add_child(bl)
	saverow.add_child(br)

	build_popup()
	build_dialogue()


func view_size() -> Vector2:
	var vs := get_viewport_rect().size
	if vs.x <= 0.0 or vs.y <= 0.0:
		vs = Vector2(1280, 720)
	return vs


var _blur_mat: ShaderMaterial
var _bbcs: Array = []


func get_blur_material() -> ShaderMaterial:
	# Общий материал «backdrop blur»: размытие + затемнение фона под модалкой.
	if _blur_mat == null:
		var sh := Shader.new()
		sh.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float radius : hint_range(0.0, 6.0) = 3.0;
uniform vec4 tint : source_color = vec4(0.02, 0.02, 0.05, 0.55);
void fragment() {
	vec2 step = radius * SCREEN_PIXEL_SIZE;
	vec3 acc = texture(screen_tex, SCREEN_UV).rgb * 0.2;
	acc += texture(screen_tex, SCREEN_UV + vec2(step.x, 0.0)).rgb * 0.1;
	acc += texture(screen_tex, SCREEN_UV - vec2(step.x, 0.0)).rgb * 0.1;
	acc += texture(screen_tex, SCREEN_UV + vec2(0.0, step.y)).rgb * 0.1;
	acc += texture(screen_tex, SCREEN_UV - vec2(0.0, step.y)).rgb * 0.1;
	acc += texture(screen_tex, SCREEN_UV + step).rgb * 0.1;
	acc += texture(screen_tex, SCREEN_UV - step).rgb * 0.1;
	acc += texture(screen_tex, SCREEN_UV + vec2(step.x, -step.y)).rgb * 0.1;
	acc += texture(screen_tex, SCREEN_UV + vec2(-step.x, step.y)).rgb * 0.1;
	vec3 col = mix(acc, tint.rgb, tint.a);
	COLOR = vec4(col, 1.0);
}
"""
		_blur_mat = ShaderMaterial.new()
		_blur_mat.shader = sh
	return _blur_mat


func modal_style() -> StyleBoxFlat:
	# Полностью непрозрачная плашка: никакой текст из-под неё не просвечивает.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.14, 1.0)
	sb.set_border_width_all(2)
	sb.border_color = Color(1.0, 1.0, 1.0, 0.28)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.shadow_size = 14
	sb.content_margin_left = 4.0
	sb.content_margin_right = 4.0
	return sb


func make_modal_shell(width: float) -> Dictionary:
	# Возвращает {wrap, panel, box}: блюр+затемнение фона, затем панель + VBox.
	var wrap := Control.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.visible = false
	add_child(wrap)
	# BackBufferCopy обязателен для SCREEN_TEXTURE в Compatibility-рендере.
	# Это Node2D: область копии задаётся rect, а не якорями.
	var bbc := BackBufferCopy.new()
	bbc.rect = Rect2(Vector2.ZERO, view_size())
	wrap.add_child(bbc)
	_bbcs.append(bbc)
	var blur := ColorRect.new()
	blur.color = Color.WHITE
	blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur.material = get_blur_material()
	wrap.add_child(blur)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.add_theme_stylebox_override("panel", modal_style())
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	return {"wrap": wrap, "panel": panel, "box": box}


func make_text_scroll(font_size: int) -> Dictionary:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", font_size)
	sc.add_child(rt)
	return {"scroll": sc, "text": rt}


func build_popup() -> void:
	var shell := make_modal_shell(620.0)
	popup = shell["wrap"]
	popup_panel = shell["panel"]
	var box: VBoxContainer = shell["box"]
	popup_title = mk_label("Заголовок", 22)
	box.add_child(popup_title)
	var ts := make_text_scroll(18)
	popup_scroll = ts["scroll"]
	popup_text = ts["text"]
	box.add_child(popup_scroll)
	var close := mk_button("Понятно (закрыть)")
	close.pressed.connect(func() -> void: popup.visible = false)
	box.add_child(close)
	get_tree().root.size_changed.connect(_fit_modals)


func build_dialogue() -> void:
	var shell := make_modal_shell(640.0)
	dlg_panel = shell["wrap"]
	dlg_inner = shell["panel"]
	var box: VBoxContainer = shell["box"]
	dlg_title = mk_label("Диалог", 22)
	box.add_child(dlg_title)
	var ts := make_text_scroll(19)
	dlg_scroll = ts["scroll"]
	dlg_text = ts["text"]
	box.add_child(dlg_scroll)
	dlg_opts_scroll = ScrollContainer.new()
	dlg_opts_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(dlg_opts_scroll)
	dlg_opts = VBoxContainer.new()
	dlg_opts.add_theme_constant_override("separation", 6)
	dlg_opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dlg_opts_scroll.add_child(dlg_opts)
	var leave := mk_button("Уйти")
	leave.pressed.connect(func() -> void: dlg_panel.visible = false)
	box.add_child(leave)


## Ограничить модалки вьюпортом и подогнать высоту текста под контент.
func _fit_modals() -> void:
	var vs := view_size()
	for b in _bbcs:
		(b as BackBufferCopy).rect = Rect2(Vector2.ZERO, vs)
	if is_instance_valid(popup_panel):
		var w: float = minf(620.0, vs.x * 0.94)
		popup_panel.custom_minimum_size = Vector2(w, 0)
		_fit_text_box(popup_scroll, popup_text, Vector2(maxf(w - 64.0, 220.0), minf(360.0, vs.y * 0.45)))
	if is_instance_valid(dlg_inner):
		var w2: float = minf(640.0, vs.x * 0.94)
		dlg_inner.custom_minimum_size = Vector2(w2, 0)
		_fit_text_box(dlg_scroll, dlg_text, Vector2(maxf(w2 - 64.0, 220.0), minf(220.0, vs.y * 0.28)))
		dlg_opts_scroll.custom_minimum_size = Vector2(maxf(w2 - 64.0, 220.0), minf(260.0, vs.y * 0.32))


func _fit_text_box(sc: ScrollContainer, rt: RichTextLabel, box_size: Vector2) -> void:
	# Высота по контенту, но не больше лимита — остальное крутится скроллом.
	var need: float = rt.get_content_height() + 12.0
	sc.custom_minimum_size = Vector2(box_size.x, clampf(need, 70.0, box_size.y))


func show_popup(title: String, text: String) -> void:
	popup_title.text = title
	popup_text.text = "[color=white]" + escape_bb(text) + "[/color]"
	popup.visible = true
	move_child(popup, get_child_count() - 1)
	_fit_modals()
	# контент уже разложен на следующем кадре — пересчитать высоту точно
	_fit_modals.call_deferred()


func show_dialogue() -> void:
	dlg_panel.visible = true
	move_child(dlg_panel, get_child_count() - 1)
	_fit_modals()
	_fit_modals.call_deferred()


func escape_bb(s: String) -> String:
	return s.replace("[", "［").replace("]", "］")


func clear_content() -> void:
	for c in content.get_children():
		c.queue_free()


# ---------- навигация ----------

func _on_nav(where: String) -> void:
	if Game.game_over:
		show_popup("Итоги", Game.election_text())
		return
	screen = where
	if where == "city":
		show_city()
	elif where == "paper":
		show_paper()
	elif where == "promises":
		show_promises()
	elif where == "journal":
		show_journal()
	elif where == "tasks":
		show_tasks()


func _on_sleep() -> void:
	if Game.game_over:
		show_popup("Итоги", Game.election_text())
		return
	var summary: String = Game.end_day()
	if Game.game_over:
		return # game_ended покажет итоги
	show_popup("Ночь → утро", summary + "\n\n---\n" + Game.morning_brief())
	show_city()


func _on_restart() -> void:
	sup_tut = true
	Game.reset_run()
	last_tut_step = 0
	screen = "city"
	show_city()
	show_popup("Новая игра", Game.morning_brief())


func _on_day_started(_d: int) -> void:
	pass # утренний брифинг уже показан через end_day popup


func _on_game_ended(_win: bool) -> void:
	show_popup("🗳 Выборы!", Game.election_text() + "\n\nНажми «🔄 Заново» внизу, чтобы сыграть ещё раз.")


func refresh() -> void:
	hud_day.text = "%s\nДень %d/7" % [Game.day_name(), Game.day]
	hud_time.text = "⏰ " + Game.time_str() + "\n(ост. %d мин)" % Game.minutes_left()
	hud_money.text = "💰 %d€" % Game.money
	hud_leaf.text = "📄 Листовки: %d" % Game.leaflets
	hud_prom.text = "📝 Активных: %d" % Game.active_promises().size()
	refresh_tutorial()
	# перерисовать текущий экран без потери места
	if screen == "city" and not Game.game_over:
		pass


## Обучение: строка текущей задачи + попап при выполнении шага.
func refresh_tutorial() -> void:
	var ts: int = int(Game.tut.get("step", 0))
	var done: bool = bool(Game.tut.get("done", false))
	var skipped: bool = bool(Game.tut.get("skipped", false))
	if sup_tut:
		sup_tut = false
		last_tut_step = ts
	elif last_tut_step < 0:
		last_tut_step = ts
	elif ts != last_tut_step and not skipped and not Game.game_over:
		if ts > last_tut_step:
			var msg := ""
			if last_tut_step < Game.TUTORIAL.size():
				var fin: Dictionary = Game.TUTORIAL[last_tut_step]
				msg += "✅ Выполнено: %s\n\n" % str(fin.get("title", ""))
			if done:
				msg += "🎓 Обучение пройдено! Дальше сам: следи за повесткой, выполняй обещания и выиграй выборы в день 7."
			else:
				var nxt: Dictionary = Game.TUTORIAL[ts]
				msg += "➡ Задача %d/%d: %s\n%s" % [ts + 1, Game.TUTORIAL.size(), str(nxt.get("title", "")), str(nxt.get("hint", ""))]
			if not dlg_panel.visible and not popup.visible:
				show_popup("🎓 Обучение", msg)
		last_tut_step = ts
	# Строка текущей цели под навигацией.
	if skipped:
		task_label.visible = false
	elif done:
		task_label.visible = true
		task_label.text = "🎓 Обучение пройдено ✅ (подробности: 🎓 Задачи)"
	else:
		task_label.visible = true
		var cur: Dictionary = Game.tut_current()
		if cur.is_empty():
			task_label.visible = false
		else:
			task_label.text = "🎓 %d/%d: %s (подробности: 🎓 Задачи)" % [ts + 1, Game.TUTORIAL.size(), str(cur.get("title", ""))]


# ---------- экраны ----------

func show_city() -> void:
	screen = "city"
	clear_content()
	content.add_child(mk_label("🗺 КАРТА ГОРОДА — куда идём?", 24))
	content.add_child(mk_label("Нажми на место. Поездка тратит время и деньги. Сейчас ты: %s %s." % [Game.loc_icon(Game.current_location), Game.location_name(Game.current_location)], 18))
	var grid := GridContainer.new()
	grid.columns = 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)
	for l in Game.D.get("locations", {}).get("locations", []):
		var lid := str(l["id"])
		var c: Array = Game.travel_cost(Game.current_location, lid)
		var tag := " (ты здесь)" if lid == Game.current_location else " — %d мин, %d€" % [int(c[0]), int(c[1])]
		var b := mk_button("%s %s%s\n%s" % [str(l.get("icon", "")), str(l.get("name", "")), tag, str(l.get("desc", ""))])
		b.pressed.connect(_on_travel.bind(lid))
		grid.add_child(b)
	content.add_child(mk_label("📊 Повестка дня:", 20))
	content.add_child(mk_label(Game.agenda_line(), 18))
	content.add_child(mk_label("💡 " + Game.location_flavor(Game.current_location), 17))
	var cur := mk_button("📍 Осмотреть: " + Game.location_name(Game.current_location))
	cur.pressed.connect(func() -> void: show_location(Game.current_location))
	content.add_child(cur)


func _on_travel(lid: String) -> void:
	var msg: String = Game.travel_to(lid)
	if lid == Game.current_location or Game.current_location == lid:
		pass
	show_popup("Переезд", msg)
	show_location(Game.current_location)


func show_location(lid: String) -> void:
	screen = "loc"
	clear_content()
	content.add_child(mk_label("%s %s" % [Game.loc_icon(lid), Game.location_name(lid)], 24))
	content.add_child(mk_label(Game.location_flavor(lid), 18))
	# особые действия офиса
	if lid == "office":
		content.add_child(mk_label("🧰 Действия штаба:", 20))
		var bp := mk_button("🖨 Напечатать 100 листовок (30 мин, 150€)")
		bp.pressed.connect(func() -> void: show_popup("Типография", Game.print_leaflets()))
		content.add_child(bp)
		var bs := mk_button("📓 Изучить заметки (10 мин)")
		bs.pressed.connect(func() -> void: show_popup("Заметки", Game.study_notes()))
		content.add_child(bs)
	if lid == "district":
		content.add_child(mk_label("📣 Агитация в районе:", 20))
		var b1 := mk_button("📨 Раздавать лично (60 мин, −100 шт, эффективно)")
		b1.pressed.connect(func() -> void: show_popup("Агитация", Game.distribute("hand")))
		content.add_child(b1)
		var b2 := mk_button("📦 Массовый разброс (20 мин, −100 шт, слабый эффект)")
		b2.pressed.connect(func() -> void: show_popup("Агитация", Game.distribute("mass")))
		content.add_child(b2)
	content.add_child(mk_label("🧍 Люди здесь:", 20))
	var npcs: Array = Game.available_npcs_at(lid)
	if npcs.is_empty():
		content.add_child(mk_label("Никого нет.", 18))
	for n in npcs:
		var avail: bool = Game.npc_available(n)
		var status := "на месте" if avail else "сейчас нет (часы %d–%d)" % [int(n.get("from", 8)), int(n.get("to", 20))]
		var b := mk_button("%s %s — %s (%s)" % [str(n.get("emoji", "🧍")), str(n.get("name", "")), str(n.get("profession", "")), status])
		b.disabled = not avail
		b.pressed.connect(_on_talk.bind(str(n["id"])))
		content.add_child(b)
	# доступные обещания, связанные с этим местом
	content.add_child(mk_label("📝 Обещания, которые тут ждут:", 20))
	var hints := 0
	for tid in Game.unlocked_promises:
		var t := Game.template_by_id(tid)
		if t.is_empty():
			continue
		var already := false
		for p in Game.promises:
			if p["template"] == tid and p["status"] in ["promised", "progress"]:
				already = true
		if already:
			continue
		hints += 1
		var extra := " ⚠ нужна поддержка Кольцова" if bool(t.get("needs_kol", false)) else ""
		var b := mk_button("«%s» — %d€, %d мин%s" % [str(t["title"]), int(t["cost"]), int(t["time_cost"]), extra])
		b.pressed.connect(_on_promise.bind(tid))
		content.add_child(b)
	if hints == 0:
		content.add_child(mk_label("Поговори с людьми, чтобы открыть новые обещания.", 17))
	var back := mk_button("⬅ На карту города")
	back.pressed.connect(show_city)
	content.add_child(back)


func _on_talk(nid: String) -> void:
	var n := Game.npc_by_id(nid)
	if n.is_empty():
		return
	var dlg := Game.dialogue_by_id(str(n.get("dialogue", "")))
	if dlg.is_empty():
		show_popup("Разговор", "Не о чем говорить.")
		return
	dlg_title.text = "%s %s — %s" % [str(n.get("emoji", "")), str(n.get("name", "")), str(n.get("profession", ""))]
	dlg_text.text = "[color=white]" + escape_bb(str(dlg.get("npc_text", ""))) + "[/color]\n[color=gray]Разговор займёт ~%d мин.[/color]" % int(dlg.get("time_cost", 20))
	Game.note_dialogue_shown(dlg)
	Game.drain_unlocks()
	for c in dlg_opts.get_children():
		c.queue_free()
	for opt in dlg.get("options", []):
		var ob := mk_button(str(opt.get("text", "...")))
		ob.pressed.connect(_on_dialogue_choice.bind(nid, dlg, opt))
		dlg_opts.add_child(ob)
	show_dialogue()


func _on_dialogue_choice(nid: String, dlg: Dictionary, opt: Dictionary) -> void:
	dlg_panel.visible = false
	var res: String = Game.apply_dialogue(nid, dlg, opt)
	show_popup("Разговор", res)
	show_location(Game.current_location)


func _on_promise(tid: String) -> void:
	var msg: String = Game.make_promise(tid)
	show_popup("Обещание", msg)


func show_promises() -> void:
	screen = "promises"
	clear_content()
	content.add_child(mk_label("📝 ОБЕЩАНИЯ — старые не исчезают!", 24))
	content.add_child(mk_label("Дать обещание: 15 мин на решение. Выполнение тратит деньги и время. Дедлайн — до выборов.", 17))
	content.add_child(mk_label("Доступно для обещания:", 20))
	var any_new := false
	for tid in Game.unlocked_promises:
		var t := Game.template_by_id(tid)
		if t.is_empty():
			continue
		var dup := false
		for p in Game.promises:
			if p["template"] == tid and p["status"] in ["promised", "progress", "completed"]:
				dup = true
		if dup:
			continue
		any_new = true
		var extra := " ⚠ нужна поддержка Кольцова" if bool(t.get("needs_kol", false)) else ""
		content.add_child(mk_label("«%s» — %s. Тема: %s. Аудитория: %s. %d€, %d мин%s." % [str(t["title"]), str(t["desc"]), Game.topic_name(str(t["topic"])), Game.sj(", ", t["audience"]), int(t["cost"]), int(t["time_cost"]), extra], 17))
		var b := mk_button("Пообещать: " + str(t["title"]))
		b.pressed.connect(_on_promise.bind(tid))
		content.add_child(b)
	if not any_new:
		content.add_child(mk_label("Новых нет. Говори с людьми — откроются новые.", 17))
	content.add_child(mk_label("Активные:", 20))
	var act := Game.active_promises()
	if act.is_empty():
		content.add_child(mk_label("Нет активных обещаний.", 17))
	for p in act:
		var left: int = int(p["deadline"]) - Game.day
		content.add_child(mk_label("«%s» — день %d → дедлайн день %d (осталось %d дн.). Память: %d/100. Статус: %s." % [p["title"], int(p["created_day"]), int(p["deadline"]), left, int(p.get("memory", 50)), p["status"]], 17))
		var cost_show := int(p["cost"])
		if str(p["template"]) == "p_roads" and Game.day >= 6:
			cost_show += 300
		var bf := mk_button("✅ Выполнить (−%d€, −%d мин)" % [cost_show, int(p["ftime"])])
		bf.pressed.connect(_on_fulfill.bind(str(p["uid"])))
		content.add_child(bf)
	content.add_child(mk_label("Закрытые:", 20))
	for p in Game.promises:
		if p["status"] in ["completed", "broken", "forgotten"]:
			var icon := "✅" if p["status"] == "completed" else "❌"
			content.add_child(mk_label("%s «%s» — %s" % [icon, p["title"], p["status"]], 17))


func _on_fulfill(uid: String) -> void:
	show_popup("Выполнение", Game.fulfill_promise(uid))
	show_promises()


func show_journal() -> void:
	screen = "journal"
	Game.note_ui("journal")
	clear_content()
	content.add_child(mk_label("📓 ЖУРНАЛ: информация → прогноз", 24))
	content.add_child(mk_label(Game.journal_text(), 18))
	content.add_child(mk_label("📊 Повестка:", 20))
	for tid in Game.agenda.keys():
		var v := int(Game.agenda[tid])
		content.add_child(mk_label("%s %s: %d/100 — %s" % [Game.topic_icon(tid), Game.topic_name(tid), v, Game.agenda_stage(v)], 18))
	content.add_child(mk_label("🤝 Отношения и поддержка:", 20))
	var lines := []
	for nid in Game.rel.keys():
		var n := Game.npc_by_id(str(nid))
		if n.is_empty():
			continue
		lines.append("%s %s: %d" % [str(n.get("emoji", "")), str(n.get("name", "")), int(Game.rel[nid])])
	content.add_child(mk_label(Game.sj("\n", lines), 17))
	var sup := []
	for g in Game.support.keys():
		sup.append("%s: %d" % [Game.GROUP_NAMES.get(str(g), str(g)), int(Game.support[g])])
	content.add_child(mk_label("Поддержка групп:\n" + Game.sj("\n", sup), 17))
	if bool(Game.flags.get("kol_support", false)):
		content.add_child(mk_label("🤝 Поддержка Кольцова: ЕСТЬ", 18))
	else:
		content.add_child(mk_label("🤝 Поддержка Кольцова: нет (договорись в мэрии)", 18))


func show_paper() -> void:
	screen = "paper"
	clear_content()
	content.add_child(mk_label("📰 «Городской вестник»", 24))
	var p := Game.today_paper()
	if p.is_empty():
		content.add_child(mk_label("Сегодня выпуска нет.", 18))
	else:
		content.add_child(mk_label("День %d: %s" % [int(p.get("day", 1)), str(p.get("headline", ""))], 22))
		content.add_child(mk_label(str(p.get("body", "")), 19))
	content.add_child(mk_label("Читай между строк: газета показывает, что станет повесткой. Кто узнал раньше (от журналистов, чиновников) — тот успел пообещать первым.", 17))


func show_tasks() -> void:
	screen = "tasks"
	clear_content()
	content.add_child(mk_label("🎓 ЗАДАЧИ — обучение механикам", 24))
	var done: bool = bool(Game.tut.get("done", false))
	var skipped: bool = bool(Game.tut.get("skipped", false))
	var step: int = int(Game.tut.get("step", 0))
	if done:
		content.add_child(mk_label("🎓 Обучение пройдено! Ты освоил: диалоги, поездки, журнал, обещания, листовки, выполнение и смену дней. Дальше — сам.", 18))
	if skipped:
		content.add_child(mk_label("Обучение пропущено. Задачи ниже — просто шпаргалка по механикам.", 18))
		var back := mk_button("↩ Вернуть обучение")
		back.pressed.connect(func() -> void:
			Game.unskip_tutorial()
			show_tasks())
		content.add_child(back)
	for i in Game.TUTORIAL.size():
		var s: Dictionary = Game.TUTORIAL[i]
		var icon := "·"
		if done or i < step:
			icon = "✅"
		elif i == step and not skipped:
			icon = "➡"
		content.add_child(mk_label("%s %d/%d: %s" % [icon, i + 1, Game.TUTORIAL.size(), str(s.get("title", ""))], 19))
		content.add_child(mk_label(str(s.get("hint", "")), 16))
	if not done and not skipped:
		var skip := mk_button("Пропустить обучение")
		skip.pressed.connect(func() -> void:
			Game.skip_tutorial()
			show_city())
		content.add_child(skip)
