// UI — порт scripts/world/world_ui.gd (Godot CanvasLayer) на DOM-оверлей.
// HUD, подсказки, телефон, диалоги, ночь, выборы, меню, тосты.

export class UI {
  constructor(game, world) {
    this.game = game;
    this.world = world; // может быть null до сборки мира
    this.dlgNpc = "";
    this.dlgData = {};
    this.phoneTab = "map";
    this.modals = {}; // name -> {dim, panel, body, ...}

    game.onState.push(() => this.refreshHud());
    game.onGameEnded.push(() => this.showElection());
  }

  $id(id) { return document.getElementById(id); }

  init() {
    this.$id("btn-phone").addEventListener("click", () => this.togglePhone());
    this.$id("btn-menu").addEventListener("click", () => this.toggleMenu());
    const prompt = this.$id("prompt");
    prompt.addEventListener("click", () => {
      const t = this.world?.target;
      if (t) this.world.doInteract(t);
    });
    this.refreshHud();
    this.buildDialog();
    this.buildPhone();
    this.buildNight();
    this.buildElection();
    this.buildMenu();
  }

  blocksWorld() {
    return Object.values(this.modals).some((m) => m.dim.style.display !== "none");
  }

  // ---------- база (modal_shell) ----------

  modal(name, width, buildContent) {
    const dim = document.createElement("div");
    dim.className = "dim";
    dim.style.display = "none";
    const panel = document.createElement("div");
    panel.className = "panel";
    panel.style.width = `${Math.min(width, window.innerWidth * 0.94)}px`;
    dim.appendChild(panel);
    this.$id("modal-root").appendChild(dim);
    const m = { dim, panel, box: panel, body: null };
    this.modals[name] = m;
    buildContent(m);
    return m;
  }

  label(parent, text, size = 18, cls = "") {
    const d = document.createElement("div");
    d.textContent = text;
    d.style.fontSize = `${size}px`;
    d.style.textShadow = "2px 2px 0 rgba(0,0,0,.9)";
    if (cls) d.className = cls;
    parent.appendChild(d);
    return d;
  }

  button(parent, text, onclick, cls = "btn") {
    const b = document.createElement("button");
    b.className = cls;
    b.textContent = text;
    if (onclick) b.addEventListener("click", onclick);
    parent.appendChild(b);
    return b;
  }

  body(m, fontSize = 18) {
    const body = document.createElement("div");
    body.className = "body";
    body.style.fontSize = `${fontSize}px`;
    m.box.appendChild(body);
    m.body = body;
    return body;
  }

  // ---------- HUD ----------

  refreshHud() {
    this.$id("hud-day").textContent = `День ${this.game.day}/7 • ${this.game.timeStr()}`;
    this.$id("hud-money").textContent = `€${this.game.money} • 📄${this.game.leaflets}`;
    this.refreshObjective();
  }

  refreshObjective() {
    const o = this.game.currentObjective();
    this.$id("hud-obj").textContent = `➤ ${o.title ?? ""}`;
  }

  // ---------- тосты ----------

  toast(text) {
    const box = this.$id("toasts");
    while (box.children.length >= 3) box.firstChild.remove();
    const d = document.createElement("div");
    d.className = "toast";
    d.textContent = text;
    box.appendChild(d);
    setTimeout(() => d.remove(), 4300);
  }

  drainUnlocksToasts() {
    for (const t of this.game.drainUnlocks()) this.toast(t);
    this.refreshObjective();
  }

  // ---------- подсказка ----------

  setPrompt(text) {
    const p = this.$id("prompt");
    if (!text) {
      p.classList.add("hidden");
      return;
    }
    p.textContent = `E — ${text}`;
    p.classList.remove("hidden");
  }

  // ---------- диалог ----------

