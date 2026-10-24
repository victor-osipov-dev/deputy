// GameState — порт scripts/game_state.gd (Godot). Вся игровая логика; UI только показывает данные.
// Системы: время, экономика, карта/локации, NPC, диалоги, информация,
// повестка, обещания, агитация, события, выборы, сейвы (localStorage).

const DAY_START_MIN = 8 * 60;
const DAY_END_MIN = 20 * 60;
const MAX_DAY = 7;
const START_MONEY = 3500;
const SAVE_KEY = "deputy_save_v1";

// localStorage может отсутствовать (Node/тесты) — мягкий фолбэк в память.
const ls = (() => {
  try {
    if (typeof localStorage === "undefined") throw new Error("no ls");
    return { get: (k) => localStorage.getItem(k), set: (k, v) => localStorage.setItem(k, v), del: (k) => localStorage.removeItem(k) };
  } catch {
    const mem = new Map();
    return { get: (k) => (mem.has(k) ? mem.get(k) : null), set: (k, v) => mem.set(k, v), del: (k) => mem.delete(k) };
  }
})();

export class GameState {
  constructor(D) {
    this.D = D; // все данные из json
    // Сигналы (аналог Godot-сигналов): список колбеков.
    this.onState = [];      // state_changed
    this.onDayStarted = []; // day_started(day)
    this.onGameEnded = [];  // game_ended(win)

    // обучение
    this.TUTORIAL = [
      { id: "mila", title: "Поговори с Милой в офисе", hint: "Нажми «📍 Осмотреть: Офис» → выбери 🧑‍💼 Милу → задай вопрос. Разговор стоит ~10 мин. Так работают все диалоги в игре." },
      { id: "anna", title: "Съезди в школу и расспроси Анну", hint: "На карте нажми 🏫 Школа (поездка 20 мин, 20€), внутри выбери 👩‍🏫 Анну. Люди дают информацию с прогнозом — что станет важным." },
      { id: "journal", title: "Открой Журнал", hint: "Кнопка 📓 Журнал сверху. Там вся собранная информация, прогнозы, повестка дня и поддержка групп." },
      { id: "promise", title: "Дай первое обещание", hint: "Экран 📝 Обещания или кнопка обещания в локации. Помни: обещание живёт до выборов — следи за дедлайном и ценой." },
      { id: "print", title: "Напечатай 100 листовок в офисе", hint: "Вернись в офис: «🖨 Напечатать» (30 мин, 150€). Листовки напоминают горожанам о твоих обещаниях." },
      { id: "give", title: "Раздай листовки в район", hint: "Жилой район → «📨 Раздавать лично» (60 мин, эффективно) или «📦 Массовый разброс» (20 мин, слабый эффект). Время или охват — выбирай." },
      { id: "fulfill", title: "Выполни обещание", hint: "Экран 📝 Обещания → «✅ Выполнить». Это тратит деньги и время. Начни с дешёвых (освещение 400€, лекарства 700€). Проекты со значком ⚠ требуют поддержки Кольцова из мэрии." },
      { id: "sleep", title: "Загляни в газету и ложись спать", hint: "📰 Газета намекает на завтрашнюю повестку. Кнопка «😴 Спать» заканчивает день: утром — новости, события и напоминания. До выборов 7 дней!" },
    ];

    this.GROUP_NAMES = new Map([
      ["parents", "Родители"], ["teachers", "Учителя"], ["pupils", "Ученики"],
      ["drivers", "Водители"], ["residents", "Жители"], ["residents_outskirts", "Окраина"],
      ["families", "Семьи"], ["children", "Дети"], ["pensioners", "Пенсионеры"],
      ["doctors", "Врачи"],
    ]);

    this.sj = (sep, parts) => parts.map((x) => String(x)).join(sep);
    this.stateChanged = () => { for (const f of this.onState) f(); };

    this.resetRun();
  }

  // ---------- helpers ----------

  timeStr() {
    return `${String(Math.floor(this.minutes / 60)).padStart(2, "0")}:${String(this.minutes % 60).padStart(2, "0")}`;
  }

  dayName() {
    const names = ["", "ПОНЕДЕЛЬНИК", "ВТОРНИК", "СРЕДА", "ЧЕТВЕРГ", "ПЯТНИЦА", "СУББОТА", "ВОСКРЕСЕНЬЕ"];
    return names[Math.min(Math.max(this.day, 1), 7)];
  }

  minutesLeft() { return DAY_END_MIN - this.minutes; }

  topicName(tid) {
    for (const t of this.D.topics?.topics ?? []) if (t.id === tid) return String(t.name);
    return tid;
  }

  topicIcon(tid) {
    for (const t of this.D.topics?.topics ?? []) if (t.id === tid) return String(t.icon ?? "•");
    return "•";
  }

  agendaStage(v) {
    if (v < 20) return "фон";
    if (v < 35) return "зарождается";
    if (v < 50) return "известна";
    if (v < 65) return "растёт";
    if (v < 80) return "публична";
    return "СРОЧНО";
  }

  locationName(lid) {
    for (const l of this.D.locations?.locations ?? []) if (l.id === lid) return String(l.name);
    return lid;
  }

  npcById(nid) {
    for (const n of this.D.npcs?.npcs ?? []) if (n.id === nid) return n;
    return {};
  }

  infoById(iid) {
    for (const i of this.D.infos?.infos ?? []) if (i.id === iid) return i;
    return {};
  }

  templateById(tid) {
    for (const t of this.D.promises?.templates ?? []) if (t.id === tid) return t;
    return {};
  }

  dialogueById(did) {
    for (const d of this.D.dialogues?.dialogues ?? []) if (d.id === did) return d;
    return {};
  }

  travelCost(fromId, toId) {
    if (fromId === toId) return [0, 0];
    const m = this.D.travel?.travel ?? {};
    if (m[fromId] && m[fromId][toId]) return m[fromId][toId];
    return [25, 25];
  }

