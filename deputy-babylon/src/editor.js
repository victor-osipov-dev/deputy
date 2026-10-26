// Редактор карты города: перетаскивание объектов мышью, подписи «что это»,
// сохранение раскладки в data/city_layout.json (через dev-сервер) или скачивание файла.

export class Editor {
  constructor(world) {
    this.world = world;
    this.active = false;
    this.items = [];
    this.sel = null;
    this.hover = null;
    this.drag = null;
    this.mouse = { x: 0, y: 0 };
    this.$ = (id) => document.getElementById(id);
    this.panel = this.$("editor");
    this.list = this.$("ed-list");
    this.tip = this.$("ed-tip");
    this.status = this.$("ed-status");
    this.bind();
  }

  bind() {
    this.$("ed-save").addEventListener("click", () => this.save());
    this.$("ed-download").addEventListener("click", () => this.download());
    this.$("ed-reset").addEventListener("click", () => this.reset());
    this.$("ed-close").addEventListener("click", () => this.setActive(false));

    const canvas = this.world.canvas;
    canvas.addEventListener("pointermove", (e) => this.onMove(e));
    canvas.addEventListener("pointerdown", (e) => this.onDown(e));
    canvas.addEventListener("pointerup", (e) => this.onUp(e));
    canvas.addEventListener("pointercancel", () => { this.drag = null; });
    canvas.addEventListener("wheel", (e) => e.preventDefault(), { passive: false });

    window.addEventListener("keydown", (e) => {
      if (e.code === "F2") {
        this.setActive(!this.active);
        e.preventDefault();
        return;
      }
      if (!this.active) return;
      if (e.code === "Delete" || e.code === "Escape") {
        this.sel = null;
        this.refreshPanel();
        e.preventDefault();
        return;
      }
      // Стрелки: точное перемещение выбранного объекта (1px, Shift — 10px)
      const step = e.shiftKey ? 10 : 1;
      let dx = 0, dy = 0;
      if (e.code === "ArrowLeft") dx = -step;
      else if (e.code === "ArrowRight") dx = step;
      else if (e.code === "ArrowUp") dy = -step;
      else if (e.code === "ArrowDown") dy = step;
      if ((dx || dy) && this.sel) {
        const [x, y] = this.sel.get();
        this.sel.set(Math.round(x + dx), Math.round(y + dy));
        this.world.rebuildCity();
        this.refreshPanel();
        e.preventDefault();
      }
    });
  }

  setActive(on) {
    this.active = on;
    this.world.editorActive = on;
    this.world.editor = this;
    this.panel.classList.toggle("hidden", !on);
    this.$("hud").style.opacity = on ? "0.25" : "";
    this.$("prompt").classList.add("hidden");
    if (on) {
      this.items = this.world.editorItems();
      this.refreshPanel();
      this.toast("Редактор: перетаскивай объекты мышью, F2 — выход");
    } else {
      this.sel = null;
      this.hover = null;
      this.tip.classList.add("hidden");
    }
  }

