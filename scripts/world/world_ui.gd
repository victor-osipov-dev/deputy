class_name WorldUI
extends CanvasLayer
## Весь интерфейс мира: HUD, подсказки, телефон, диалоги, ночь, выборы, меню.

var base = null

var hud_day: Label
var hud_money: Label
var hud_obj: Label
var prompt_btn: Button
var phone_btn: Button
var menu_btn: Button
var stick: TouchStick
var toast_box: VBoxContainer

var dim_layer: CanvasLayer
var dlg_wrap: Control
var dlg_panel: PanelContainer
var dlg_title: Label
var dlg_remind: Label
var dlg_text_scroll: ScrollContainer
var dlg_text: RichTextLabel
var dlg_opts_scroll: ScrollContainer
var dlg_opts: VBoxContainer
var dlg_npc := ""
var dlg_data := {}

var phone_wrap: Control
var phone_tabs: HBoxContainer
var phone_body: VBoxContainer
var phone_tab := "map"

var night_wrap: Control
var night_title: Label
var night_text: RichTextLabel

var elect_wrap: Control
var elect_text: RichTextLabel

var menu_wrap: Control

var _blur_mat: ShaderMaterial


func build() -> void:
	layer = 10
	_build_hud()
	_build_toasts()
	_build_prompt()
	_build_touch()
	_build_dialog()
	_build_phone()
	_build_night()
	_build_elect()
	_build_menu()


# ---------- база ----------

func _mk_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _mk_button(text: String, fsize: int = 19) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 54)
	b.add_theme_font_size_override("font_size", fsize)
	return b


func get_blur() -> ShaderMaterial:
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


func modal_shell(width: float) -> Dictionary:
	var wrap := Control.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.visible = false
	add_child(wrap)
	var bbc := BackBufferCopy.new()
	bbc.rect = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	wrap.add_child(bbc)
	var blur := ColorRect.new()
	blur.color = Color.WHITE
	blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur.material = get_blur()
	wrap.add_child(blur)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.14, 1.0)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.28)
	sb.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", sb)
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


func blocks_world() -> bool:
	for w in [dlg_wrap, phone_wrap, night_wrap, elect_wrap, menu_wrap]:
		if is_instance_valid(w) and w.visible:
			return true
	return false


# ---------- HUD ----------

func _build_hud() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 12
	top.offset_right = -12
	top.offset_top = 8
	top.add_theme_constant_override("separation", 16)
	add_child(top)
	hud_day = _mk_label("", 20)
	top.add_child(hud_day)
	hud_obj = _mk_label("", 17)
	hud_obj.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud_obj.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(hud_obj)
	hud_money = _mk_label("", 20)
	top.add_child(hud_money)
	phone_btn = _mk_button("📱", 26)
	phone_btn.custom_minimum_size = Vector2(64, 54)
	phone_btn.pressed.connect(toggle_phone)
	top.add_child(phone_btn)
	menu_btn = _mk_button("☰", 26)
	menu_btn.custom_minimum_size = Vector2(64, 54)
	menu_btn.pressed.connect(toggle_menu)
	top.add_child(menu_btn)


func refresh_hud() -> void:
	hud_day.text = "День %d/7 • %s" % [Game.day, Game.time_str()]
	hud_money.text = "€%d • 📄%d" % [Game.money, Game.leaflets]
	refresh_objective()


func refresh_objective() -> void:
	var o: Dictionary = Game.current_objective()
	hud_obj.text = "➤ %s" % str(o.get("title", ""))


func _build_toasts() -> void:
	toast_box = VBoxContainer.new()
	toast_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast_box.offset_left = -380
	toast_box.offset_right = 380
	toast_box.offset_top = -260
	toast_box.offset_bottom = -120
	toast_box.add_theme_constant_override("separation", 6)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_box)


