extends Node
## GameState — автолоад Game. Вся игровая логика MVP, UI только показывает данные.
## Системы: время, экономика, карта/локации, NPC, диалоги, информация,
## повестка, обещания, агитация, события, выборы, сейвы.

signal state_changed
signal message_popup(title: String, text: String)
signal day_started(day: int)
signal game_ended(win: bool)

const DAY_START_MIN := 8 * 60
const DAY_END_MIN := 20 * 60
const MAX_DAY := 7
const START_MONEY := 3500
const SAVE_PATH := "user://deputy_save.json"

var D := {} # все данные из json

var day := 1
var minutes := DAY_START_MIN
var money := START_MONEY
var leaflets := 0
var current_location := "office"
var info_collected: Array = [] # id строк
var unlocked_promises: Array = ["p_meeting", "p_roads_light"]
var promises: Array = [] # словари-инстансы
var agenda := {} # topic -> int приоритет
var support := {} # группа -> int 0..100
var rel := {} # npc_id -> int
var flags := {} # напр. kol_support
var paper_read := {} # day -> bool
var game_over := false
var election := {}
var _uid := 0
# Обучение: с кем говорили, сколько напечатали/раздали, прогресс задач (legacy OldUI).
var talked_to: Array = []
var printed_total := 0
var distributed_total := 0
var tut := {"step": 0, "done": false, "skipped": false, "journal": false}
# Новый мир: постепенные открытия, слухи, посещения, подсказки.
var unlocked := {"talking": false, "promises": false, "notebook": false, "printing": false, "campaigning": false, "agenda_view": false, "budget": false, "politicians": false, "newspaper": false}
var info_state := {} # iid -> "rumor" | "confirmed"
var info_source := {} # iid -> npc_id
var info_day := {} # iid -> day
var visited: Array = []
var hints_seen: Array = []
var paper_seen := false
var morning_notes: Array = []
var time_bank := 0.0
var last_unlocks: Array = []
var just_slept := false
var last_night := ""
var spawn_override = null

## Безопасный join для обычных Array (String.join требует PackedStringArray).
func sj(sep: String, parts: Array) -> String:
	var ps := PackedStringArray()
	for x in parts:
		ps.append(str(x))
	return sep.join(ps)


var GROUP_NAMES := {
	"parents": "Родители", "teachers": "Учителя", "pupils": "Ученики",
	"drivers": "Водители", "residents": "Жители", "residents_outskirts": "Окраина",
	"families": "Семьи", "children": "Дети", "pensioners": "Пенсионеры",
	"doctors": "Врачи"
}

## Обучение: 8 задач по основным механикам. Порядок важен — проверка идёт по шагам.
const TUTORIAL := [
	{"id": "mila", "title": "Поговори с Милой в офисе", "hint": "Нажми «📍 Осмотреть: Офис» → выбери 🧑‍💼 Милу → задай вопрос. Разговор стоит ~10 мин. Так работают все диалоги в игре."},
	{"id": "anna", "title": "Съезди в школу и расспроси Анну", "hint": "На карте нажми 🏫 Школа (поездка 20 мин, 20€), внутри выбери 👩‍🏫 Анну. Люди дают информацию с прогнозом — что станет важным."},
	{"id": "journal", "title": "Открой Журнал", "hint": "Кнопка 📓 Журнал сверху. Там вся собранная информация, прогнозы, повестка дня и поддержка групп."},
	{"id": "promise", "title": "Дай первое обещание", "hint": "Экран 📝 Обещания или кнопка обещания в локации. Помни: обещание живёт до выборов — следи за дедлайном и ценой."},
	{"id": "print", "title": "Напечатай 100 листовок в офисе", "hint": "Вернись в офис: «🖨 Напечатать» (30 мин, 150€). Листовки напоминают горожанам о твоих обещаниях."},
	{"id": "give", "title": "Раздай листовки в районе", "hint": "Жилой район → «📨 Раздавать лично» (60 мин, эффективно) или «📦 Массовый разброс» (20 мин, слабый эффект). Время или охват — выбирай."},
	{"id": "fulfill", "title": "Выполни обещание", "hint": "Экран 📝 Обещания → «✅ Выполнить». Это тратит деньги и время. Начни с дешёвых (освещение 400€, лекарства 700€). Проекты со значком ⚠ требуют поддержки Кольцова из мэрии."},
	{"id": "sleep", "title": "Загляни в газету и ложись спать", "hint": "📰 Газета намекает на завтрашнюю повестку. Кнопка «😴 Спать» заканчивает день: утром — новости, события и напоминания. До выборов 7 дней!"},
]


func _ready() -> void:
	load_data()
	reset_run()


func load_data() -> void:
	for f in ["locations", "topics", "infos", "npcs", "dialogues", "promises", "travel", "events", "newspaper"]:
		var path := "res://data/%s.json" % f
		var txt := FileAccess.get_file_as_string(path)
		if txt == "":
			push_error("Нет файла: " + path)
			D[f] = {}
			continue
		var parsed = JSON.parse_string(txt)
		if parsed == null:
			push_error("Битый JSON: " + path)
			D[f] = {}
		else:
			D[f] = parsed