  toast(text) {
    const el = document.createElement("div");
    el.className = "ed-toast";
    el.textContent = text;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 3200);
  }

  refreshPanel() {
    if (!this.list) return;
    this.items = this.world.editorItems();
    this.list.innerHTML = "";
    for (const it of this.items) {
      const row = document.createElement("button");
      row.className = "ed-row" + (it === this.sel ? " sel" : "");
      row.textContent = it.label;
      const [x, y] = it.get();
      const coords = document.createElement("span");
      coords.className = "ed-coords";
      coords.textContent = `${Math.round(x)}, ${Math.round(y)}`;
      row.appendChild(coords);
      row.addEventListener("click", () => {
        this.sel = it;
        this.centerOn(x, y);
        this.refreshPanel();
      });
      this.list.appendChild(row);
    }
    this.updateStatus();
  }

  updateStatus() {
    if (!this.status) return;
    if (this.sel) {
      const [x, y] = this.sel.get();
      this.status.textContent = `Выбрано: ${this.sel.label} — ${Math.round(x)}, ${Math.round(y)} (стрелки — точнее, Shift — ×10)`;
    } else {
      this.status.textContent = "Клик — выбрать, тяни — двигать. WASD — камера. Стрелки — точное перемещение.";
    }
  }

  centerOn(x, y) {
    this.world.cam.x = x;
    this.world.cam.y = y;
  }

  // экранные координаты → мировые
  toWorld(e) {
    const r = this.world.canvas.getBoundingClientRect();
    const camX = this.world.cam.x - this.world.view.w / 2;
    const camY = this.world.cam.y - this.world.view.h / 2;
    return { x: e.clientX - r.left + camX, y: e.clientY - r.top + camY };
  }

  hitTest(wx, wy) {
    // сверху вниз: последние в списке — поверх
    for (let i = this.items.length - 1; i >= 0; i -= 1) {
      const b = this.items[i].bounds();
      if (wx >= b.x && wx <= b.x + b.w && wy >= b.y && wy <= b.y + b.h) return this.items[i];
    }
    return null;
  }

  onMove(e) {
    if (!this.active) return;
    this.mouse = { x: e.clientX, y: e.clientY };
    const w = this.toWorld(e);
    if (this.drag) {
      const nx = Math.round(w.x - this.drag.offX);
      const ny = Math.round(w.y - this.drag.offY);
      this.drag.item.set(nx, ny);
      this.world.rebuildCity();
      this.updateStatus();
      if (this.sel === this.drag.item) {
        const st = this.status;
        if (st) st.textContent = `Двигаем: ${this.drag.item.label} — ${nx}, ${ny}`;
      }
      return;
    }
    this.hover = this.hitTest(w.x, w.y);
    if (this.hover) {
      this.tip.classList.remove("hidden");
      this.tip.textContent = this.hover.label;
      this.tip.style.left = `${e.clientX + 14}px`;
      this.tip.style.top = `${e.clientY + 12}px`;
      this.world.canvas.style.cursor = "grab";
    } else {
      this.tip.classList.add("hidden");
      this.world.canvas.style.cursor = "default";
    }
  }

  onDown(e) {
    if (!this.active || e.button !== 0) return;
    const w = this.toWorld(e);
    const it = this.hitTest(w.x, w.y);
    if (!it) {
      this.sel = null;
      this.refreshPanel();
      return;
    }
    this.sel = it;
    this.items = this.world.editorItems();
    const [x, y] = it.get();
    this.drag = { item: it, offX: w.x - x, offY: w.y - y };
    this.world.canvas.style.cursor = "grabbing";
    this.refreshPanel();
    e.preventDefault();
  }

  onUp() {
    if (!this.active) return;
    this.drag = null;
    if (this.world.canvas) this.world.canvas.style.cursor = "grab";
    this.refreshPanel();
  }

  // ---------- сохранение ----------

  async save() {
    const data = this.world.layout;
    try {
      const r = await fetch("/__save__", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ file: "city_layout.json", data }),
      });
      const j = await r.json();
      if (j.ok) this.toast("💾 Сохранено в data/city_layout.json");
      else this.toast(`⚠ Не сохранилось: ${j.error ?? "ошибка"}`);
    } catch {
      this.toast("⚠ Сервер не пишет файлы — скачай JSON кнопкой «Скачать JSON»");
    }
    this.notifyGodot();
  }

  // Подсказка: как перенести раскладку в Godot-версию
  notifyGodot() {
    void 0;
  }

  download() {
    const data = JSON.stringify(this.world.layout, null, 2);
    const blob = new Blob([data], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "city_layout.json";
    a.click();
    URL.revokeObjectURL(a.href);
    this.toast("⬇ city_layout.json скачан — положи в deputy-babylon/data/");
  }

  reset() {
    this.world.layout = this.world.defaultLayout();
    this.world.rebuildCity();
    this.sel = null;
    this.refreshPanel();
    this.toast("↺ Раскладка сброшена к city.json");
  }

  // ---------- отрисовка ----------

  drawOverlay(ctx, camX, camY) {
    if (!this.active) return;
    ctx.save();
    ctx.translate(-camX, -camY);
    // подписи всех объектов
    ctx.font = "14px system-ui, sans-serif";
    ctx.textAlign = "left";
    for (const it of this.items) {
      const b = it.bounds();
      const isSel = it === this.sel;
      const isHover = it === this.hover;
      let color = "rgba(160,220,255,0.75)";
      if (isSel) color = "rgba(255,220,90,0.9)";
      else if (isHover) color = "rgba(255,255,255,0.95)";
      // рамка объекта (для точек — маленький маркер)
      ctx.strokeStyle = color;
      ctx.lineWidth = isSel ? 3 : 1.5;
      if (b.w > 90 || b.h > 90) {
        ctx.strokeRect(b.x, b.y, b.w, b.h);
      } else {
        ctx.strokeRect(b.x + b.w / 2 - 6, b.y + b.h / 2 - 6, 12, 12);
      }
      // подпись (только для видимых на экране)
      if (b.x + b.w > camX - 100 && b.x < camX + this.world.view.w + 100
        && b.y + b.h > camY - 100 && b.y < camY + this.world.view.h + 100) {
        const lx = b.x + 4;
        const ly = b.y + 14;
        const txt = it.label;
        const tw = ctx.measureText(txt).width;
        ctx.fillStyle = "rgba(8,10,16,0.72)";
        ctx.fillRect(lx - 3, ly - 12, tw + 8, 18);
        ctx.fillStyle = color;
        ctx.fillText(txt, lx, ly + 2);
      }
    }
    ctx.restore();
  }
}