  activePromises() {
    return this.promises.filter((p) => p.status === "promised" || p.status === "progress");
  }

  npcAvailable(n) {
    const h = Math.floor(this.minutes / 60);
    return h >= (n.from ?? 8) && h < (n.to ?? 20);
  }

  availableNpcsAt(loc) {
    return (this.D.npcs?.npcs ?? []).filter((n) => String(n.location) === loc);
  }

  // ---------- обучение ----------

  tutCurrent() {
    if (this.tut.done || this.tut.skipped) return {};
    const s = this.tut.step;
    if (s < 0 || s >= this.TUTORIAL.length) return {};
    return this.TUTORIAL[s];
  }

  tutStepDone(sid) {
    switch (sid) {
      case "mila": return this.talkedTo.includes("assistant");
      case "anna": return this.talkedTo.includes("teacher_anna");
      case "journal": return !!this.tut.journal;
      case "promise": return this.promises.length > 0;
      case "print": return this.printedTotal >= 100;
      case "give": return this.distributedTotal >= 100;
      case "fulfill": return this.promises.some((p) => p.status === "completed");
      case "sleep": return this.day > 1;
    }
    return false;
  }

  checkTutorial() {
    if (this.tut.done || this.tut.skipped) return;
    let s = this.tut.step;
    let advanced = false;
    while (s < this.TUTORIAL.length && this.tutStepDone(String(this.TUTORIAL[s].id))) {
      s += 1;
      advanced = true;
    }
    if (advanced) {
      this.tut.step = s;
      if (s >= this.TUTORIAL.length) this.tut.done = true;
      this.stateChanged();
    }
  }

  noteUi(which) {
    if (which === "journal" && !this.tut.journal) {
      this.tut.journal = true;
      this.checkTutorial();
    }
  }

  skipTutorial() {
    this.tut.skipped = true;
    this.stateChanged();
  }

  unskipTutorial() {
    this.tut.skipped = false;
    this.checkTutorial();
    this.stateChanged();
  }

  // ---------- новый мир: открытия, слухи, цель ----------

  isUnlocked(mid) { return !!this.unlocked[mid]; }

  unlockMechanic(mid) {
    if (this.unlocked[mid]) return false;
    this.unlocked[mid] = true;
    this.lastUnlocks.push(mid);
    this.stateChanged();
    return true;
  }

  drainUnlocks() {
    const out = [];
    for (const mid of this.lastUnlocks) out.push(this.mechToast(String(mid)));
    this.lastUnlocks = [];
    return out;
  }

  npcWhere(npcId) {
    // Где NPC сейчас: {loc, cx?, cy??} или {} (его нет).
    const n = this.npcById(npcId);
    const h = Math.floor(this.minutes / 60);
    const posts = n.posts ?? [];
    if (posts.length === 0) {
      if (this.npcAvailable(n)) return { loc: String(n.location ?? "district") };
      return {};
    }
    for (const post of posts) {
      if (this.day < (post.day_min ?? 1)) continue;
      if (h >= (post.from ?? 8) && h < (post.to ?? 20)) return post;
    }
    return {};
  }

  mechToast(mid) {
    switch (mid) {
      case "talking": return "💬 Новое: разговоры! Подойди к человеку и нажми E (или кнопку).";
      case "promises": return "📝 Новое: обещания! Слова людям теперь записываются (📱 → Обещания).";
      case "notebook": return "📓 Новое: блокнот! Слухи и факты собираются в 📱 → Блокнот.";
      case "printing": return "🖨 Новое: печать! В офисе заработал принтер.";
      case "campaigning": return "📨 Новое: агитация! Раздавай листовки людям и клади в ящики.";
      case "agenda_view": return "📊 Новое: обзор повестки! В блокноте видно, о чём гудит город.";
      case "budget": return "💰 Новое: бюджет! Большие траты — только через совет и депутатов.";
      case "politicians": return "🤝 Новое: переговоры! Депутатов встречают в мэрии.";
      case "newspaper": return "📰 Новое: газета! Утренний выпуск лежит в офисе на столе.";
    }
    return "";
  }

  seenHint(key) {
    if (this.hintsSeen.includes(key)) return false;
    this.hintsSeen.push(key);
    return true;
  }

  enterMap(mapId) {
    const notes = [];
    this.currentLocation = mapId;
    if (!this.visited.includes(mapId)) this.visited.push(mapId);
    if (mapId === "city_hall") {
      if (this.unlockMechanic("politicians")) notes.push(this.mechToast("politicians"));
    }
    this.stateChanged();
    return notes;
  }

  // Дробное игровое время (ходьба). Возвращает текст перехода ночи или "".
  tickTime(amount) {
    if (this.gameOver) return "";
    this.timeBank += amount;
    const whole = Math.floor(this.timeBank);
    if (whole < 1) return "";
    this.timeBank -= whole;
    this.minutes += whole;
    this.stateChanged();
    if (this.minutes >= DAY_END_MIN) return this.endDay();
    this.checkTutorial();
    return "";
  }

  // ----- слухи и подтверждения -----

  gainInfo(iid, npcId) {
    const out = [];
    const inf = this.infoById(iid);
    if (!inf.id && !inf.text) return out;
    const sid = String(iid);
    const topic = String(inf.topic ?? "");
    if (!this.infoCollected.includes(sid)) {
      this.infoCollected.push(sid);
      this.infoSource[sid] = npcId;
      this.infoDay[sid] = this.day;
      if (Number(inf.reliability ?? 0.8) >= 1.0) {
        this.infoState[sid] = "confirmed";
        out.push("📎 Точно известно: " + String(inf.text ?? sid));
      } else {
        this.infoState[sid] = "rumor";
        const n = this.npcById(npcId);
        out.push(`👂 Слух от ${n.name ?? "?"}: ${inf.text ?? sid} (стоит проверить)`);
      }
      out.push("🔮 " + String(inf.hint ?? ""));
      this.confirmTopic(topic, npcId);
      if (this.infoCollected.length >= 2) {
        if (this.unlockMechanic("notebook")) out.push(this.mechToast("notebook"));
      }
    } else {
      out.push("(уже записано)");
    }
    return out;
  }