func reset_run() -> void:
	day = 1
	minutes = DAY_START_MIN
	money = START_MONEY
	leaflets = 0
	current_location = "office"
	info_collected = []
	unlocked_promises = [] # всё открывается только через разговоры (unlock_promises в диалогах)
	promises = []
	flags = {}
	paper_read = {}
	game_over = false
	election = {}
	_uid = 0
	agenda = {}
	for t in D.get("topics", {}).get("topics", []):
		agenda[t["id"]] = int(t.get("base", 15))
	support = {}
	for g in GROUP_NAMES.keys():
		support[g] = 30
	rel = {}
	for n in D.get("npcs", {}).get("npcs", []):
		rel[n["id"]] = 0
	talked_to = []
	printed_total = 0
	distributed_total = 0
	tut = {"step": 0, "done": false, "skipped": false, "journal": false}
	unlocked = {"talking": false, "promises": false, "notebook": false, "printing": false, "campaigning": false, "agenda_view": false, "budget": false, "politicians": false, "newspaper": false}
	info_state = {}
	info_source = {}
	info_day = {}
	visited = []
	hints_seen = []
	paper_seen = false
	morning_notes = []
	time_bank = 0.0
	last_unlocks = []
	just_slept = false
	last_night = ""
	emit_signal("state_changed")


# ---------- helpers ----------

func time_str() -> String:
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func day_name() -> String:
	var names := ["", "ПОНЕДЕЛЬНИК", "ВТОРНИК", "СРЕДА", "ЧЕТВЕРГ", "ПЯТНИЦА", "СУББОТА", "ВОСКРЕСЕНЬЕ"]
	return names[clampi(day, 1, 7)]


func minutes_left() -> int:
	return DAY_END_MIN - minutes


func topic_name(tid: String) -> String:
	for t in D.get("topics", {}).get("topics", []):
		if t["id"] == tid:
			return str(t["name"])
	return tid


func topic_icon(tid: String) -> String:
	for t in D.get("topics", {}).get("topics", []):
		if t["id"] == tid:
			return str(t.get("icon", "•"))
	return "•"


func agenda_stage(v: int) -> String:
	if v < 20:
		return "фон"
	elif v < 35:
		return "зарождается"
	elif v < 50:
		return "известна"
	elif v < 65:
		return "растёт"
	elif v < 80:
		return "публична"
	return "СРОЧНО"


func location_name(lid: String) -> String:
	for l in D.get("locations", {}).get("locations", []):
		if l["id"] == lid:
			return str(l["name"])
	return lid


func npc_by_id(nid: String) -> Dictionary:
	for n in D.get("npcs", {}).get("npcs", []):
		if n["id"] == nid:
			return n
	return {}


func info_by_id(iid: String) -> Dictionary:
	for i in D.get("infos", {}).get("infos", []):
		if i["id"] == iid:
			return i
	return {}


func template_by_id(tid: String) -> Dictionary:
	for t in D.get("promises", {}).get("templates", []):
		if t["id"] == tid:
			return t
	return {}


func dialogue_by_id(did: String) -> Dictionary:
	for d in D.get("dialogues", {}).get("dialogues", []):
		if d["id"] == did:
			return d
	return {}


func travel_cost(from_id: String, to_id: String) -> Array:
	if from_id == to_id:
		return [0, 0]
	var m: Dictionary = D.get("travel", {}).get("travel", {})
	if m.has(from_id) and m[from_id].has(to_id):
		return m[from_id][to_id]
	return [25, 25]


func active_promises() -> Array:
	var out := []
	for p in promises:
		if p["status"] in ["promised", "progress"]:
			out.append(p)
	return out


func npc_available(n: Dictionary) -> bool:
	var h := minutes / 60
	return h >= int(n.get("from", 8)) and h < int(n.get("to", 20))


func available_npcs_at(loc: String) -> Array:
	var out := []
	for n in D.get("npcs", {}).get("npcs", []):
		if str(n["location"]) == loc:
			out.append(n)
	return out


# ---------- обучение ----------

func tut_current() -> Dictionary:
	if bool(tut.get("done", false)) or bool(tut.get("skipped", false)):
		return {}
	var s := int(tut.get("step", 0))
	if s < 0 or s >= TUTORIAL.size():
		return {}
	return TUTORIAL[s]


func tut_step_done(sid: String) -> bool:
	match sid:
		"mila":
			return talked_to.has("assistant")
		"anna":
			return talked_to.has("teacher_anna")
		"journal":
			return bool(tut.get("journal", false))
		"promise":
			return promises.size() > 0
		"print":
			return printed_total >= 100
		"give":
			return distributed_total >= 100
		"fulfill":
			for p in promises:
				if str(p.get("status", "")) == "completed":
					return true
			return false
		"sleep":
			return day > 1
	return false


## Проверить и продвинуть задачи. Вызывать после действий (все денежные/временные
## действия проходят через advance_time, плюс note_ui и end_day напрямую).
func check_tutorial() -> void:
	if bool(tut.get("done", false)) or bool(tut.get("skipped", false)):
		return
	var s := int(tut.get("step", 0))
	var advanced := false
	while s < TUTORIAL.size() and tut_step_done(str(TUTORIAL[s]["id"])):
		s += 1
		advanced = true
	if advanced:
		tut["step"] = s
		if s >= TUTORIAL.size():
			tut["done"] = true
		emit_signal("state_changed")


func note_ui(which: String) -> void:
	if which == "journal" and not bool(tut.get("journal", false)):
		tut["journal"] = true
		check_tutorial()


func skip_tutorial() -> void:
	tut["skipped"] = true
	emit_signal("state_changed")


func unskip_tutorial() -> void:
	tut["skipped"] = false
	check_tutorial()
	emit_signal("state_changed")


# ---------- новый мир: открытия, слухи, цель ----------

func is_unlocked(mid: String) -> bool:
	return bool(unlocked.get(mid, false))


func unlock_mechanic(mid: String) -> bool:
	if bool(unlocked.get(mid, false)):
		return false
	unlocked[mid] = true
	last_unlocks.append(mid)
	emit_signal("state_changed")
	return true


func drain_unlocks() -> Array:
	var out: Array = []
	for mid in last_unlocks:
		out.append(mech_toast(str(mid)))
	last_unlocks = []
	return out