  buildDialog() {
    this.modal("dialog", 640, (m) => {
      m.title = this.label(m.box, "Диалог", 22);
      m.remind = this.label(m.box, "", 17, "lbl-amber");
      m.bodyEl = this.body(m, 19);
      m.opts = document.createElement("div");
      m.opts.className = "buttons";
      m.box.appendChild(m.opts);
      this.button(m.box, "Уйти", () => { m.dim.style.display = "none"; });
    });
  }

  openDialog(npcId) {
    const n = this.game.npcById(npcId);
    if (!n.id) return;
    const dlg = this.game.dialogueById(String(n.dialogue ?? ""));
    if (!dlg.id && !dlg.npc_text) {
      this.toast("Не о чем говорить.");
      return;
    }
    this.dlgNpc = npcId;
    this.dlgData = dlg;
    const m = this.modals.dialog;
    m.title.textContent = `${n.emoji ?? ""} ${n.name ?? ""} — ${n.profession ?? ""}`;
    const rem = this.game.reminderFor(npcId);
    if (!rem || !rem.title) {
      m.remind.style.display = "none";
    } else {
      m.remind.style.display = "";
      m.remind.textContent = `«Вы же обещали: ${rem.title}. Когда сделаете?»`;
    }
    m.bodyEl.textContent = `${dlg.npc_text ?? ""}\n(~${dlg.time_cost ?? 20} мин)`;
    for (const nt of this.game.noteDialogueShown(dlg)) this.toast(nt);
    this.drainUnlocksToasts();
    this.fillOptions();
    m.dim.style.display = "";
  }

  fillOptions() {
    const m = this.modals.dialog;
    m.opts.innerHTML = "";
    for (const opt of this.dlgData.options ?? []) {
      const lock = this.game.relGate(opt, this.dlgNpc);
      let text = String(opt.text ?? "...");
      const b = document.createElement("button");
      b.className = "btn";
      if (lock !== "") {
        b.textContent = `🔒 ${text} (${lock})`;
        b.disabled = true;
      } else {
        b.textContent = text;
        b.addEventListener("click", () => this.onDlgChoice(opt));
      }
      m.opts.appendChild(b);
    }
    if (this.canHand()) {
      this.button(m.opts, "📨 Вручить листовку лично", () => this.onHand());
    }
  }

  canHand() {
    return this.game.isUnlocked("campaigning") && this.game.leaflets >= 50
      && this.game.activePromises().length > 0 && this.game.minutesLeft() >= 60;
  }

  onHand() {
    const m = this.modals.dialog;
    m.dim.style.display = "none";
    this.world._afterAction(this.game.distribute("hand"));
    this.drainUnlocksToasts();
    this.toast("📨 Листовка вручена лично.");
  }

  onDlgChoice(opt) {
    const m = this.modals.dialog;
    const res = this.game.applyDialogue(this.dlgNpc, this.dlgData, opt);
    m.opts.innerHTML = "";
    m.bodyEl.textContent = res;
    this.drainUnlocksToasts();
    this.refreshObjective();
    this.world._afterAction("");
  }

  // ---------- телефон ----------

  buildPhone() {
    this.modal("phone", 640, (m) => {
      this.label(m.box, "📱 Телефон депутата", 22);
      m.tabs = document.createElement("div");
      m.tabs.className = "tab-strip";
      m.box.appendChild(m.tabs);
      m.bodyEl = this.body(m, 18);
      m.opts = m.bodyEl;
      this.button(m.box, "Закрыть", () => { m.dim.style.display = "none"; });
    });
  }

  togglePhone() {
    const m = this.modals.phone;
    if (m.dim.style.display !== "none") {
      m.dim.style.display = "none";
      return;
    }
    this.phoneTab = "map";
    this.drawPhone();
    m.dim.style.display = "";
  }