  confirmTopic(topic, byNpc) {
    // Второй независимый источник по теме (или газета) подтверждает слухи.
    const sources = {};
    for (const iid of this.infoCollected) {
      const inf = this.infoById(String(iid));
      if (String(inf.topic ?? "") === topic) sources[String(this.infoSource[iid] ?? "?")] = true;
    }
    if (Object.keys(sources).length >= 2 || byNpc === "paper") {
      for (const iid of this.infoCollected) {
        const inf2 = this.infoById(String(iid));
        if (String(inf2.topic ?? "") === topic && String(this.infoState[iid] ?? "rumor") === "rumor") {
          this.infoState[iid] = "confirmed";
        }
      }
    }
  }

  confirmInfos(ids) {
    const out = [];
    for (const x of ids) {
      const sid = String(x);
      if (this.infoCollected.includes(sid) && String(this.infoState[sid] ?? "rumor") === "rumor") {
        this.infoState[sid] = "confirmed";
        out.push("✅ Подтверждено: " + String(this.infoById(sid).text ?? ""));
      }
    }
    return out;
  }

  // Диалог ПОКАЗАН (опции увидены, выбор ещё не сделан).
  // Узнанные возможности пообещать сразу падают в телефон — уходить можно спокойно.
  noteDialogueShown(dlg) {
    const notes = [];
    let anyPromise = false;
    for (const opt of dlg.options ?? []) {
      for (const pid of opt.unlock_promises ?? []) {
        anyPromise = true;
        const ps = String(pid);
        if (!this.unlockedPromises.includes(ps)) {
          this.unlockedPromises.push(ps);
          notes.push(`📝 Узнал: можно пообещать «${this.templateById(ps).title ?? ps}»`);
        }
      }
      if (opt.creates_promise) {
        anyPromise = true;
        const cs = String(opt.creates_promise);
        if (!this.unlockedPromises.includes(cs)) {
          this.unlockedPromises.push(cs);
          notes.push(`📝 Узнал: можно пообещать «${this.templateById(cs).title ?? cs}»`);
        }
      }
    }
    if (anyPromise) this.unlockMechanic("promises");
    if (notes.length > 0) this.stateChanged();
    return notes;
  }

  sourceWords(relVal) {
    if (relVal >= 0.95) return "очевидец";
    if (relVal >= 0.8) return "надёжный человек";
    return "слышал от других";
  }

  journalNotebook() {
    const lines = ["📓 БЛОКНОТ"];
    for (const t of this.D.topics?.topics ?? []) {
      const tid = String(t.id);
      lines.push(`${t.icon ?? "•"} ${t.name ?? tid}`);
      const items = [];
      for (const iid of this.infoCollected) {
        const inf = this.infoById(String(iid));
        if (String(inf.topic ?? "") === tid) items.push(String(iid));
      }
      if (items.length === 0) lines.push("? Нужно проверить");
      for (const iid of items) {
        const inf = this.infoById(iid);
        const n = this.npcById(String(this.infoSource[iid] ?? "?"));
        const band = this.sourceWords(Number(inf.reliability ?? 0.8));
        if (String(this.infoState[iid] ?? "rumor") === "rumor") {
          lines.push(`? Слух: ${inf.text ?? ""} (${n.name ?? "?"}, ${band})`);
        } else {
          lines.push(`❗ ${inf.text ?? ""} (${n.name ?? "?"})`);
        }
        lines.push("  🔮 " + String(inf.hint ?? ""));
      }
    }
    if (this.isUnlocked("agenda_view")) {
      lines.push("📊 О чём гудит город:");
      for (const t of this.D.topics?.topics ?? []) {
        const tid = String(t.id);
        lines.push(`• ${t.icon ?? ""} ${t.name ?? tid} — ${this.agendaWord(this.agenda.get(tid) ?? 0)}`);
      }
    } else {
      lines.push("(обзор повестки откроется позже)");
    }
    const met = [];
    for (const nid of this.talkedTo) {
      const n = this.npcById(String(nid));
      if (n.id) met.push(`${n.emoji ?? ""} ${n.name ?? ""}`);
    }
    if (met.length > 0) lines.push("🤝 Знакомые: " + this.sj(", ", met));
    return this.sj("\n", lines);
  }

  agendaWord(v) {
    if (v < 20) return "тихо";
    if (v < 35) return "поговаривают";
    if (v < 50) return "обсуждают";
    if (v < 65) return "гудит";
    if (v < 80) return "все только о нём!";
    return "КРИЗИС";
  }

  decisiveDay(topic) {
    for (const t of this.D.topics?.topics ?? []) {
      if (String(t.id ?? "") === topic) return t.decisive_day ?? 4;
    }
    return 4;
  }

  topicHome(topic) {
    for (const t of this.D.topics?.topics ?? []) {
      if (String(t.id ?? "") === topic) return String(t.home ?? "city");
    }
    return "city";
  }

  predictedTopics() {
    // Темы, где подтверждённая инфа добыта раньше решающего дня.
    const out = [];
    for (const t of this.D.topics?.topics ?? []) {
      const tid = String(t.id);
      const dd = t.decisive_day ?? 4;
      for (const iid of this.infoCollected) {
        const inf = this.infoById(String(iid));
        if (String(inf.topic ?? "") === tid && String(this.infoState[iid] ?? "") === "confirmed" && (this.infoDay[iid] ?? 99) < dd) {
          if (!out.includes(tid)) out.push(tid);
        }
      }
    }
    return out;
  }