func npc_where(npc_id: String) -> Dictionary:
	# Где NPC сейчас: {"loc":..., "cx":..,"cy":..?} или {} (его нет).
	var n := npc_by_id(npc_id)
	var h := minutes / 60
	var posts: Array = n.get("posts", [])
	if posts.is_empty():
		if npc_available(n):
			return {"loc": str(n.get("location", "district"))}
		return {}
	for post in posts:
		if day < int(post.get("day_min", 1)):
			continue
		if h >= float(post.get("from", 8)) and h < float(post.get("to", 20)):
			return post
	return {}


func mech_toast(mid: String) -> String:
	match mid:
		"talking":
			return "💬 Новое: разговоры! Подойди к человеку и нажми E (или кнопку)."
		"promises":
			return "📝 Новое: обещания! Слова людям теперь записываются (📱 → Обещания)."
		"notebook":
			return "📓 Новое: блокнот! Слухи и факты собираются в 📱 → Блокнот."
		"printing":
			return "🖨 Новое: печать! В офисе заработал принтер."
		"campaigning":
			return "📨 Новое: агитация! Раздавай листовки людям и клади в ящики."
		"agenda_view":
			return "📊 Новое: обзор повестки! В блокноте видно, о чём гудит город."
		"budget":
			return "💰 Новое: бюджет! Большие траты — только через совет и депутатов."
		"politicians":
			return "🤝 Новое: переговоры! Депутатов встречают в мэрии."
		"newspaper":
			return "📰 Новое: газета! Утренний выпуск лежит в офисе на столе."
	return ""


func seen_hint(key: String) -> bool:
	# true, если подсказка показывается впервые (и помечает её).
	if key in hints_seen:
		return false
	hints_seen.append(key)
	return true


func enter_map(map_id: String) -> Array:
	var notes: Array = []
	current_location = map_id
	if not map_id in visited:
		visited.append(map_id)
	if map_id == "city_hall":
		if unlock_mechanic("politicians"):
			notes.append(mech_toast("politicians"))
	emit_signal("state_changed")
	return notes


## Дробное игровое время (ходьба). Возвращает текст перехода ночи или "".
func tick_time(amount: float) -> String:
	if game_over:
		return ""
	time_bank += amount
	var whole := int(time_bank)
	if whole < 1:
		return ""
	time_bank -= whole
	minutes += whole
	emit_signal("state_changed")
	if minutes >= DAY_END_MIN:
		return end_day()
	check_tutorial()
	return ""


# ----- слухи и подтверждения -----

func gain_info(iid: String, npc_id: String) -> Array:
	var out: Array = []
	var inf := info_by_id(iid)
	if inf.is_empty():
		return out
	var sid := str(iid)
	var topic := str(inf.get("topic", ""))
	if not sid in info_collected:
		info_collected.append(sid)
		info_source[sid] = npc_id
		info_day[sid] = day
		if float(inf.get("reliability", 0.8)) >= 1.0:
			info_state[sid] = "confirmed"
			out.append("📎 Точно известно: " + str(inf.get("text", sid)))
		else:
			info_state[sid] = "rumor"
			var n := npc_by_id(npc_id)
			out.append("👂 Слух от %s: %s (стоит проверить)" % [str(n.get("name", "?")), str(inf.get("text", sid))])
		out.append("🔮 " + str(inf.get("hint", "")))
		confirm_topic(topic, npc_id)
		if info_collected.size() >= 2:
			if unlock_mechanic("notebook"):
				out.append(mech_toast("notebook"))
	else:
		out.append("(уже записано)")
	return out


func confirm_topic(topic: String, by_npc: String) -> void:
	# Второй независимый источник по теме (или газета) подтверждает слухи.
	var sources := {}
	for iid in info_collected:
		var inf := info_by_id(str(iid))
		if str(inf.get("topic", "")) == topic:
			sources[str(info_source.get(str(iid), "?"))] = true
	if sources.size() >= 2 or by_npc == "paper":
		for iid in info_collected:
			var inf2 := info_by_id(str(iid))
			if str(inf2.get("topic", "")) == topic and str(info_state.get(str(iid), "rumor")) == "rumor":
				info_state[str(iid)] = "confirmed"


func confirm_infos(ids: Array) -> Array:
	var out: Array = []
	for x in ids:
		var sid := str(x)
		if sid in info_collected and str(info_state.get(sid, "rumor")) == "rumor":
			info_state[sid] = "confirmed"
			out.append("✅ Подтверждено: " + str(info_by_id(sid).get("text", "")))
	return out


## Диалог ПОКАЗАН (опции увидены, выбор ещё не сделан).
## Узнанные возможности пообещать сразу падают в телефон — уходить можно спокойно.
## Возвращает строки-заметки; тост открытия механики придёт через drain_unlocks().
func note_dialogue_shown(dlg: Dictionary) -> Array:
	var notes: Array = []
	var any_promise := false
	for opt in dlg.get("options", []):
		for pid in opt.get("unlock_promises", []):
			any_promise = true
			var ps := str(pid)
			if not ps in unlocked_promises:
				unlocked_promises.append(ps)
				notes.append("📝 Узнал: можно пообещать «%s»" % str(template_by_id(ps).get("title", ps)))
		if opt.has("creates_promise"):
			any_promise = true
			var cs := str(opt["creates_promise"])
			if not cs in unlocked_promises:
				unlocked_promises.append(cs)
				notes.append("📝 Узнал: можно пообещать «%s»" % str(template_by_id(cs).get("title", cs)))
	if any_promise:
		unlock_mechanic("promises")
	if not notes.is_empty():
		emit_signal("state_changed")
	return notes


func source_words(rel_val: float) -> String:
	if rel_val >= 0.95:
		return "очевидец"
	elif rel_val >= 0.8:
		return "надёжный человек"
	return "слышал от других"


