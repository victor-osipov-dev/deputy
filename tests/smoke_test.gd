extends SceneTree
## Смоук-тест игровой логики (ядро + новый мир). Запуск:
## Godot --headless --path <проект> --script res://tests/smoke_test.gd

func _init() -> void:
	var gs = load("res://scripts/game_state.gd").new()
	gs.load_data()
	gs.reset_run()
	var results: Array = []
	var check := func(name: String, cond: bool) -> void:
		results.append(("PASS " if cond else "FAIL ") + name)

	# --- база (ядро) ---
	check.call("старт день=1", gs.day == 1)
	check.call("старт деньги=3500", gs.money == 3500)
	check.call("повестка 5 тем", gs.agenda.size() == 5)
	check.call("механики закрыты", not gs.is_unlocked("notebook") and not gs.is_unlocked("printing"))
	check.call("цель 1: найти офис", str(gs.current_objective().get("title", "")) == "Найди свой офис")
	gs.enter_map("office")
	check.call("офис посещён", "office" in gs.visited)
	check.call("цель 2: поговорить", str(gs.current_objective().get("title", "")) == "Поговори с жителями")

	# --- диалог с Милой ---
	var dass: Dictionary = gs.dialogue_by_id("dlg_assistant")
	gs.apply_dialogue("assistant", dass, dass["options"][0])
	check.call("разговор открыл talking", gs.is_unlocked("talking"))
	check.call("инфа от Милы подтверждена (1.0)", str(gs.info_state.get("assistant_brief", "")) == "confirmed")

	# --- слухи: баба Валя -> врач ---
	var dpat: Dictionary = gs.dialogue_by_id("dlg_patient")
	gs.apply_dialogue("patient_granny", dpat, dpat["options"][0])
	check.call("слух записан", str(gs.info_state.get("hospital_queues", "")) == "rumor")
	check.call("блокнот открыт (2 инфо)", gs.is_unlocked("notebook"))
	var ddoc: Dictionary = gs.dialogue_by_id("dlg_doctor")
	gs.apply_dialogue("doctor_elena", ddoc, ddoc["options"][0])
	check.call("второй источник подтвердил", str(gs.info_state.get("hospital_queues", "")) == "confirmed")
	check.call("журнал-блокнот группирует", gs.journal_notebook().contains("БЛОКНОТ"))

	# --- rel-гейт: журналист закрыт, потом открыт ---
	var dj: Dictionary = gs.dialogue_by_id("dlg_journalist")
	check.call("гейт Иры держит", gs.rel_gate(dj["options"][0], "journalist") != "")
	gs.apply_dialogue("journalist", dj, dj["options"][1])
	gs.apply_dialogue("journalist", dj, dj["options"][1])
	check.call("гейт Иры открыт при rel>=2", gs.rel_gate(dj["options"][0], "journalist") == "")

	# --- увидел опции, но ушёл: телефон уже знает ---
	var peek: Dictionary = gs.dialogue_by_id("dlg_anna")
	var notes: Array = gs.note_dialogue_shown(peek)
	check.call("увиденное открыто без выбора", gs.unlocked_promises.has("p_school_teachers"))
	check.call("без выбора обещаний нет", gs.active_promises().is_empty())
	check.call("заметка об узнанном", notes.size() > 0)
	# --- Анна: обещание прямо из диалога ---
	var dlg: Dictionary = gs.dialogue_by_id("dlg_anna")
	var opt: Dictionary = {}
	for o in dlg.get("options", []):
		if str(o.get("creates_promise", "")) == "p_school_teachers":
			opt = o
	check.call("опция-создатель найдена", not opt.is_empty())
	gs.apply_dialogue("teacher_anna", dlg, opt)
	check.call("обещание создано диалогом", gs.active_promises().size() == 1)
	check.call("механика обещаний открыта", gs.is_unlocked("promises"))
	var dup: String = gs.make_promise("p_school_teachers")
	check.call("дубликат запрещён", dup.contains("уже активно"))
	var ff: String = gs.fulfill_promise(gs.active_promises()[0]["uid"])
	check.call("без Кольцова отказ", ff.contains("Кольцова"))

	# --- напоминание NPC ---
	gs.day = 3
	var rem: Dictionary = gs.reminder_for("teacher_anna")
	check.call("Анна напоминает про учителей", str(rem.get("template", "")) == "p_school_teachers")
	gs.day = 1

	# --- посты NPC ---
	gs.minutes = 10 * 60
	gs.day = 1
	check.call("Анна в школе утром", str(gs.npc_where("teacher_anna").get("loc", "")) == "school")
	gs.minutes = int(16.5 * 60)
	check.call("Анны нет в 16:30 (перерыв)", gs.npc_where("teacher_anna").is_empty())
	gs.minutes = 18 * 60
	check.call("Анна вечером в районе", str(gs.npc_where("teacher_anna").get("loc", "")) == "district")
	gs.day = 4
	gs.minutes = 14 * 60
	check.call("Ира у школы днём 4+", str(gs.npc_where("journalist").get("loc", "")) == "city")
	gs.day = 1
	gs.minutes = 8 * 60

	# --- газета подтверждает слухи ---
	gs.day = 2
	check.call("газета дня 2", str(gs.today_paper().get("topic", "")) == "hospital")
	var pt: String = gs.pickup_paper()
	check.call("подбор газеты", pt.contains("Очереди") or pt.length() > 20)
	gs.day = 1

	# --- листовки с районным бонусом ---
	gs.current_location = "office"
	gs.minutes = 8 * 60
	gs.money = 3500
	gs.print_leaflets()
	check.call("печать открыла агитацию", gs.is_unlocked("campaigning"))
	gs.make_promise("p_roads_light")
	gs.current_location = "city" # дом дорог — улицы города
	gs.distribute("hand")
	var mem := 50
	for p in gs.promises:
		if p["template"] == "p_roads_light":
			mem = int(p.get("memory", 50))
	check.call("домашний бонус памяти", mem >= 85)
	var uid_light := ""
	for p in gs.active_promises():
		if p["template"] == "p_roads_light":
			uid_light = p["uid"]
	var money_before: int = gs.money
	check.call("выполнение освещения", gs.fulfill_promise(uid_light).begins_with("✅"))
	check.call("деньги списаны 400", gs.money == money_before - 400)

	# --- предсказание ---
	gs.day = 1
	check.call("школа предсказана (подтверждено до дня 4)", "school" in gs.predicted_topics())

	# --- сейв/лоад нового состояния ---
	check.call("сейв ок", gs.save_game().contains("Сохранено"))
	gs.info_state = {}
	gs.load_game()
	check.call("лоад вернул слухи", str(gs.info_state.get("hospital_queues", "")) == "confirmed")
	check.call("лоад вернул открытия", gs.is_unlocked("campaigning"))

	# --- выборы: дешёвый спидран проигрывает ---
	var gw = load("res://scripts/game_state.gd").new()
	gw.load_data()
	gw.reset_run()
	gw.make_promise_silent("p_roads_light")
	gw.make_promise_silent("p_meeting")
	for p in gw.promises:
		p["status"] = "completed"
	gw.money = 9999
	gw.day = 7
	gw.minutes = 19 * 60
	gw.end_day()
	check.call("выборы кончились", gw.game_over)
	check.call("2 дешёвых НЕ дают победу", not bool(gw.election.get("win", true)))
	check.call("текст без формулы", not gw.election_text().contains("45+"))

	# --- выборы: значимая кампания выигрывает ---
	var gv = load("res://scripts/game_state.gd").new()
	gv.load_data()
	gv.reset_run()
	gv.flags["kol_support"] = true
	gv.make_promise_silent("p_school_teachers")
	gv.make_promise_silent("p_transport_buses")
	gv.make_promise_silent("p_school_repair")
	for p in gv.promises:
		p["status"] = "completed"
		p["memory"] = 80
	gv.day = 7
	gv.minutes = 19 * 60
	gv.end_day()
	check.call("сильная кампания побеждает", bool(gv.election.get("win", false)))
	check.call("темы решены", "school" in gv.election.get("resolved", []))

	for line in results:
		print(line)
	var bad := 0
	for line in results:
		if str(line).begins_with("FAIL"):
			bad += 1
	print("ИТОГ: %d/%d passed" % [results.size() - bad, results.size()])
	quit(1 if bad > 0 else 0)