  drawPhone() {
    const m = this.modals.phone;
    m.tabs.innerHTML = "";
    m.bodyEl.innerHTML = "";
    const tabs = [
      ["🗺 Карта", "map", true],
      ["📓 Блокнот", "notes", this.game.isUnlocked("notebook")],
      ["📝 Обещания", "promises", this.game.isUnlocked("promises")],
      ["📰 Газета", "paper", this.game.isUnlocked("newspaper")],
    ];
    for (const t of tabs) {
      const b = this.button(m.tabs, t[0], () => this.onPhoneTab(t[1]), "btn inline");
      b.disabled = !t[2];
    }
    if (this.phoneTab === "map") this.phoneMap();
    else if (this.phoneTab === "notes") this.phoneNotes();
    else if (this.phoneTab === "promises") this.phonePromises();
    else if (this.phoneTab === "paper") this.phonePaper();
  }

  onPhoneTab(t) {
    this.phoneTab = t;
    this.drawPhone();
  }

  plabel(parent, text, size = 18) {
    const d = this.label(parent, text, size);
    d.style.whiteSpace = "pre-wrap";
    return d;
  }

  phoneMap() {
    const b = this.modals.phone.bodyEl;
    if (this.game.currentLocation === "city" || this.game.currentLocation === "district") {
      this.plabel(b, "🗺 Город. Ты на улицах.", 19);
    } else {
      this.plabel(b, `🗺 Город. Ты здесь: ${this.game.locationName(this.game.currentLocation)}.`, 19);
    }
    for (const l of this.game.D.locations?.locations ?? []) {
      const mark = this.game.visited.includes(String(l.id)) ? "✓" : "·";
      this.plabel(b, `${mark} ${l.icon ?? ""} ${l.name ?? ""} ${l.desc ?? ""}`, 17);
    }
    this.plabel(b, "🚌 Автобус между Центром и Районом: 8 мин, 5€.", 16);
  }

  phoneNotes() {
    this.plabel(this.modals.phone.bodyEl, this.game.journalNotebook(), 17);
  }

  phonePromises() {
    const b = this.modals.phone.bodyEl;
    const act = this.game.activePromises();
    if (this.game.isUnlocked("budget")) {
      this.plabel(b, `💰 Офисный бюджет: €${this.game.money}. Большие траты — через совет.`, 17);
    }
    if (act.length === 0) this.plabel(b, "Активных обещаний нет. Их дают в разговорах.", 17);
    for (const p of act) {
      const left = p.deadline - this.game.day;
      this.plabel(b, `«${p.title}» — до дня ${p.deadline} (осталось ${left} дн.), ${p.cost}€.`, 17);
      this.button(b, `✅ Выполнить (−${p.cost}€)`, () => this.onFulfill(String(p.uid)));
    }
    this.plabel(b, "Где пообещать (подойди лично):", 18);
    let any = false;
    for (const tid of this.game.unlockedPromises) {
      const t = this.game.templateById(String(tid));
      if (!t.title) continue;
      const dup = this.game.promises.some((p) => p.template === tid && ["promised", "progress", "completed"].includes(p.status));
      if (dup) continue;
      any = true;
      const extra = t.needs_kol ? " ⚠ нужен Кольцов" : "";
      this.plabel(b, `«${t.title}» (${t.cost}€${extra})\n➤ ${this.whoGives(String(tid))}`, 16);
    }
    if (!any) this.plabel(b, "Новых нет — говори с людьми.", 16);
  }

  // Справочник: у кого и где даётся обещание (без удалённой выдачи).
  whoGives(tid) {
    const parts = [];
    for (const n of this.game.D.npcs?.npcs ?? []) {
      if ((n.promises ?? []).includes(tid)) {
        const post = this.game.npcWhere(String(n.id ?? ""));
        if (!post.loc) {
          parts.push(`${n.name ?? "?"} (сейчас не найти — обычно: ${this.game.locationName(String(n.location ?? ""))})`);
        } else if (["city", "district"].includes(String(post.loc))) {
          parts.push(`${n.name ?? "?"} (сейчас: на улицах, район)`);
        } else {
          parts.push(`${n.name ?? "?"} (сейчас: ${this.game.locationName(String(post.loc))})`);
        }
      }
    }
    if (parts.length === 0) return "расспроси людей в городе";
    return this.game.sj("; ", parts);
  }