  reminderFor(npcId) {
    // Старое активное обещание по темам этого NPC (для живого напоминания).
    const n = this.npcById(npcId);
    const topics = [];
    for (const iid of n.knowledge ?? []) {
      const inf = this.infoById(String(iid));
      if (inf.text !== undefined || inf.topic !== undefined) topics.push(String(inf.topic ?? ""));
    }
    let best = null;
    for (const p of this.promises) {
      if ((p.status === "promised" || p.status === "progress") && (p.created_day ?? this.day) < this.day && topics.includes(String(p.topic ?? ""))) {
        if (!best || (p.created_day ?? 0) < (best.created_day ?? 99)) best = p;
      }
    }
    return best ?? {};
  }

  relGate(opt, npcId) {
    // Пуста, если опцию можно выбрать; иначе причина блокировки.
    if (opt.needs_rel !== undefined) {
      const need = Number(opt.needs_rel);
      const has = this.rel.get(npcId) ?? 0;
      if (has < need) return "нужно больше доверия (поговори ещё)";
    }
    return "";
  }

  currentObjective() {
    if (!this.visited.includes("office")) {
      return { title: "Найди свой офис", hint: "Иди к зданию с вывеской ОФИС и зайди в дверь." };
    }
    if (this.talkedTo.length === 0) {
      return { title: "Поговори с жителями", hint: "Подойди к человеку и нажми E." };
    }
    if (this.infoCollected.length === 0) {
      return { title: "Узнай, что происходит", hint: "Расспрашивай людей о городе." };
    }
    if (this.promises.length === 0) {
      return { title: "Дай обещание", hint: "В разговоре выбери «Да, постараюсь!»." };
    }
    if (this.leaflets <= 0) {
      return { title: "Напечатай листовки", hint: "Принтер стоит в твоём офисе." };
    }
    let spread = false;
    for (const p of this.promises) if ((p.memory ?? 50) > 50) spread = true;
    if (!spread) {
      return { title: "Раздай листовки", hint: "Подходи к людям или клади в ящики. У своих тем — сильнее эффект." };
    }
    let done = false;
    for (const p of this.promises) if (p.status === "completed") done = true;
    if (!done) {
      return { title: "Выполни обещание", hint: "Нужны деньги и время. Начни с дешёвого." };
    }
    if (this.day <= 1) {
      return { title: "Дождись утра", hint: "Поспи на диване в офисе." };
    }
    return this.dayAdvice();
  }

  dayAdvice() {
    switch (this.day) {
      case 2: return { title: "Проверь слухи", hint: "Больница и школа — спроси врачей и учителей." };
      case 3: return { title: "Родители волнуются", hint: "Загляни в школу и почитай стенд." };
      case 4: return { title: "Город гудит", hint: "Школа и транспорт на устах. Решай, за что браться." };
      case 5: return { title: "День заседания", hint: "Мэрия делит бюджет. Нужен голос Кольцова." };
      case 6: return { title: "Битва за пустырь", hint: "Парк или парковка — выбери сторону." };
      default: return { title: "Выборы завтра", hint: "Выполни начатое. Люди всё помнят." };
    }
  }

  pickupPaper() {
    const p = this.todayPaper();
    if (!p.headline && !p.body) return "Газет нет.";
    this.paperSeen = true;
    this.unlockMechanic("newspaper");
    this.confirmTopic(String(p.topic ?? ""), "paper");
    this.stateChanged();
    return `📰 «${p.headline ?? ""}»\n${p.body ?? ""}`;
  }

  paperUnread() {
    return !this.paperSeen || (this.paperRead.last_day ?? 0) !== this.day;
  }

  infosOfDay(d) {
    return this.infoCollected.filter((iid) => (this.infoDay[String(iid)] ?? 0) === d);
  }

  promisesOfDay(d) {
    return this.promises.filter((p) => (p.created_day ?? 0) === d);
  }

  eventsOfDay(d) {
    return (this.D.events?.events ?? []).filter((e) => (e.day ?? 0) === d);
  }

  markPaperRead() {
    this.paperRead.last_day = this.day;
  }

  // ---------- время ----------

  // Продвинуть время. Возвращает текст предупреждения или "".
  advanceTime(cost) {
    if (this.gameOver) return "";
    this.minutes += cost;
    this.stateChanged();
    if (this.minutes >= DAY_END_MIN) return this.endDay();
    this.checkTutorial();
    return "";
  }

  endDay() {
    // итоги вечера + переход
    const summary = this.eveningSummary();
    if (this.day >= MAX_DAY) {
      this.runElection();
      this.justSlept = true;
      this.lastNight = summary;
      return summary;
    }
    this.day += 1;
    this.minutes = DAY_START_MIN;
    this.applyDayEvents(this.day);
    this.expirePromises();
    // растворение внимания
    for (const k of Array.from(this.agenda.keys())) {
      this.agenda.set(k, Math.max(5, (this.agenda.get(k) ?? 0) - 3));
    }
    // открытия по дням
    this.morningNotes = [];
    if (this.day >= 3 && this.unlockMechanic("printing")) this.morningNotes.push(this.mechToast("printing"));
    if (this.day >= 4 && this.unlockMechanic("agenda_view")) this.morningNotes.push(this.mechToast("agenda_view"));
    if (this.day >= 5 && this.unlockMechanic("budget")) this.morningNotes.push(this.mechToast("budget"));
    for (const f of this.onDayStarted) f(this.day);
    this.stateChanged();
    this.checkTutorial();
    this.justSlept = true;
    this.lastNight = summary;
    return summary;
  }