func toast(text: String) -> void:
	while toast_box.get_child_count() >= 3:
		toast_box.get_child(0).queue_free()
	var l := _mk_label(text, 17)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_box.add_child(l)
	var tw := create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func _build_prompt() -> void:
	prompt_btn = _mk_button("", 20)
	prompt_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_btn.offset_left = -300
	prompt_btn.offset_right = 300
	prompt_btn.offset_top = -110
	prompt_btn.offset_bottom = -50
	prompt_btn.visible = false
	prompt_btn.pressed.connect(func() -> void:
		if base.target != null:
			base.do_interact(base.target))
	add_child(prompt_btn)


func set_prompt(text: String, _target) -> void:
	if text == "":
		prompt_btn.visible = false
	else:
		prompt_btn.visible = true
		if DisplayServer.is_touchscreen_available():
			prompt_btn.text = text
		else:
			prompt_btn.text = "E — " + text


func _build_touch() -> void:
	stick = TouchStick.new()
	stick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	stick.offset_left = 30
	stick.offset_top = -260
	stick.offset_right = 260
	stick.offset_bottom = -30
	stick.visible = DisplayServer.is_touchscreen_available()
	add_child(stick)


# ---------- диалог ----------

func _build_dialog() -> void:
	var s := modal_shell(640.0)
	dlg_wrap = s["wrap"]
	dlg_panel = s["panel"]
	var box: VBoxContainer = s["box"]
	dlg_title = _mk_label("Диалог", 22)
	box.add_child(dlg_title)
	dlg_remind = _mk_label("", 17)
	dlg_remind.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	box.add_child(dlg_remind)
	dlg_text_scroll = ScrollContainer.new()
	dlg_text_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(dlg_text_scroll)
	dlg_text = RichTextLabel.new()
	dlg_text.bbcode_enabled = true
	dlg_text.fit_content = true
	dlg_text.scroll_active = false
	dlg_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dlg_text.add_theme_font_size_override("normal_font_size", 19)
	dlg_text_scroll.add_child(dlg_text)
	dlg_opts_scroll = ScrollContainer.new()
	dlg_opts_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(dlg_opts_scroll)
	dlg_opts = VBoxContainer.new()
	dlg_opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dlg_opts.add_theme_constant_override("separation", 6)
	dlg_opts_scroll.add_child(dlg_opts)
	var leave := _mk_button("Уйти")
	leave.pressed.connect(func() -> void: dlg_wrap.visible = false)
	box.add_child(leave)


## Высота скроллов по контенту: нет пустого места и лишних скроллбаров.
func _fit_dialog() -> void:
	var vs := get_viewport().get_visible_rect().size
	if vs.x <= 0.0:
		vs = Vector2(1280, 720)
	dlg_panel.custom_minimum_size = Vector2(minf(640.0, vs.x * 0.94), 0)
	var w := minf(600.0, vs.x * 0.94 - 60.0)
	var need_t: float = dlg_text.get_content_height() + 12.0
	dlg_text_scroll.custom_minimum_size = Vector2(w, clampf(need_t, 60.0, minf(300.0, vs.y * 0.38)))
	var n := dlg_opts.get_child_count()
	if n <= 0:
		dlg_opts_scroll.visible = false
	else:
		dlg_opts_scroll.visible = true
		dlg_opts_scroll.custom_minimum_size = Vector2(w, clampf(n * 60.0, 60.0, minf(300.0, vs.y * 0.34)))


func open_dialog(npc_id: String) -> void:
	var n := Game.npc_by_id(npc_id)
	if n.is_empty():
		return
	var dlg := Game.dialogue_by_id(str(n.get("dialogue", "")))
	if dlg.is_empty():
		toast("Не о чем говорить.")
		return
	dlg_npc = npc_id
	dlg_data = dlg
	dlg_title.text = "%s %s — %s" % [str(n.get("emoji", "")), str(n.get("name", "")), str(n.get("profession", ""))]
	var rem := Game.reminder_for(npc_id)
	if rem.is_empty():
		dlg_remind.visible = false
	else:
		dlg_remind.visible = true
		dlg_remind.text = "«Вы же обещали: %s. Когда сделаете?»" % str(rem.get("title", ""))
	dlg_text.text = "[color=white]%s[/color]\n[color=gray](~%d мин)[/color]" % [_ebb(str(dlg.get("npc_text", ""))), int(dlg.get("time_cost", 20))]
	for nt in Game.note_dialogue_shown(dlg):
		toast(nt)
	for t in Game.drain_unlocks():
		toast(t)
	_fill_options()
	dlg_wrap.visible = true
	_fit_dialog()
	_fit_dialog.call_deferred()