func journal_notebook() -> String:
	var lines := ["📓 БЛОКНОТ"]
	for t in D.get("topics", {}).get("topics", []):
		var tid := str(t["id"])
		lines.append("%s %s" % [str(t.get("icon", "•")), str(t.get("name", tid))])
		var items := []
		for iid in info_collected:
			var inf := info_by_id(str(iid))
			if str(inf.get("topic", "")) == tid:
				items.append(str(iid))
		if items.is_empty():
			lines.append("? Нужно проверить")
		for iid in items:
			var inf := info_by_id(iid)
			var n := npc_by_id(str(info_source.get(iid, "?")))
			var band := source_words(float(inf.get("reliability", 0.8)))
			if str(info_state.get(iid, "rumor")) == "rumor":
				lines.append("? Слух: %s (%s, %s)" % [str(inf.get("text", "")), str(n.get("name", "?")), band])
			else:
				lines.append("❗ %s (%s)" % [str(inf.get("text", "")), str(n.get("name", "?"))])
			lines.append("  🔮 " + str(inf.get("hint", "")))
	if is_unlocked("agenda_view"):
		lines.append("📊 О чём гудит город:")
		for t in D.get("topics", {}).get("topics", []):
			var tid := str(t["id"])
			lines.append("• %s %s — %s" % [str(t.get("icon", "")), str(t.get("name", tid)), agenda_word(int(agenda.get(tid, 0)))])
	else:
		lines.append("(обзор повестки откроется позже)")
	var met := []
	for nid in talked_to:
		var n := npc_by_id(str(nid))
		if not n.is_empty():
			met.append("%s %s" % [str(n.get("emoji", "")), str(n.get("name", ""))])
	if not met.is_empty():
		lines.append("🤝 Знакомые: " + sj(", ", met))
	return sj("\n", lines)


func agenda_word(v: int) -> String:
	if v < 20:
		return "тихо"
	elif v < 35:
		return "поговаривают"
	elif v < 50:
		return "обсуждают"
	elif v < 65:
		return "гудит"
	elif v < 80:
		return "все только о нём!"
	return "КРИЗИС"


func decisive_day(topic: String) -> int:
	for t in D.get("topics", {}).get("topics", []):
		if str(t.get("id", "")) == topic:
			return int(t.get("decisive_day", 4))
	return 4


func topic_home(topic: String) -> String:
	for t in D.get("topics", {}).get("topics", []):
		if str(t.get("id", "")) == topic:
			return str(t.get("home", "city"))
	return "city"


func predicted_topics() -> Array:
	# Темы, где подтверждённая инфа добыта раньше решающего дня.
	var out: Array = []
	for t in D.get("topics", {}).get("topics", []):
		var tid := str(t["id"])
		var dd := int(t.get("decisive_day", 4))
		for iid in info_collected:
			var inf := info_by_id(str(iid))
			if str(inf.get("topic", "")) == tid and str(info_state.get(str(iid), "")) == "confirmed" and int(info_day.get(str(iid), 99)) < dd:
				if not tid in out:
					out.append(tid)
	return out


func reminder_for(npc_id: String) -> Dictionary:
	# Старое активное обещание по темам этого NPC (для живого напоминания).
	var n := npc_by_id(npc_id)
	var topics := []
	for iid in n.get("knowledge", []):
		var inf := info_by_id(str(iid))
		if not inf.is_empty():
			topics.append(str(inf.get("topic", "")))
	var best := {}
	for p in promises:
		if p["status"] in ["promised", "progress"] and int(p.get("created_day", day)) < day and str(p.get("topic", "")) in topics:
			if best.is_empty() or int(p.get("created_day", 0)) < int(best.get("created_day", 99)):
				best = p
	return best


func rel_gate(opt: Dictionary, npc_id: String) -> String:
	# Пуста, если опцию можно выбрать; иначе причина блокировки.
	if opt.has("needs_rel"):
		var need := int(opt["needs_rel"])
		var has := int(rel.get(npc_id, 0))
		if has < need:
			return "нужно больше доверия (поговори ещё)"
	return ""


func current_objective() -> Dictionary:
	if not "office" in visited:
		return {"title": "Найди свой офис", "hint": "Иди к зданию с вывеской ОФИС и зайди в дверь."}
	if talked_to.is_empty():
		return {"title": "Поговори с жителями", "hint": "Подойди к человеку и нажми E."}
	if info_collected.is_empty():
		return {"title": "Узнай, что происходит", "hint": "Расспрашивай людей о городе."}
	if promises.is_empty():
		return {"title": "Дай обещание", "hint": "В разговоре выбери «Да, постараюсь!»."}
	if leaflets <= 0:
		return {"title": "Напечатай листовки", "hint": "Принтер стоит в твоём офисе."}
	var spread := false
	for p in promises:
		if int(p.get("memory", 50)) > 50:
			spread = true
	if not spread:
		return {"title": "Раздай листовки", "hint": "Подходи к людям или клади в ящики. У своих тем — сильнее эффект."}
	var done := false
	for p in promises:
		if str(p.get("status", "")) == "completed":
			done = true
	if not done:
		return {"title": "Выполни обещание", "hint": "Нужны деньги и время. Начни с дешёвого."}
	if day <= 1:
		return {"title": "Дождись утра", "hint": "Поспи на диване в офисе."}
	return day_advice()


func day_advice() -> Dictionary:
	match day:
		2:
			return {"title": "Проверь слухи", "hint": "Больница и школа — спроси врачей и учителей."}
		3:
			return {"title": "Родители волнуются", "hint": "Загляни в школу и почитай стенд."}
		4:
			return {"title": "Город гудит", "hint": "Школа и транспорт на устах. Решай, за что браться."}
		5:
			return {"title": "День заседания", "hint": "Мэрия делит бюджет. Нужен голос Кольцова."}
		6:
			return {"title": "Битва за пустырь", "hint": "Парк или парковка — выбери сторону."}
		_:
			return {"title": "Выборы завтра", "hint": "Выполни начатое. Люди всё помнят."}