  eveningSummary() {
    const lines = [`🌙 Вечер дня ${this.day}.`];
    lines.push("Повестка: " + this.agendaLine());
    const urgent = [];
    for (const p of this.activePromises()) {
      const left = p.deadline - this.day;
      if (left <= 1) urgent.push(`«${p.title}» (дедлайн: день ${p.deadline})`);
    }
    if (urgent.length > 0) lines.push("⚠ К дедлайну близко:\n• " + this.sj("\n• ", urgent));
    else lines.push("Обещания под контролем.");
    return this.sj("\n", lines);
  }

  agendaLine() {
    const parts = [];
    for (const [tid, v] of this.agenda) {
      parts.push(`${this.topicIcon(tid)} ${this.topicName(tid)} ${v} (${this.agendaStage(v)})`);
    }
    return this.sj(" | ", parts);
  }

  applyDayEvents(forDay) {
    for (const e of this.D.events?.events ?? []) {
      if ((e.day ?? 0) === forDay) {
        const t = String(e.topic ?? "");
        if (this.agenda.has(t)) {
          this.agenda.set(t, Math.min(100, (this.agenda.get(t) ?? 0) + (e.delta ?? 10)));
        }
      }
    }
    // дороги после дня 5 дорожают
    if (forDay >= 6) {
      // цена обрабатывается в fulfill (наценка)
    }
  }

  expirePromises() {
    for (const p of this.promises) {
      if ((p.status === "promised" || p.status === "progress") && this.day > p.deadline) {
        p.status = "broken";
        for (const g of p.audience ?? []) {
          const gs = String(g);
          if (this.support.has(gs)) this.support.set(gs, Math.max(0, (this.support.get(gs) ?? 0) - 8));
        }
      }
    }
  }

  // ---------- действия ----------

  travelTo(locId) {
    if (this.gameOver) return "Игра окончена.";
    if (locId === this.currentLocation) return "Ты уже здесь.";
    const c = this.travelCost(this.currentLocation, locId);
    const dur = c[0];
    const price = c[1];
    if (this.money < price) return `Не хватает денег на поездку (${price}€).`;
    this.money -= price;
    this.currentLocation = locId;
    const warn = this.advanceTime(dur);
    let msg = `${this.locIcon(locId)} ${this.locationName(locId)}. Поездка ${dur} мин, ${price}€.`;
    if (warn !== "") msg += "\n\n" + warn;
    return msg;
  }

  locIcon(lid) {
    for (const l of this.D.locations?.locations ?? []) {
      if (l.id === lid) return String(l.icon ?? "📍");
    }
    return "📍";
  }

  applyDialogue(npcId, dlg, opt) {
    if (this.gameOver) return "Игра окончена.";
    const cost = dlg.time_cost ?? 20;
    const out = [];
    const n = this.npcById(npcId);
    out.push(`💬 ${n.name ?? "?"} (${n.profession ?? ""}), −${cost} мин.`);
    for (const iid of opt.give_info ?? []) out.push(...this.gainInfo(String(iid), npcId));
    for (const cid of opt.confirms ?? []) out.push(...this.confirmInfos([String(cid)]));
    for (const pid of opt.unlock_promises ?? []) {
      const ps = String(pid);
      if (!this.unlockedPromises.includes(ps)) {
        this.unlockedPromises.push(ps);
        const t = this.templateById(ps);
        out.push(`📝 Доступно обещание: «${t.title ?? ps}»`);
      }
      if (this.unlockMechanic("promises")) out.push(this.mechToast("promises"));
    }
    if (opt.creates_promise) {
      const cp = this.makePromiseSilent(String(opt.creates_promise));
      if (cp !== "") out.push(cp);
      if (this.unlockMechanic("promises")) out.push(this.mechToast("promises"));
    }
    if (opt.set_flag) {
      this.flags[String(opt.set_flag)] = true;
      out.push("🤝 Флаг: " + String(opt.set_flag));
    }
    const dr = opt.rel ?? 0;
    const pr = this.rel.get(npcId);
    if (dr !== 0 && pr !== undefined) this.rel.set(npcId, pr + dr);
    if (!this.talkedTo.includes(npcId)) this.talkedTo.push(npcId);
    if (this.unlockMechanic("talking")) out.push(this.mechToast("talking"));
    out.push("");
    out.push(String(opt.result ?? ""));
    const warn = this.advanceTime(cost);
    if (warn !== "") out.push("\n" + warn);
    return this.sj("\n", out);
  }

  makePromise(tid) {
    if (this.gameOver) return "Игра окончена.";
    const t = this.templateById(tid);
    if (!t.id && !t.title) return "Нет такого обещания.";
    for (const p of this.promises) {
      if (p.template === tid && (p.status === "promised" || p.status === "progress")) {
        return "Это обещание уже активно. Старые обещания не исчезают!";
      }
    }
    if (this.activePromises().length >= 8) return "Слишком много активных обещаний (8). Выполни старые!";
    this.uid += 1;
    this.promises.push({
      uid: `pr${this.uid}`,
      template: tid,
      title: String(t.title),
      topic: String(t.topic),
      audience: [...(t.audience ?? [])],
      cost: t.cost ?? 0,
      ftime: t.time_cost ?? 0,
      deadline: (t.deadline ?? 0) > 7 ? this.day + 6 : (t.deadline ?? 0),
      needs_kol: !!t.needs_kol,
      status: "promised",
      created_day: this.day,
      memory: 50,
      visibility: 20,
    });
    const warn = this.advanceTime(15);
    const back = this.promises[this.promises.length - 1];
    let msg = `📝 Обещание дано: «${t.title}» (день ${this.day}, дедлайн день ${back.deadline}). Подумай: сможешь ли выполнить?`;
    if (warn !== "") msg += "\n\n" + warn;
    return msg;
  }