func _ebb(s: String) -> String:
	return s.replace("[", "［").replace("]", "］")


func _fill_options() -> void:
	for c in dlg_opts.get_children():
		dlg_opts.remove_child(c)
		c.queue_free()
	for opt in dlg_data.get("options", []):
		var lock := Game.rel_gate(opt, dlg_npc)
		var b := _mk_button(str(opt.get("text", "...")))
		if lock != "":
			b.text = "🔒 " + b.text + " (%s)" % lock
			b.disabled = true
		else:
			b.pressed.connect(_on_dlg_choice.bind(opt))
		dlg_opts.add_child(b)
	if _can_hand():
		var hb := _mk_button("📨 Вручить листовку лично")
		hb.pressed.connect(_on_hand)
		dlg_opts.add_child(hb)


func _can_hand() -> bool:
	return Game.is_unlocked("campaigning") and Game.leaflets >= 50 and not Game.active_promises().is_empty() and Game.minutes_left() >= 60


func _on_hand() -> void:
	dlg_wrap.visible = false
	base._after_action(Game.distribute("hand"))
	base._drain_unlocks()
	toast("📨 Листовка вручена лично.")


func _on_dlg_choice(opt: Dictionary) -> void:
	var res: String = Game.apply_dialogue(dlg_npc, dlg_data, opt)
	for c in dlg_opts.get_children():
		dlg_opts.remove_child(c)
		c.queue_free()
	dlg_text.text = "[color=white]%s[/color]" % _ebb(res)
	# Кнопка «Уйти» уже есть внизу панели — вторую не добавляем.
	_fit_dialog()
	_fit_dialog.call_deferred()
	for t in Game.drain_unlocks():
		toast(t)
	refresh_objective()
	base._after_action("")


# ---------- телефон ----------

func _build_phone() -> void:
	var s := modal_shell(640.0)
	phone_wrap = s["wrap"]
	var box: VBoxContainer = s["box"]
	var title := _mk_label("📱 Телефон депутата", 22)
	box.add_child(title)
	phone_tabs = HBoxContainer.new()
	phone_tabs.add_theme_constant_override("separation", 6)
	box.add_child(phone_tabs)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(560, 320)
	box.add_child(sc)
	phone_body = VBoxContainer.new()
	phone_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phone_body.add_theme_constant_override("separation", 8)
	sc.add_child(phone_body)
	var close := _mk_button("Закрыть")
	close.pressed.connect(func() -> void: phone_wrap.visible = false)
	box.add_child(close)


func toggle_phone() -> void:
	if phone_wrap.visible:
		phone_wrap.visible = false
		return
	phone_tab = "map"
	_draw_phone()
	phone_wrap.visible = true


func _draw_phone() -> void:
	for c in phone_tabs.get_children():
		c.queue_free()
	for c in phone_body.get_children():
		c.queue_free()
	var tabs := [["🗺 Карта", "map", true]]
	tabs.append(["📓 Блокнот", "notes", Game.is_unlocked("notebook")])
	tabs.append(["📝 Обещания", "promises", Game.is_unlocked("promises")])
	tabs.append(["📰 Газета", "paper", Game.is_unlocked("newspaper")])
	for t in tabs:
		var b := _mk_button(t[0], 16)
		b.disabled = not t[2]
		b.pressed.connect(_on_phone_tab.bind(t[1]))
		phone_tabs.add_child(b)
	if phone_tab == "map":
		_phone_map()
	elif phone_tab == "notes":
		_phone_notes()
	elif phone_tab == "promises":
		_phone_promises()
	elif phone_tab == "paper":
		_phone_paper()