func pickup_paper() -> String:
	var p := today_paper()
	if p.is_empty():
		return "Газет нет."
	paper_seen = true
	unlock_mechanic("newspaper")
	confirm_topic(str(p.get("topic", "")), "paper")
	emit_signal("state_changed")
	return "📰 «%s»\n%s" % [str(p.get("headline", "")), str(p.get("body", ""))]


func paper_unread() -> bool:
	return not paper_seen or int(paper_read.get("last_day", 0)) != day


func infos_of_day(d: int) -> Array:
	var out: Array = []
	for iid in info_collected:
		if int(info_day.get(str(iid), 0)) == d:
			out.append(str(iid))
	return out


func promises_of_day(d: int) -> Array:
	var out: Array = []
	for p in promises:
		if int(p.get("created_day", 0)) == d:
			out.append(p)
	return out


func events_of_day(d: int) -> Array:
	var out: Array = []
	for e in D.get("events", {}).get("events", []):
		if int(e.get("day", 0)) == d:
			out.append(e)
	return out


func mark_paper_read() -> void:
	paper_read["last_day"] = day


# ---------- время ----------

## Продвинуть время. Возвращает текст предупреждения или "".
func advance_time(cost: int) -> String:
	if game_over:
		return ""
	minutes += cost
	emit_signal("state_changed")
	if minutes >= DAY_END_MIN:
		return end_day()
	check_tutorial()
	return ""


func end_day() -> String:
	# итоги вечера + переход
	var summary := evening_summary()
	if day >= MAX_DAY:
		run_election()
		just_slept = true
		last_night = summary
		return summary
	day += 1
	minutes = DAY_START_MIN
	apply_day_events(day)
	expire_promises()
	# растворение внимания
	for k in agenda.keys():
		agenda[k] = maxi(5, int(agenda[k]) - 3)
	# открытия по дням
	morning_notes = []
	if day >= 3 and unlock_mechanic("printing"):
		morning_notes.append(mech_toast("printing"))
	if day >= 4 and unlock_mechanic("agenda_view"):
		morning_notes.append(mech_toast("agenda_view"))
	if day >= 5 and unlock_mechanic("budget"):
		morning_notes.append(mech_toast("budget"))
	emit_signal("day_started", day)
	emit_signal("state_changed")
	check_tutorial()
	just_slept = true
	last_night = summary
	return summary


func evening_summary() -> String:
	var lines := ["🌙 Вечер дня %d." % day]
	lines.append("Повестка: " + agenda_line())
	var urgent := []
	for p in active_promises():
		var left: int = int(p["deadline"]) - day
		if left <= 1:
			urgent.append("«%s» (дедлайн: день %d)" % [p["title"], p["deadline"]])
	if not urgent.is_empty():
		lines.append("⚠ К дедлайну близко:\n• " + sj("\n• ", urgent))
	else:
		lines.append("Обещания под контролем.")
	return sj("\n", lines)


func agenda_line() -> String:
	var parts := []
	for tid in agenda.keys():
		parts.append("%s %s %d (%s)" % [topic_icon(tid), topic_name(tid), int(agenda[tid]), agenda_stage(int(agenda[tid]))])
	return sj(" | ", parts)


func apply_day_events(for_day: int) -> void:
	for e in D.get("events", {}).get("events", []):
		if int(e.get("day", 0)) == for_day:
			var t := str(e.get("topic", ""))
			if agenda.has(t):
				agenda[t] = mini(100, int(agenda[t]) + int(e.get("delta", 10)))
	# дороги после дня 5 дорожают
	if for_day >= 6:
		var t := template_by_id("p_roads")
		if not t.is_empty():
			pass # цена обрабатывается в fulfill (наценка)


func expire_promises() -> void:
	for p in promises:
		if p["status"] in ["promised", "progress"] and day > int(p["deadline"]):
			p["status"] = "broken"
			for g in p.get("audience", []):
				var gs := str(g)
				if support.has(gs):
					support[gs] = maxi(0, int(support[gs]) - 8)


# ---------- действия ----------

func travel_to(loc_id: String) -> String:
	if game_over:
		return "Игра окончена."
	if loc_id == current_location:
		return "Ты уже здесь."
	var c: Array = travel_cost(current_location, loc_id)
	var dur := int(c[0])
	var price := int(c[1])
	if money < price:
		return "Не хватает денег на поездку (%d€)." % price
	money -= price
	current_location = loc_id
	var warn := advance_time(dur)
	var msg := "%s %s. Поездка %d мин, %d€." % [loc_icon(loc_id), location_name(loc_id), dur, price]
	if warn != "":
		msg += "\n\n" + warn
	return msg


func loc_icon(lid: String) -> String:
	for l in D.get("locations", {}).get("locations", []):
		if l["id"] == lid:
			return str(l.get("icon", "📍"))
	return "📍"