  // Обещание прямо из диалога: без лишней траты времени (разговор уже оплачен).
  makePromiseSilent(tid) {
    if (this.gameOver) return "";
    const t = this.templateById(tid);
    if (!t.id && !t.title) return "";
    for (const p of this.promises) {
      if (p.template === tid && (p.status === "promised" || p.status === "progress")) {
        return "(это обещание уже дано)";
      }
    }
    if (this.activePromises().length >= 8) return "(слишком много обещаний — сначала выполни старые)";
    this.uid += 1;
    this.promises.push({
      uid: `pr${this.uid}`,
      template: tid,
      title: String(t.title),
      topic: String(t.topic),
      audience: [...(t.audience ?? [])],
      cost: t.cost ?? 0,
      ftime: t.time_cost ?? 0,
      deadline: (t.deadline ?? 0) > 7 ? this.day + 6 : (t.deadline ?? 0),
      needs_kol: !!t.needs_kol,
      status: "promised",
      created_day: this.day,
      memory: 50,
      visibility: 20,
    });
    this.stateChanged();
    return `✅ Новое обещание: «${t.title}»`;
  }

  fulfillPromise(uid) {
    if (this.gameOver) return "Игра окончена.";
    for (const p of this.promises) {
      if (p.uid !== uid) continue;
      if (!(p.status === "promised" || p.status === "progress")) return `Обещание уже закрыто (${p.status}).`;
      if (p.needs_kol && !this.flags.kol_support) {
        return "Нужна поддержка Кольцова! Договорись с ним в мэрии (день 1–5), иначе проект не пройдёт совет.";
      }
      let cost = p.cost ?? 0;
      if (p.template === "p_roads" && this.day >= 6) cost += 300; // смета сгорела
      if (this.money < cost) return `Не хватает денег: нужно ${cost}€, есть ${this.money}€.`;
      if (this.minutesLeft() < (p.ftime ?? 0)) return "Не хватает времени сегодня. Приходи завтра.";
      this.money -= cost;
      p.status = "completed";
      const boost = 8;
      for (const g of p.audience ?? []) {
        const gs = String(g);
        if (this.support.has(gs)) this.support.set(gs, Math.min(100, (this.support.get(gs) ?? 0) + boost));
      }
      const t = String(p.topic ?? "");
      if (this.agenda.has(t)) this.agenda.set(t, Math.max(5, (this.agenda.get(t) ?? 0) - 12)); // проблема решена — приоритет падает
      const warn = this.advanceTime(p.ftime ?? 0);
      let msg = `✅ Выполнено: «${p.title}» (−${cost}€, −${p.ftime} мин). Поддержка ${this.sj(", ", p.audience ?? [])} выросла!`;
      if (warn !== "") msg += "\n\n" + warn;
      return msg;
    }
    return "Обещание не найдено.";
  }

  printLeaflets() {
    if (this.gameOver) return "Игра окончена.";
    const tc = this.D.travel?.costs?.print_100 ?? [30, 150];
    const dur = tc[0];
    const price = tc[1];
    if (this.money < price) return `Нужно ${price}€, а есть ${this.money}€.`;
    if (this.minutesLeft() < dur) return "Не хватает времени сегодня.";
    this.money -= price;
    this.leaflets += 100;
    this.printedTotal += 100;
    this.unlockMechanic("campaigning"); // тост покажет мир через drainUnlocks
    const warn = this.advanceTime(dur);
    let msg = `🖨 Напечатано 100 листовок (−${price}€, −${dur} мин). Всего: ${this.leaflets}.`;
    if (warn !== "") msg += "\n\n" + warn;
    return msg;
  }

  distribute(mode) {
    if (this.gameOver) return "Игра окончена.";
    if (this.leaflets < 50) return "Нужно хотя бы 50 листовок. Напечатай в офисе.";
    const act = this.activePromises();
    if (act.length === 0) return "Сначала дай хоть одно обещание — разносить нечего.";
    if (mode === "hand") {
      if (this.minutesLeft() < 60) return `Нужно 60 мин, а осталось ${this.minutesLeft()}.`;
      this.leaflets = Math.max(0, this.leaflets - 100);
      this.distributedTotal += 100;
      let homeHit = false;
      for (const p of act) {
        const bonus = this.topicHome(String(p.topic ?? "")) === this.currentLocation;
        homeHit = homeHit || bonus;
        p.memory = Math.min(100, (p.memory ?? 50) + (bonus ? 35 : 25));
        p.visibility = Math.min(100, (p.visibility ?? 20) + (bonus ? 45 : 30));
        for (const g of p.audience ?? []) {
          const gs = String(g);
          if (this.support.has(gs)) this.support.set(gs, Math.min(100, (this.support.get(gs) ?? 0) + (bonus ? 6 : 3)));
        }
      }
      const warn = this.advanceTime(60);
      let msg = "📨 Раздал лично (−100 шт, −60 мин). Высокая запоминаемость! Обещания помнят лучше.";
      if (homeHit) msg += " Своя территория — эффект сильнее!";
      if (warn !== "") msg += "\n\n" + warn;
      return msg;
    } else {
      if (this.minutesLeft() < 20) return "Нужно 20 мин.";
      this.leaflets = Math.max(0, this.leaflets - 100);
      this.distributedTotal += 100;
      let homeHit2 = false;
      for (const p of act) {
        const bonus2 = this.topicHome(String(p.topic ?? "")) === this.currentLocation;
        homeHit2 = homeHit2 || bonus2;
        p.memory = Math.min(100, (p.memory ?? 50) + (bonus2 ? 15 : 10));
        p.visibility = Math.min(100, (p.visibility ?? 20) + (bonus2 ? 20 : 12));
        for (const g of p.audience ?? []) {
          const gs = String(g);
          if (this.support.has(gs)) this.support.set(gs, Math.min(100, (this.support.get(gs) ?? 0) + (bonus2 ? 2 : 1)));
        }
      }
      const warn = this.advanceTime(20);
      let msg = "📦 Массовый разброс (−100 шт, −20 мин). Охват большой, но запоминают слабо.";
      if (homeHit2) msg += " Своя территория — эффект сильнее!";
      if (warn !== "") msg += "\n\n" + warn;
      return msg;
    }
  }