  onFulfill(uid) {
    this.toast(this.game.fulfillPromise(uid));
    this.drainUnlocksToasts();
    this.world._afterAction("");
    this.drawPhone();
  }

  phonePaper() {
    const b = this.modals.phone.bodyEl;
    const p = this.game.todayPaper();
    if (!p.headline && !p.body) this.plabel(b, "Сегодня выпуска нет.", 18);
    else {
      this.plabel(b, `День ${p.day ?? 1}: ${p.headline ?? ""}`, 20);
      this.plabel(b, String(p.body ?? ""), 18);
    }
    this.game.markPaperRead();
  }

  openPaper(text) {
    this.phoneTab = "paper";
    this.drawPhone();
    this.modals.phone.dim.style.display = "";
    this.toast(text.split("\n")[0]);
  }

  // ---------- ночь / выборы / меню ----------

  buildNight() {
    this.modal("night", 620, (m) => {
      m.title = this.label(m.box, "", 24);
      m.bodyEl = this.body(m, 18);
      this.button(m.box, "☀ Проснуться в офисе", () => {
        m.dim.style.display = "none";
        this.world.wakeHome();
      });
    });
  }

  showNight(_summary) {
    const m = this.modals.night;
    m.title.textContent = this.game.day > 1 ? `ДЕНЬ ${Math.min(this.game.day - 1, 7)} ЗАКОНЧЕН` : "НОЧЬ";
    const lines = [];
    const learned = this.game.infosOfDay(Math.min(this.game.day - 1, 7));
    if (learned.length > 0) {
      lines.push("Ты узнал:");
      for (const iid of learned) lines.push(`• ${this.game.infoById(iid).text ?? iid}`);
    }
    const made = this.game.promisesOfDay(Math.min(this.game.day - 1, 7));
    if (made.length > 0) {
      lines.push("Ты обещал:");
      for (const p of made) lines.push(`• ${p.title ?? ""}`);
    }
    const tom = this.game.eventsOfDay(this.game.day);
    if (tom.length > 0 && this.game.day <= 7) {
      lines.push("Завтра:");
      for (const e of tom) lines.push(`• ${e.title ?? ""}`);
    }
    for (const note of this.game.morningNotes) lines.push(note);
    this.game.morningNotes = [];
    if (lines.length === 0) lines.push("Спокойная ночь.");
    m.bodyEl.textContent = this.game.sj("\n", lines);
    m.dim.style.display = "";
  }

  buildElection() {
    this.modal("election", 620, (m) => {
      this.label(m.box, "🗳 Выборы", 24);
      m.bodyEl = this.body(m, 18);
      this.button(m.box, "🔄 Начать заново", () => {
        m.dim.style.display = "none";
        this.game.resetRun();
        this.world.gotoMap("city", { x: 460, y: 930 });
      });
    });
  }

  showElection() {
    const m = this.modals.election;
    m.bodyEl.textContent = this.game.electionText();
    m.dim.style.display = "";
  }

  buildMenu() {
    this.modal("menu", 420, (m) => {
      this.label(m.box, "Меню", 22);
      const items = [
        ["💾 Сохранить", () => { this.toast(this.game.saveGame()); }],
        ["📂 Загрузить", () => {
          const msg = this.game.loadGame();
          this.world.gameOverRelaunch();
          this.toast(msg);
        }],
        ["🔄 Заново", () => {
          m.dim.style.display = "none";
          this.game.resetRun();
          this.world.gotoMap("city", { x: 460, y: 930 });
        }],
        ["Закрыть", () => { m.dim.style.display = "none"; }],
      ];
      for (const it of items) this.button(m.box, it[0], it[1]);
    });
  }

  toggleMenu() {
    const m = this.modals.menu;
    m.dim.style.display = m.dim.style.display === "none" ? "" : "none";
  }
}