func apply_dialogue(npc_id: String, dlg: Dictionary, opt: Dictionary) -> String:
	if game_over:
		return "Игра окончена."
	var cost := int(dlg.get("time_cost", 20))
	var out: Array = []
	var n := npc_by_id(npc_id)
	out.append("💬 %s (%s), −%d мин." % [n.get("name", "?"), n.get("profession", ""), cost])
	for iid in opt.get("give_info", []):
		out.append_array(gain_info(str(iid), npc_id))
	for cid in opt.get("confirms", []):
		out.append_array(confirm_infos([str(cid)]))
	for pid in opt.get("unlock_promises", []):
		var ps := str(pid)
		if not ps in unlocked_promises:
			unlocked_promises.append(ps)
			var t := template_by_id(ps)
			out.append("📝 Доступно обещание: «%s»" % str(t.get("title", ps)))
		if unlock_mechanic("promises"):
			out.append(mech_toast("promises"))
	if opt.has("creates_promise"):
		var cp := make_promise_silent(str(opt["creates_promise"]))
		if cp != "":
			out.append(cp)
		if unlock_mechanic("promises"):
			out.append(mech_toast("promises"))
	if opt.has("set_flag"):
		flags[str(opt["set_flag"])] = true
		out.append("🤝 Флаг: " + str(opt["set_flag"]))
	var dr := int(opt.get("rel", 0))
	if dr != 0 and rel.has(npc_id):
		rel[npc_id] = int(rel[npc_id]) + dr
	if not talked_to.has(npc_id):
		talked_to.append(npc_id)
	if unlock_mechanic("talking"):
		out.append(mech_toast("talking"))
	out.append("")
	out.append(str(opt.get("result", "")))
	var warn := advance_time(cost)
	if warn != "":
		out.append("\n" + warn)
	return sj("\n", out)


func make_promise(tid: String) -> String:
	if game_over:
		return "Игра окончена."
	var t := template_by_id(tid)
	if t.is_empty():
		return "Нет такого обещания."
	for p in promises:
		if p["template"] == tid and p["status"] in ["promised", "progress"]:
			return "Это обещание уже активно. Старые обещания не исчезают!"
	if active_promises().size() >= 8:
		return "Слишком много активных обещаний (8). Выполни старые!"
	_uid += 1
	promises.append({
		"uid": "pr%d" % _uid,
		"template": tid,
		"title": str(t["title"]),
		"topic": str(t["topic"]),
		"audience": t["audience"].duplicate(),
		"cost": int(t["cost"]),
		"ftime": int(t["time_cost"]),
		"deadline": day + 6 if int(t["deadline"]) > 7 else int(t["deadline"]),
		"needs_kol": bool(t.get("needs_kol", false)),
		"status": "promised",
		"created_day": day,
		"memory": 50,
		"visibility": 20,
	})
	var warn := advance_time(15)
	var msg := "📝 Обещание дано: «%s» (день %d, дедлайн день %d). Подумай: сможешь ли выполнить?" % [t["title"], day, promises.back()["deadline"]]
	if warn != "":
		msg += "\n\n" + warn
	return msg


## Обещание прямо из диалога: без лишней траты времени (разговор уже оплачен).
## Возвращает строку итога или "" при повторе.
func make_promise_silent(tid: String) -> String:
	if game_over:
		return ""
	var t := template_by_id(tid)
	if t.is_empty():
		return ""
	for p in promises:
		if p["template"] == tid and p["status"] in ["promised", "progress"]:
			return "(это обещание уже дано)"
	if active_promises().size() >= 8:
		return "(слишком много обещаний — сначала выполни старые)"
	_uid += 1
	promises.append({
		"uid": "pr%d" % _uid,
		"template": tid,
		"title": str(t["title"]),
		"topic": str(t["topic"]),
		"audience": t["audience"].duplicate(),
		"cost": int(t["cost"]),
		"ftime": int(t["time_cost"]),
		"deadline": day + 6 if int(t["deadline"]) > 7 else int(t["deadline"]),
		"needs_kol": bool(t.get("needs_kol", false)),
		"status": "promised",
		"created_day": day,
		"memory": 50,
		"visibility": 20,
	})
	emit_signal("state_changed")
	return "✅ Новое обещание: «%s»" % str(t["title"])


func fulfill_promise(uid: String) -> String:
	if game_over:
		return "Игра окончена."
	for p in promises:
		if p["uid"] != uid:
			continue
		if not p["status"] in ["promised", "progress"]:
			return "Обещание уже закрыто (%s)." % p["status"]
		if bool(p.get("needs_kol", false)) and not bool(flags.get("kol_support", false)):
			return "Нужна поддержка Кольцова! Договорись с ним в мэрии (день 1–5), иначе проект не пройдёт совет."
		var cost := int(p["cost"])
		if str(p["template"]) == "p_roads" and day >= 6:
			cost += 300 # смета сгорела
		if money < cost:
			return "Не хватает денег: нужно %d€, есть %d€." % [cost, money]
		if minutes_left() < int(p["ftime"]):
			return "Не хватает времени сегодня. Приходи завтра."
		money -= cost
		p["status"] = "completed"
		var boost := 8
		for g in p.get("audience", []):
			var gs := str(g)
			if support.has(gs):
				support[gs] = mini(100, int(support[gs]) + boost)
		var t := str(p["topic"])
		if agenda.has(t):
			agenda[t] = maxi(5, int(agenda[t]) - 12) # проблема решена — приоритет падает
		var warn := advance_time(int(p["ftime"]))
		var msg := "✅ Выполнено: «%s» (−%d€, −%d мин). Поддержка %s выросла!" % [p["title"], cost, p["ftime"], sj(", ", p["audience"])]
		if warn != "":
			msg += "\n\n" + warn
		return msg
	return "Обещание не найдено."


func print_leaflets() -> String:
	if game_over:
		return "Игра окончена."
	var tc: Array = D.get("travel", {}).get("costs", {}).get("print_100", [30, 150])
	var dur := int(tc[0])
	var price := int(tc[1])
	if money < price:
		return "Нужно %d€, а есть %d€." % [price, money]
	if minutes_left() < dur:
		return "Не хватает времени сегодня."
	money -= price
	leaflets += 100
	printed_total += 100
	if unlock_mechanic("campaigning"):
		pass # тост покажет мир через drain_unlocks
	var warn := advance_time(dur)
	var msg := "🖨 Напечатано 100 листовок (−%d€, −%d мин). Всего: %d." % [price, dur, leaflets]
	if warn != "":
		msg += "\n\n" + warn
	return msg