  studyNotes() {
    if (this.gameOver) return "Игра окончена.";
    const warn = this.advanceTime(10);
    let msg = "📓 Заметки изучены (−10 мин).\n" + this.journalText();
    if (warn !== "") msg += "\n\n" + warn;
    return msg;
  }

  journalText() {
    if (this.infoCollected.length === 0) {
      return "Пока пусто. Поговори с жителями, специалистами, журналистом.";
    }
    const lines = [];
    for (const iid of this.infoCollected) {
      const inf = this.infoById(String(iid));
      if (!inf.text && !inf.topic) continue;
      lines.push(`• [${this.topicName(String(inf.topic ?? ""))}] ${inf.text ?? ""} (надёжность ${Math.round(Number(inf.reliability ?? 0.8) * 100)}%)\n  🔮 ${inf.hint ?? ""}`);
    }
    return this.sj("\n", lines);
  }

  todayPaper() {
    for (const p of this.D.newspaper?.papers ?? []) {
      if ((p.day ?? 0) === this.day) return p;
    }
    return {};
  }

  morningBrief() {
    const p = this.todayPaper();
    const lines = [`☀️ ${this.dayName()}, день ${this.day}/7. Время ${this.timeStr()}, бюджет ${this.money}€.`];
    if (p.headline || p.body) lines.push(`📰 «${p.headline ?? ""}»\n${p.body ?? ""}`);
    lines.push("📊 " + this.agendaLine());
    const rem = [];
    for (const pr of this.activePromises()) rem.push(`«${pr.title}» до дня ${pr.deadline} [${pr.status}]`);
    if (rem.length === 0) lines.push("Активных обещаний нет.");
    else lines.push("Активные обещания: " + this.sj("; ", rem));
    return this.sj("\n", lines);
  }

  locationFlavor(lid) {
    for (const l of this.D.locations?.locations ?? []) {
      if (l.id === lid) {
        const fb = l.flavor_by_day ?? {};
        if (fb[String(this.day)]) return String(fb[String(this.day)]);
        return String(l.desc ?? "");
      }
    }
    return "";
  }

  // ---------- выборы ----------

  templateImportance(tid) {
    const t = this.templateById(tid);
    return t.importance ?? 1;
  }

  runElection() {
    this.gameOver = true;
    let completed = 0;
    let broken = 0;
    for (const p of this.promises) {
      if (p.status === "completed") completed += 1;
      else if (p.status === "broken") broken += 1;
      else {
        p.status = "broken"; // невыполненное к выборам = нарушено
        broken += 1;
      }
    }
    // решённые темы: есть выполненное обещание
    const resolved = [];
    for (const t of this.D.topics?.topics ?? []) {
      const tid = String(t.id);
      for (const p of this.promises) {
        if (String(p.topic ?? "") === tid && String(p.status ?? "") === "completed") {
          if (!resolved.includes(tid)) resolved.push(tid);
        }
      }
    }
    // скрытая оценка качества кампании (игроку не показывается)
    let points = 0.0;
    for (const p of this.promises) {
      const imp = this.templateImportance(String(p.template ?? ""));
      if (String(p.status ?? "") === "completed") {
        points += imp * (1.0 + (p.memory ?? 50) / 100.0);
      } else {
        points -= imp * 1.5;
        if ((p.visibility ?? 20) >= 50) points -= imp * (p.visibility ?? 20) / 100.0; // позор разрекламированного провала
      }
    }
    const pred = this.predictedTopics();
    points += pred.length * 1.5;
    let avgSup = 0;
    if (this.support.size > 0) {
      let s = 0;
      for (const v of this.support.values()) s += v;
      avgSup = Math.trunc(s / this.support.size);
    }
    points += avgSup / 20.0;
    if (this.flags.kol_support) points += 1.0;
    const win = points >= 11.0 && broken <= 2;
    const supportCopy = new Map(this.support);
    const promisesCopy = this.promises.map((p) => ({ ...p }));
    this.election = {
      completed, broken,
      avg_support: avgSup, win,
      resolved, predicted: pred,
      support: supportCopy, promises: promisesCopy,
    };
    for (const f of this.onGameEnded) f(win);
    this.stateChanged();
  }

  electionText() {
    const e = this.election;
    if (!e || !Object.keys(e).length) return "Выборы ещё не прошли.";
    const lines = ["🗳 ВЫБОРЫ. Неделя закончена."];
    lines.push(`Ты обещал: ${this.promises.length} | Выполнил: ${e.completed ?? 0} | Провалил: ${e.broken ?? 0}`);
    lines.push("");
    const res = e.resolved ?? [];
    if (res.length === 0) lines.push("Решённых проблем нет.");
    else {
      lines.push("Проблемы, которые решил:");
      for (const tid of res) lines.push(`✓ ${this.topicIcon(String(tid))} ${this.topicName(String(tid))}`);
    }
    const missed = [];
    for (const t of this.D.topics?.topics ?? []) {
      const tid = String(t.id);
      if (!res.includes(tid) && ((this.agenda.get(tid) ?? 0) >= 50 || this.hasBrokenTopic(tid))) missed.push(tid);
    }
    if (missed.length > 0) {
      lines.push("Проблемы, которые упустил:");
      for (const tid of missed) lines.push(`✗ ${this.topicIcon(String(tid))} ${this.topicName(String(tid))}`);
    }
    const pred = e.predicted ?? [];
    if (pred.length > 0) {
      const pn = pred.map((tid) => this.topicName(String(tid)));
      lines.push("Ты заранее разгадал: " + this.sj(", ", pn) + ". Город это ценит.");
    }
    lines.push("");
    lines.push("Жители помнят твои обещания.");
    lines.push("");
    if (e.win) {
      lines.push("🎉 ПОБЕДА! Ты переизбран. Тебя помнят по делам, а не по словам.");
    } else {
      lines.push("💔 ПОРАЖЕНИЕ. Городу нужны были дела.");
      if ((e.completed ?? 0) < 3) lines.push("Совет: два дешёвых обещания — не кампания. Решай значимые проблемы и доводи до конца.");
      if ((e.broken ?? 0) > 2) lines.push("Совет: не давай обещаний, которые не потянешь. Люди помнят каждый провал.");
      if (pred.length === 0) lines.push("Совет: слушай людей раньше — кто предсказал повестку, тот успел первым.");
    }
    return this.sj("\n", lines);
  }