func _on_phone_tab(t: String) -> void:
	phone_tab = t
	_draw_phone()


func _plabel(text: String, size: int = 18) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _phone_map() -> void:
	if Game.current_location == "city" or Game.current_location == "district":
		phone_body.add_child(_plabel("🗺 Город. Ты на улицах.", 19))
	else:
		phone_body.add_child(_plabel("🗺 Город. Ты здесь: %s." % Game.location_name(Game.current_location), 19))
	for l in Game.D.get("locations", {}).get("locations", []):
		var mark := "✓" if str(l["id"]) in Game.visited else "·"
		phone_body.add_child(_plabel("%s %s %s — %s" % [mark, str(l.get("icon", "")), str(l.get("name", "")), str(l.get("desc", ""))], 17))
	phone_body.add_child(_plabel("🚌 Автобус между Центром и Районом: 8 мин, 5€.", 16))


func _phone_notes() -> void:
	phone_body.add_child(_plabel(Game.journal_notebook(), 17))


func _phone_promises() -> void:
	var act := Game.active_promises()
	if is_unlocked_budget_line():
		phone_body.add_child(_plabel("💰 Офисный бюджет: €%d. Большие траты — через совет." % Game.money, 17))
	if act.is_empty():
		phone_body.add_child(_plabel("Активных обещаний нет. Их дают в разговорах.", 17))
	for p in act:
		var left: int = int(p["deadline"]) - Game.day
		phone_body.add_child(_plabel("«%s» — до дня %d (осталось %d дн.), %d€." % [p["title"], int(p["deadline"]), left, int(p["cost"])], 17))
		var bf := _mk_button("✅ Выполнить (−%d€)" % int(p["cost"]))
		bf.pressed.connect(_on_fulfill.bind(str(p["uid"])))
		phone_body.add_child(bf)
	phone_body.add_child(_plabel("Где пообещать (подойди лично):", 18))
	var any := false
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
		any = true
		var extra := " ⚠ нужен Кольцов" if bool(t.get("needs_kol", false)) else ""
		phone_body.add_child(_plabel("«%s» (%d€%s)\n➤ %s" % [str(t["title"]), int(t["cost"]), extra, _who_gives(tid)], 16))
	if not any:
		phone_body.add_child(_plabel("Новых нет — говори с людьми.", 16))


## Справочник: у кого и где даётся обещание (без удалённой выдачи).
func _who_gives(tid: String) -> String:
	var parts := []
	for n in Game.D.get("npcs", {}).get("npcs", []):
		if tid in n.get("promises", []):
			var post: Dictionary = Game.npc_where(str(n.get("id", "")))
			if post.is_empty():
				parts.append("%s (сейчас не найти — обычно: %s)" % [str(n.get("name", "?")), Game.location_name(str(n.get("location", "")))])
			elif str(post.get("loc", "")) in ["city", "district"]:
				parts.append("%s (сейчас: на улицах, район)" % str(n.get("name", "?")))
			else:
				parts.append("%s (сейчас: %s)" % [str(n.get("name", "?")), Game.location_name(str(post.get("loc", "")))])
	if parts.is_empty():
		return "расспроси людей в городе"
	return Game.sj("; ", parts)


func is_unlocked_budget_line() -> bool:
	return Game.is_unlocked("budget")


func _on_fulfill(uid: String) -> void:
	toast(Game.fulfill_promise(uid))
	base._drain_unlocks()
	base._after_action("")
	_draw_phone()


func _phone_paper() -> void:
	var p := Game.today_paper()
	if p.is_empty():
		phone_body.add_child(_plabel("Сегодня выпуска нет.", 18))
	else:
		phone_body.add_child(_plabel("День %d: %s" % [int(p.get("day", 1)), str(p.get("headline", ""))], 20))
		phone_body.add_child(_plabel(str(p.get("body", "")), 18))
	Game.mark_paper_read()