func distribute(mode: String) -> String:
	if game_over:
		return "Игра окончена."
	if leaflets < 50:
		return "Нужно хотя бы 50 листовок. Напечатай в офисе."
	var act := active_promises()
	if act.is_empty():
		return "Сначала дай хоть одно обещание — разносить нечего."
	if mode == "hand":
		if minutes_left() < 60:
			return "Нужно 60 мин, а осталось %d." % minutes_left()
		leaflets = maxi(0, leaflets - 100)
		distributed_total += 100
		var home_hit := false
		for p in act:
			var bonus := topic_home(str(p.get("topic", ""))) == current_location
			home_hit = home_hit or bonus
			p["memory"] = mini(100, int(p.get("memory", 50)) + (35 if bonus else 25))
			p["visibility"] = mini(100, int(p.get("visibility", 20)) + (45 if bonus else 30))
			for g in p.get("audience", []):
				var gs := str(g)
				if support.has(gs):
					support[gs] = mini(100, int(support[gs]) + (6 if bonus else 3))
		var warn := advance_time(60)
		var msg := "📨 Раздал лично (−100 шт, −60 мин). Высокая запоминаемость! Обещания помнят лучше."
		if home_hit:
			msg += " Своя территория — эффект сильнее!"
		if warn != "":
			msg += "\n\n" + warn
		return msg
	else:
		if minutes_left() < 20:
			return "Нужно 20 мин."
		leaflets = maxi(0, leaflets - 100)
		distributed_total += 100
		var home_hit2 := false
		for p in act:
			var bonus2 := topic_home(str(p.get("topic", ""))) == current_location
			home_hit2 = home_hit2 or bonus2
			p["memory"] = mini(100, int(p.get("memory", 50)) + (15 if bonus2 else 10))
			p["visibility"] = mini(100, int(p.get("visibility", 20)) + (20 if bonus2 else 12))
			for g in p.get("audience", []):
				var gs := str(g)
				if support.has(gs):
					support[gs] = mini(100, int(support[gs]) + (2 if bonus2 else 1))
		var warn := advance_time(20)
		var msg := "📦 Массовый разброс (−100 шт, −20 мин). Охват большой, но запоминают слабо."
		if home_hit2:
			msg += " Своя территория — эффект сильнее!"
		if warn != "":
			msg += "\n\n" + warn
		return msg


func study_notes() -> String:
	if game_over:
		return "Игра окончена."
	var warn := advance_time(10)
	var msg := "📓 Заметки изучены (−10 мин).\n" + journal_text()
	if warn != "":
		msg += "\n\n" + warn
	return msg


func journal_text() -> String:
	if info_collected.is_empty():
		return "Пока пусто. Поговори с жителями, специалистами, журналистом."
	var lines := []
	for iid in info_collected:
		var inf := info_by_id(str(iid))
		if inf.is_empty():
			continue
		lines.append("• [%s] %s (надёжность %d%%)\n  🔮 %s" % [topic_name(str(inf.get("topic", ""))), inf.get("text", ""), int(float(inf.get("reliability", 0.8)) * 100.0), inf.get("hint", "")])
	return sj("\n", lines)


func today_paper() -> Dictionary:
	for p in D.get("newspaper", {}).get("papers", []):
		if int(p.get("day", 0)) == day:
			return p
	return {}


func morning_brief() -> String:
	var p := today_paper()
	var lines := ["☀️ %s, день %d/7. Время %s, бюджет %d€." % [day_name(), day, time_str(), money]]
	if not p.is_empty():
		lines.append("📰 «%s»\n%s" % [p.get("headline", ""), p.get("body", "")])
	lines.append("📊 " + agenda_line())
	var rem := []
	for pr in active_promises():
		rem.append("«%s» до дня %d [%s]" % [pr["title"], pr["deadline"], pr["status"]])
	if rem.is_empty():
		lines.append("Активных обещаний нет.")
	else:
		lines.append("Активные обещания: " + sj("; ", rem))
	return sj("\n", lines)


func location_flavor(lid: String) -> String:
	for l in D.get("locations", {}).get("locations", []):
		if l["id"] == lid:
			var fb: Dictionary = l.get("flavor_by_day", {})
			if fb.has(str(day)):
				return str(fb[str(day)])
			return str(l.get("desc", ""))
	return ""


# ---------- выборы ----------

func template_importance(tid: String) -> int:
	var t := template_by_id(tid)
	return int(t.get("importance", 1))


func run_election() -> void:
	game_over = true
	var completed := 0
	var broken := 0
	for p in promises:
		if p["status"] == "completed":
			completed += 1
		elif p["status"] == "broken":
			broken += 1
		else:
			p["status"] = "broken" # невыполненное к выборам = нарушено
			broken += 1
	# решённые темы: есть выполненное обещание
	var resolved := []
	for t in D.get("topics", {}).get("topics", []):
		var tid := str(t["id"])
		for p in promises:
			if str(p.get("topic", "")) == tid and str(p.get("status", "")) == "completed":
				if not tid in resolved:
					resolved.append(tid)
	# скрытая оценка качества кампании (игроку не показывается)
	var points := 0.0
	for p in promises:
		var imp := template_importance(str(p.get("template", "")))
		if str(p.get("status", "")) == "completed":
			points += imp * (1.0 + int(p.get("memory", 50)) / 100.0)
		else:
			points -= imp * 1.5
			if int(p.get("visibility", 20)) >= 50:
				points -= imp * int(p.get("visibility", 20)) / 100.0 # позор разрекламированного провала
	var pred := predicted_topics()
	points += pred.size() * 1.5
	var avg_sup := 0
	if not support.is_empty():
		var s := 0
		for v in support.values():
			s += int(v)
		avg_sup = s / support.size()
	points += avg_sup / 20.0
	if bool(flags.get("kol_support", false)):
		points += 1.0
	var win := points >= 11.0 and broken <= 2
	election = {
		"completed": completed, "broken": broken,
		"avg_support": avg_sup, "win": win,
		"resolved": resolved, "predicted": pred,
		"support": support.duplicate(), "promises": promises.duplicate(),
	}
	emit_signal("game_ended", win)
	emit_signal("state_changed")