  hasBrokenTopic(tid) {
    return this.promises.some((p) => String(p.topic ?? "") === tid && String(p.status ?? "") === "broken");
  }

  // ---------- сейвы ----------

  saveGame() {
    const data = {
      day: this.day, minutes: this.minutes, money: this.money, leaflets: this.leaflets,
      current_location: this.currentLocation, info: this.infoCollected,
      unlocked: this.unlockedPromises, promises: this.promises,
      agenda: [...this.agenda.entries()], support: [...this.support.entries()], rel: [...this.rel.entries()],
      flags: this.flags, paper_read: this.paperRead,
      uid: this.uid, game_over: this.gameOver, election: { ...this.election, support: this.election?.support ? [...this.election.support.entries()] : [] },
      talked: this.talkedTo, printed: this.printedTotal, gave: this.distributedTotal,
      tut: this.tut, mechs: this.unlocked,
      info_state: this.infoState, info_source: this.infoSource, info_day: this.infoDay,
      visited: this.visited, hints: this.hintsSeen, paper_seen: this.paperSeen,
    };
    try {
      ls.set(SAVE_KEY, JSON.stringify(data));
      return `💾 Сохранено (день ${this.day}, ${this.timeStr()}).`;
    } catch {
      return "Не смог сохранить.";
    }
  }

  loadGame() {
    const txt = ls.get(SAVE_KEY);
    if (txt === null) return "Сохранения нет.";
    let data;
    try {
      data = JSON.parse(txt);
    } catch {
      return "Сохранение битое.";
    }
    this.day = data.day ?? 1;
    this.minutes = data.minutes ?? DAY_START_MIN;
    this.money = data.money ?? START_MONEY;
    this.leaflets = data.leaflets ?? 0;
    this.currentLocation = String(data.current_location ?? "office");
    this.infoCollected = data.info ?? [];
    this.unlockedPromises = data.unlocked ?? [];
    this.promises = data.promises ?? [];
    this.agenda = new Map(data.agenda ?? []);
    this.support = new Map(data.support ?? []);
    this.rel = new Map(data.rel ?? []);
    this.flags = data.flags ?? {};
    this.paperRead = data.paper_read ?? {};
    this.uid = data.uid ?? 0;
    this.gameOver = !!data.game_over;
    this.election = { ...(data.election ?? {}), support: new Map(data.election?.support ?? []) };
    this.talkedTo = data.talked ?? [];
    this.printedTotal = data.printed ?? 0;
    this.distributedTotal = data.gave ?? 0;
    const lt = data.tut ?? { step: 0, done: false, skipped: false, journal: false };
    this.tut = { step: lt.step ?? 0, done: !!lt.done, skipped: !!lt.skipped, journal: !!lt.journal };
    const lu = { talking: false, promises: false, notebook: false, printing: false, campaigning: false, agenda_view: false, budget: false, politicians: false, newspaper: false };
    const su = data.mechs ?? {};
    for (const k of Object.keys(lu)) lu[k] = !!su[k];
    this.unlocked = lu;
    this.infoState = data.info_state ?? {};
    this.infoSource = data.info_source ?? {};
    this.infoDay = data.info_day ?? {};
    this.visited = data.visited ?? [];
    this.hintsSeen = data.hints ?? [];
    this.paperSeen = !!data.paper_seen;
    this.stateChanged();
    if (this.gameOver) for (const f of this.onGameEnded) f(!!this.election.win);
    return `📂 Загружено (день ${this.day}, ${this.timeStr()}).`;
  }

  hasSave() {
    return ls.get(SAVE_KEY) !== null;
  }

  resetRun() {
    this.day = 1;
    this.minutes = DAY_START_MIN;
    this.money = START_MONEY;
    this.leaflets = 0;
    this.currentLocation = "office";
    this.infoCollected = [];
    this.unlockedPromises = []; // всё открывается только через разговоры
    this.promises = [];
    this.flags = {};
    this.paperRead = {};
    this.gameOver = false;
    this.election = {};
    this.uid = 0;
    this.agenda = new Map();
    for (const t of this.D.topics?.topics ?? []) this.agenda.set(t.id, t.base ?? 15);
    this.support = new Map();
    for (const g of this.GROUP_NAMES.keys()) this.support.set(g, 30);
    this.rel = new Map();
    for (const n of this.D.npcs?.npcs ?? []) this.rel.set(n.id, 0);
    this.talkedTo = [];
    this.printedTotal = 0;
    this.distributedTotal = 0;
    this.tut = { step: 0, done: false, skipped: false, journal: false };
    this.unlocked = { talking: false, promises: false, notebook: false, printing: false, campaigning: false, agenda_view: false, budget: false, politicians: false, newspaper: false };
    this.infoState = {};
    this.infoSource = {};
    this.infoDay = {};
    this.visited = [];
    this.hintsSeen = [];
    this.paperSeen = false;
    this.morningNotes = [];
    this.timeBank = 0.0;
    this.lastUnlocks = [];
    this.justSlept = false;
    this.lastNight = "";
    this.spawnOverride = null;
    this.stateChanged();
  }
}