func open_paper(text: String) -> void:
	phone_tab = "paper"
	_draw_phone()
	phone_wrap.visible = true
	toast(text.split("\n")[0] if "\n" in text else text)


# ---------- ночь / выборы / меню ----------

func _build_night() -> void:
	var s := modal_shell(620.0)
	night_wrap = s["wrap"]
	var box: VBoxContainer = s["box"]
	night_title = _mk_label("", 24)
	box.add_child(night_title)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(540, 300)
	box.add_child(sc)
	night_text = RichTextLabel.new()
	night_text.bbcode_enabled = true
	night_text.fit_content = true
	night_text.scroll_active = false
	night_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	night_text.add_theme_font_size_override("normal_font_size", 18)
	sc.add_child(night_text)
	var go := _mk_button("☀ Проснуться в офисе")
	go.pressed.connect(func() -> void:
		night_wrap.visible = false
		base.wake_home())
	box.add_child(go)


func show_night(_summary: String) -> void:
	night_title.text = "ДЕНЬ %d ЗАКОНЧЕН" % mini(Game.day - 1, 7) if Game.day > 1 else "НОЧЬ"
	var lines := []
	var learned := Game.infos_of_day(mini(Game.day - 1, 7))
	if not learned.is_empty():
		lines.append("Ты узнал:")
		for iid in learned:
			lines.append("• %s" % str(Game.info_by_id(iid).get("text", iid)))
	var made := Game.promises_of_day(mini(Game.day - 1, 7))
	if not made.is_empty():
		lines.append("Ты обещал:")
		for p in made:
			lines.append("• %s" % str(p.get("title", "")))
	var tom := Game.events_of_day(Game.day)
	if not tom.is_empty() and Game.day <= 7:
		lines.append("Завтра:")
		for e in tom:
			lines.append("• %s" % str(e.get("title", "")))
	for m in Game.morning_notes:
		lines.append(m)
	Game.morning_notes = []
	if lines.is_empty():
		lines.append("Спокойная ночь.")
	night_text.text = "[color=white]%s[/color]" % _ebb(Game.sj("\n", lines))
	night_wrap.visible = true


func _build_elect() -> void:
	var s := modal_shell(620.0)
	elect_wrap = s["wrap"]
	var box: VBoxContainer = s["box"]
	box.add_child(_mk_label("🗳 Выборы", 24))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(540, 320)
	box.add_child(sc)
	elect_text = RichTextLabel.new()
	elect_text.bbcode_enabled = true
	elect_text.fit_content = true
	elect_text.scroll_active = false
	elect_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	elect_text.add_theme_font_size_override("normal_font_size", 18)
	sc.add_child(elect_text)
	var again := _mk_button("🔄 Начать заново")
	again.pressed.connect(func() -> void:
		elect_wrap.visible = false
		Game.reset_run()
		base.goto_map("city", Vector2(460, 930)))
	box.add_child(again)


func show_election() -> void:
	elect_text.text = "[color=white]%s[/color]" % _ebb(Game.election_text())
	elect_wrap.visible = true


func _build_menu() -> void:
	var s := modal_shell(420.0)
	menu_wrap = s["wrap"]
	var box: VBoxContainer = s["box"]
	box.add_child(_mk_label("Меню", 22))
	var items := [["💾 Сохранить", "save"], ["📂 Загрузить", "load"], ["🔄 Заново", "new"], ["🕹 Старый интерфейс", "old"], ["Закрыть", "close"]]
	for it in items:
		var b := _mk_button(it[0])
		b.pressed.connect(_on_menu.bind(it[1]))
		box.add_child(b)


func _on_menu(what: String) -> void:
	match what:
		"save":
			toast(Game.save_game())
		"load":
			toast(Game.load_game())
		"new":
			menu_wrap.visible = false
			Game.reset_run()
			base.goto_map("city", Vector2(460, 930))
		"old":
			get_tree().change_scene_to_file("res://scenes/Main.tscn")
		"close":
			menu_wrap.visible = false


func toggle_menu() -> void:
	menu_wrap.visible = not menu_wrap.visible