func election_text() -> String:
	var e := election
	if e.is_empty():
		return "Выборы ещё не прошли."
	var lines := ["🗳 ВЫБОРЫ. Неделя закончена."]
	lines.append("Ты обещал: %d | Выполнил: %d | Провалил: %d" % [promises.size(), int(e.get("completed", 0)), int(e.get("broken", 0))])
	lines.append("")
	var res: Array = e.get("resolved", [])
	if res.is_empty():
		lines.append("Решённых проблем нет.")
	else:
		lines.append("Проблемы, которые решил:")
		for tid in res:
			lines.append("✓ %s %s" % [topic_icon(str(tid)), topic_name(str(tid))])
	var missed := []
	for t in D.get("topics", {}).get("topics", []):
		var tid := str(t["id"])
		if not tid in res and (int(agenda.get(tid, 0)) >= 50 or has_broken_topic(tid)):
			missed.append(tid)
	if not missed.is_empty():
		lines.append("Проблемы, которые упустил:")
		for tid in missed:
			lines.append("✗ %s %s" % [topic_icon(str(tid)), topic_name(str(tid))])
	var pred: Array = e.get("predicted", [])
	if not pred.is_empty():
		var pn := []
		for tid in pred:
			pn.append(topic_name(str(tid)))
		lines.append("Ты заранее разгадал: " + sj(", ", pn) + ". Город это ценит.")
	lines.append("")
	lines.append("Жители помнят твои обещания.")
	lines.append("")
	if bool(e.get("win", false)):
		lines.append("🎉 ПОБЕДА! Ты переизбран. Тебя помнят по делам, а не по словам.")
	else:
		lines.append("💔 ПОРАЖЕНИЕ. Городу нужны были дела.")
		if int(e.get("completed", 0)) < 3:
			lines.append("Совет: два дешёвых обещания — не кампания. Решай значимые проблемы и доводи до конца.")
		if int(e.get("broken", 0)) > 2:
			lines.append("Совет: не давай обещаний, которые не потянешь. Люди помнят каждый провал.")
		if pred.is_empty():
			lines.append("Совет: слушай людей раньше — кто предсказал повестку, тот успел первым.")
	return sj("\n", lines)


func has_broken_topic(tid: String) -> bool:
	for p in promises:
		if str(p.get("topic", "")) == tid and str(p.get("status", "")) == "broken":
			return true
	return false


# ---------- сейвы ----------

func save_game() -> String:
	var data := {
		"day": day, "minutes": minutes, "money": money, "leaflets": leaflets,
		"current_location": current_location, "info": info_collected,
		"unlocked": unlocked_promises, "promises": promises, "agenda": agenda,
		"support": support, "rel": rel, "flags": flags, "paper_read": paper_read,
		"uid": _uid, "game_over": game_over, "election": election,
		"talked": talked_to, "printed": printed_total, "gave": distributed_total,
		"tut": tut, "mechs": unlocked,
		"info_state": info_state, "info_source": info_source, "info_day": info_day,
		"visited": visited, "hints": hints_seen, "paper_seen": paper_seen,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return "Не смог сохранить."
	f.store_string(JSON.stringify(data))
	f.close()
	return "💾 Сохранено (день %d, %s)." % [day, time_str()]


func load_game() -> String:
	if not FileAccess.file_exists(SAVE_PATH):
		return "Сохранения нет."
	var txt := FileAccess.get_file_as_string(SAVE_PATH)
	var data = JSON.parse_string(txt)
	if data == null:
		return "Сохранение битое."
	day = int(data.get("day", 1))
	minutes = int(data.get("minutes", DAY_START_MIN))
	money = int(data.get("money", START_MONEY))
	leaflets = int(data.get("leaflets", 0))
	current_location = str(data.get("current_location", "office"))
	info_collected = data.get("info", [])
	unlocked_promises = data.get("unlocked", [])
	promises = data.get("promises", [])
	agenda = data.get("agenda", {})
	support = data.get("support", {})
	rel = data.get("rel", {})
	flags = data.get("flags", {})
	paper_read = data.get("paper_read", {})
	_uid = int(data.get("uid", 0))
	game_over = bool(data.get("game_over", false))
	election = data.get("election", {})
	talked_to = data.get("talked", [])
	printed_total = int(data.get("printed", 0))
	distributed_total = int(data.get("gave", 0))
	var lt = data.get("tut", {"step": 0, "done": false, "skipped": false, "journal": false})
	tut = {"step": int(lt.get("step", 0)), "done": bool(lt.get("done", false)), "skipped": bool(lt.get("skipped", false)), "journal": bool(lt.get("journal", false))}
	var lu = {"talking": false, "promises": false, "notebook": false, "printing": false, "campaigning": false, "agenda_view": false, "budget": false, "politicians": false, "newspaper": false}
	var su = data.get("mechs", {})
	for k in lu.keys():
		lu[k] = bool(su.get(k, false))
	unlocked = lu
	info_state = data.get("info_state", {})
	info_source = data.get("info_source", {})
	info_day = data.get("info_day", {})
	visited = data.get("visited", [])
	hints_seen = data.get("hints", [])
	paper_seen = bool(data.get("paper_seen", false))
	emit_signal("state_changed")
	if game_over:
		emit_signal("game_ended", bool(election.get("win", false)))
	return "📂 Загружено (день %d, %s)." % [day, time_str()]


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)
