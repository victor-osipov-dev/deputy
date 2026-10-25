// World — порт scripts/world/{world_base,city,interior,player,npc}.gd.
// Мир рисуется каждый кадр в 2D-контекст Babylon DynamicTexture (режим city/interior).

import * as Tex from "./tex.js";

const PX = Tex.PX;

// ---------- константы city.gd ----------
const STYLE = {
  office: [227, 47, 30],
  school: [223, 39, 29],
  city_hall: [231, 51, 29],
  hospital: [235, 47, 30],
  news: [239, 55, 29],
};
const T_GRASS = 889, T_SIDE = 740, T_TAN = 745, T_ASPH = 750, T_YEL = 752, T_CROSS = 824, T_DOOR_ROW = 16;

// ---------- константы interior.gd ----------
const T_FLOOR = 745, T_WALLI = 227;
const FURN = {
  "Стол": 546, "Принтерная": 545, "Диван-кровать": 849,
  "Класс 1": 543, "Класс 2": 544, "Кабинет директора": 886,
  "Приёмная": 548, "Зал заседаний": 805, "Палата": 886,
  "Склад лекарств": 579, "Отдел новостей": 804, "Архив": 875,
};
const PROP_TILE = { printer: 545, paper: 547, bed: 849, info_board: 616, flavor: 543 };

// ---------- world_base.gd ----------
const WALK_MIN_PER_SEC = 1.0 / 0.8; // 1 игровая минута = 0.8 реальной секунды
const IDLE_MIN_PER_SEC = 0.05;
const IDLE_LIMIT = 30.0;
const SPEED = 230.0; // player.gd
const SENSOR_R = 95.0;

export class World {
  constructor(game, ui, canvas) {
    this.game = game;
    this.ui = ui;
    this.canvas = canvas; // HTML canvas (Babylon)
    this.mode = "city"; // city | interior
    this.conf = {};
    this.city = {};
    this.mapId = "city";

    this.player = { x: 460, y: 930, r: 14, vx: 0, vy: 0, stepPhase: 0, frozen: false };
    this.joy = { x: 0, y: 0, active: false };

    this.solids = [];         // {x,y,w,h}
    this.interact = [];       // {x,y,r,kind,...}
    this.ylist = [];          // [{y, draw(ctx)}] сортируется по y
    this.groundFns = [];      // земляной слой
    this.labelsCity = [];     // подписи рисуются в ysort-проходе
    this.districtRect = null; // {x,y,w,h}
    this.park = null;

    this.cam = { x: 460, y: 930 };
    this.still = 0;
    this.idleWarned = false;
    this.target = null;
    this.rngState = 12345; // _rng.seed = 12345 (для деревьев)
    this.keys = new Set();

    this.view = { w: 1280, h: 720 };

    // Рендер в 2D-контекст Babylon DynamicTexture создаётся в main.js и передаётся вызовом render(ctx).
  }

  attachInput() {
    // Порт input-маппинга project.godot:
    // A/←, D/→, W/↑, S/↓; E/Space — interact; Tab/Q — phone; Esc — menu.
    const MAP = {
      KeyA: "move_left", ArrowLeft: "move_left",
      KeyD: "move_right", ArrowRight: "move_right",
      KeyW: "move_up", ArrowUp: "move_up",
      KeyS: "move_down", ArrowDown: "move_down",
    };
    window.addEventListener("keydown", (e) => {
      if (e.repeat) return;
      const m = MAP[e.code];
      if (m) { this.keys.add(m); e.preventDefault(); return; }
      if (e.code === "KeyE" || e.code === "Space") {
        this.doInteract(this.target);
        e.preventDefault();
      } else if (e.code === "Tab" || e.code === "KeyQ") {
        this.ui.togglePhone();
        e.preventDefault();
      } else if (e.code === "Escape") {
        this.ui.toggleMenu();
        e.preventDefault();
      }
    });
    window.addEventListener("keyup", (e) => {
      const m = MAP[e.code];
      if (m) this.keys.delete(m);
    });
    window.addEventListener("blur", () => this.keys.clear());
  }

  viewW() { return this.canvas.clientWidth || 1280; }
  viewH() { return this.canvas.clientHeight || 720; }

  // отладочный прями ГПСЧ (детерминизм как _rng при seed 12345 не требуется точно,
  // главное — стабильность внутри карты)
  rand() {
    this.rngState = (this.rngState * 1103515245 + 12345) & 0x7fffffff;
    return this.rngState / 0x7fffffff;
  }

  // ================= сборка карт =================

  buildCity() {
    this.mode = "city";
    this.mapId = "city";
    this.city = this.game.D.city ?? {};
    const W = (this.city.size ?? [2400, 1600])[0];
    const H = (this.city.size ?? [2400, 1600])[1];
    this.worldSize = { w: W, h: H };
    this.solids = [];
    this.interact = [];
    this.ylist = [];
    this.groundFns = [];
    this.buildingRects = [];
    this.roadRects = [];
    this.rngState = 12345;

    // земля: тротуар везде
    this.groundFns.push((ctx) => Tex.tiled(ctx, T_SIDE, 0, 0, W, H));
    // парк (зелёный)
    const pk = this.city.park ?? {};
    this.groundFns.push((ctx) => Tex.tiled(ctx, T_GRASS, pk.x ?? 1650, pk.y ?? 120, pk.w ?? 600, pk.h ?? 260));
    this._walls(W, H);
    // площадь: до дорог, и не на дороге (сдвигаем влево от вертикальной)
    const pl = (this.city.plaza ?? [1080, 640, 260, 100]).slice();
    const rv = (this.city.roads ?? []).find((r) => r[2] < r[3]); // вертикальная дорога
    if (rv && pl[0] + pl[2] > rv[0] - 20) pl[0] = rv[0] - pl[2] - 20;
    this.groundFns.push((ctx) => Tex.tiled(ctx, T_TAN, pl[0], pl[1], pl[2], pl[3]));
    for (const r of this.city.roads ?? []) this._road(r[0], r[1], r[2], r[3]);
    // перекрёстки: чистый асфальт поверх разметки/тротуаров
    // зона дороги с её тротуарами (PX по бокам) — чтобы перекрёсток был сплошным
    const full = (r) => (r[2] >= r[3] ? { x: r[0], y: r[1] - PX, w: r[2], h: r[3] + PX * 2 } : { x: r[0] - PX, y: r[1], w: r[2] + PX * 2, h: r[3] });
    const rr = this.roadRects.map((r, i) => full((this.city.roads ?? [])[i]));
    for (let i = 0; i < rr.length; i += 1) {
      for (let j = i + 1; j < rr.length; j += 1) {
        const a = rr[i], b = rr[j];
        const x1 = Math.max(a.x, b.x);
        const y1 = Math.max(a.y, b.y);
        const x2 = Math.min(a.x + a.w, b.x + b.w);
        const y2 = Math.min(a.y + a.h, b.y + b.h);
        if (x2 > x1 && y2 > y1) {
          const px1 = x1, py1 = y1, pw = x2 - x1, ph = y2 - y1;
          this.groundFns.push((ctx) => Tex.tiled(ctx, T_ASPH, px1, py1, pw, ph));
        }
      }
    }
    // зебра — через горизонтальную дорогу по центру вертикальной
    const cxw = rv ? rv[0] + rv[2] * 0.5 : pl[0] + pl[2] * 0.5;
    this._crosswalk(cxw, 740, cxw, 850);
    this._label("⛲ ПЛОЩАДЬ", pl[0] + 30, pl[1] + 10, 20);
    this._bench(pl[0] + 40, pl[1] + 40);
    this._bench(pl[0] + pl[2] - 230, pl[1] + 40);
    const dd = this.city.district ?? {};
    this.districtRect = { x: dd.x ?? 1900, y: dd.y ?? 560, w: dd.w ?? 460, h: dd.h ?? 560 };
    this._label("🏠 " + String(dd.name ?? "Район"), this.districtRect.x + 120, this.districtRect.y + 10, 20);
    this._label("🌳 " + String(pk.label ?? "ПУСТЫРЬ"), (pk.x ?? 1650) + 200, (pk.y ?? 120) + 10, 20);
    this._bench(1750, 300);
    for (const b of this.city.buildings ?? []) this._building(b);
    for (const sh of this.city.houses ?? []) this._house(sh[0], sh[1], sh[2], sh[3]);
    for (const t of this.city.trees ?? []) this._tree(t[0], t[1]);
    for (const s of this.city.bus_stops ?? []) this._busStop(s);
    this._dropbox(2100, 950);
    this._dropbox(1340, 470);
    this._lampsRow(100, 720, 5, 460.0);
    this._lampsRow(1120, 100, 4, 340.0);
    this._car(700, 795, 0);
    this._car(1500, 795, 2);
    this._car(1185, 1150, 1);
    this._propMc(30, 14, 1450, 700, 4.0); // ящик
    this._propMc(35, 24, 1900, 860, 4.0); // барьер
    this._propMc(25, 14, 2290, 660, 4.0); // коробка у депо
    this._propMc(29, 14, 2150, 1010, 4.0); // коробка
    this._spawnNpcsCity();
    this._spawnAmbient();

    this.placePlayer(this.defaultSpawnCity());
    const notes = this.game.enterMap("city");
    for (const n of notes) this.ui.toast(n);
    this.ui.drainUnlocksToasts();
    this.game.spawnOverride = null;
  }

  defaultSpawnCity() {
    const s = this.city.spawn ?? [460, 930];
    return { x: s[0], y: s[1] };
  }

  buildInterior(loc) {
    this.mode = "interior";
    this.mapId = loc;
    this.conf = (this.game.D.interiors ?? {})[loc] ?? {};
    if (!this.conf.name) {
      this.conf = { name: loc, size: [1100, 700], obstacles: [], npc_spots: {}, props: [] };
    }
    const sz = this.conf.size ?? [1100, 700];
    this.worldSize = { w: sz[0], h: sz[1] };
    this.solids = [];
    this.interact = [];
    this.ylist = [];
    this.groundFns = [];
    this.buildingRects = [];
    this.districtRect = null;

    this.groundFns.push((ctx) => Tex.tiled(ctx, T_FLOOR, 0, 0, sz[0], sz[1]));
    this._wallsInterior(sz[0], sz[1]);
    this._label(String(this.conf.name ?? loc), 30, 16, 24);
    for (const o of this.conf.obstacles ?? []) this._furniture(o);
    for (const p of this.conf.props ?? []) this._prop(p);
    this._spawnNpcsInterior();

    const sp = this.spawnOverrideInterior(loc) ?? { x: 550, y: 600 };
    this.placePlayer(sp);
    const notes = this.game.enterMap(loc);
    for (const n of notes) this.ui.toast(n);
    this.ui.drainUnlocksToasts();
  }

  spawnOverrideInterior(loc) {
    const so = this.game.spawnOverride;
    if (so && so.map === loc) return so.pos;
    return null;
  }

  placePlayer(sp) {
    let so = this.game.spawnOverride;
    if (so && so.map === this.mapId) {
      this.player.x = so.pos.x;
      this.player.y = so.pos.y;
    } else {
      this.player.x = sp.x;
      this.player.y = sp.y;
    }
    this.game.spawnOverride = null;
    this.cam.x = this.player.x;
    this.cam.y = this.player.y;
    this._depenetrate();
  }

  // Выталкивание из коллизий после телепорта (аналог depenetration Godot).
  _depenetrate() {
    const p = this.player;
    const r = p.r;
    for (let iter = 0; iter < 4; iter += 1) {
      let moved = false;
      for (const s of this.solids) {
        const cx = Math.max(s.x, Math.min(p.x, s.x + s.w));
        const cy = Math.max(s.y, Math.min(p.y, s.y + s.h));
        const dx = p.x - cx, dy = p.y - cy;
        const d2 = dx * dx + dy * dy;
        if (d2 >= r * r) continue;
        if (d2 > 1e-9) {
          const d = Math.sqrt(d2);
          const push = (r - d) / d;
          p.x += dx * push;
          p.y += dy * push;
        } else {
          // центр внутри прямоугольника — выталкиваем к ближайшему ребру
          const left = p.x - s.x, right = s.x + s.w - p.x;
          const top = p.y - s.y, bottom = s.y + s.h - p.y;
          const m = Math.min(left, right, top, bottom);
          if (m === top) p.y = s.y - r;
          else if (m === bottom) p.y = s.y + s.h + r;
          else if (m === left) p.x = s.x - r;
          else p.x = s.x + s.w + r;
        }
        moved = true;
      }
      if (!moved) break;
    }
    this.cam.x = p.x;
    this.cam.y = p.y;
  }

  // ---------- элементы города ----------

  _walls(w, h) {
    this._solid(-40, -40, w + 80, 40);
    this._solid(-40, h, w + 80, 40);
    this._solid(-40, 0, 40, h);
    this._solid(w, 0, 40, h);
  }

  _wallsInterior(w, h) {
    const rects = [
      [-40, -40, w + 80, 40], [-40, h, w + 80, 40],
      [-40, 0, 40, h], [w, 0, 40, h],
    ];
    for (const r of rects) {
      this.groundFns.push((ctx) => Tex.tiled(ctx, T_WALLI, r[0], r[1], r[2], r[3]));
      this._solid(r[0], r[1], r[2], r[3]);
    }
  }

  _solid(x, y, w, h) {
    this.solids.push({ x, y, w, h });
  }

  _label(text, x, y, size) {
    this.ylist.push({ y, draw: (ctx) => {
      ctx.font = `${size}px system-ui, sans-serif`;
      ctx.textAlign = "left"; ctx.textBaseline = "alphabetic";
      ctx.fillStyle = "rgba(0,0,0,0.85)";
      ctx.fillText(text, x + 2, y + size + 2);
      ctx.fillStyle = "rgba(255,255,255,0.9)";
      ctx.fillText(text, x, y + size);
    } });
  }

  // Дорога: асфальт + жёлтая середина + тротуары по бокам.
  _road(x, y, w, h) {
    this.roadRects.push({ x, y, w, h });
    this.groundFns.push((ctx) => Tex.tiled(ctx, T_ASPH, x, y, w, h));
    if (w >= h) {
      const mid = y + h * 0.5 - PX * 0.5;
      this.groundFns.push((ctx) => Tex.tiled(ctx, T_YEL, x, mid, w, PX));
      this.groundFns.push((ctx) => Tex.tiled(ctx, T_SIDE, x, y - PX, w, PX));
      this.groundFns.push((ctx) => Tex.tiled(ctx, T_SIDE, x, y + h, w, PX));
    } else {
      const mid = x + w * 0.5 - PX * 0.5;
      this.groundFns.push((ctx) => Tex.tiled(ctx, T_YEL, mid, y, PX, h));
      this.groundFns.push((ctx) => Tex.tiled(ctx, T_SIDE, x - PX, y, PX, h));
      this.groundFns.push((ctx) => Tex.tiled(ctx, T_SIDE, x + w, y, PX, h));
    }
  }

  // Зебра между двумя точками (вертикальная полоса).
  _crosswalk(ax, ay, bx, by) {
    const x = (ax + bx) * 0.5 - PX * 0.5;
    const y0 = Math.min(ay, by);
    const y1 = Math.max(ay, by);
    let yv = y0;
    while (yv < y1) {
      const yy = yv;
      this.groundFns.push((ctx) => Tex.tiled(ctx, T_CROSS, x, yy, PX, PX));
      yv += PX;
    }
  }

  _building(b) {
    const r = { x: b.x, y: b.y, w: b.w, h: b.h };
    this.buildingRects.push(r);
    const st = STYLE[String(b.id ?? "")] ?? [227, 43, 30];
    const wallTile = st[0], roofTile = st[1], doorCol = st[2];
    this.ylist.push({ y: r.y - 40, draw: (ctx) => Tex.tiled(ctx, roofTile, r.x, r.y - 40, r.w, 64) });
    this.ylist.push({ y: r.y, draw: (ctx) => Tex.tiled(ctx, wallTile, r.x, r.y, r.w, r.h) });
    this._solid(r.x, r.y, r.w, r.h);
    this._label(`${b.icon ?? ""} ${b.sign ?? ""}`, r.x + 20, r.y - 44, 22);
    const d = b.door ?? [r.x + r.w * 0.5, r.y + r.h];
    this._door(d[0], d[1], String(b.id), `Войти: ${b.name ?? ""}`, doorCol);
  }

  _house(x, y, w, h) {
    // дома не стоят на дорогах (в data есть точка на дороге)
    for (const r of this.roadRects) {
      if (x + w > r.x - 10 && x < r.x + r.w + 10 && y + h > r.y - 10 && y < r.y + r.h + 10) return;
    }
    this.buildingRects.push({ x, y, w, h });
    // жилой вид: бежевый кирпич + красная крыша
    this.ylist.push({ y, draw: (ctx) => Tex.tiled(ctx, 231, x, y, w, h) });
    this._solid(x, y, w, h);
    this.ylist.push({ y: y - 30, draw: (ctx) => Tex.tiled(ctx, 39, x, y - 30, w, 48) });
  }

  _door(px, py, loc, label, dcol) {
    this.ylist.push({ y: py - 50, draw: (ctx) => Tex.drawMosaic(ctx, dcol, T_DOOR_ROW, 1, 1, px, py - 50, 4.0) });
    this.interact.push({ x: px, y: py, r: 55, kind: "door", loc, label });
  }

  _tree(x, y) {
    // деревья не растут внутри зданий и на дорогах (в data есть такие точки)
    for (const b of this.buildingRects) {
      if (x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h) return;
    }
    for (const r of this.roadRects) {
      if (x >= r.x - 20 && x <= r.x + r.w + 20 && y >= r.y - 20 && y <= r.y + r.h + 20) return;
    }
    const kinds = [31, 32, 33, 34, 35, 36];
    const col = kinds[Math.floor(this.rand() * kinds.length)];
    // полное дерево: 2 тайла (верх r10 + низ r11), основание у земли
    this.ylist.push({ y: y - 80, draw: (ctx) => Tex.drawMosaic(ctx, col, 10, 1, 2, x, y - 80, 5.0) });
  }

  _lampsRow(x, y, n, step) {
    for (let i = 0; i < n; i += 1) {
      const lx = x + i * step, ly = y - 40;
      this.ylist.push({ y: ly, draw: (ctx) => Tex.drawMosaic(ctx, 19, 13, 1, 1, lx, ly, 4.0) });
    }
  }

  _car(x, y, v) {
    const cells = [[31, 18], [33, 18], [31, 22], [33, 22]];
    const c = cells[v % cells.length];
    this.ylist.push({ y, draw: (ctx) => Tex.drawMosaic(ctx, c[0], c[1], 2, 2, x, y, 5.0) });
  }

  _bench(x, y) {
    // деревянная скамья/стол (рейки (35,23) выглядели как странные металлические балки)
    this.ylist.push({ y, draw: (ctx) => Tex.drawMosaic(ctx, 18, 15, 1, 1, x, y, 4.0) });
  }

  _propMc(col, row, x, y, sc) {
    this.ylist.push({ y, draw: (ctx) => Tex.drawMosaic(ctx, col, row, 1, 1, x, y, sc) });
  }

  _busStop(s) {
    const pos = s;
    let other = {};
    for (const o of this.city.bus_stops ?? []) {
      if (String(o.id) !== String(s.id)) other = o;
    }
    this._bench(pos.x + 0, pos.y - 30);
    this.interact.push({
      x: pos.x, y: pos.y, r: 60, kind: "bus",
      to_pos: { x: other.x ?? pos.x, y: (other.y ?? pos.y) + 40 },
    });
    this._label("🚌 " + String(s.label ?? "Остановка"), pos.x - 70, pos.y + 22, 15);
  }

  _dropbox(x, y) {
    this.ylist.push({ y: y - 20, draw: (ctx) => Tex.drawMosaic(ctx, 30, 14, 1, 1, x, y - 20, 4.0) });
    this.interact.push({ x, y, r: 55, kind: "mailbox" });
    this._label("Ящик", x - 24, y + 22, 15);
  }

  _furniture(o) {
    const r = { x: o.x, y: o.y, w: o.w, h: o.h };
    const idx = FURN[String(o.label ?? "")] ?? 546;
    this.ylist.push({ y: r.y, draw: (ctx) => Tex.tiled(ctx, idx, r.x, r.y, r.w, r.h) });
    this._solid(r.x, r.y, r.w, r.h);
  }

  _prop(p) {
    const pos = p;
    const kind = String(p.kind ?? "flavor");
    if (kind === "exit") {
      this.interact.push({ x: pos.x, y: pos.y, r: 60, kind: "exit", out: this._doorOut() });
      this._label(String(p.label ?? "Выход"), pos.x - 60, pos.y + 20, 15);
      return;
    }
    const meta = { x: pos.x, y: pos.y, r: 60, kind };
    if (kind === "flavor") { meta.label = String(p.label ?? ""); meta.text = String(p.text ?? "..."); }
    this.interact.push(meta);
    const y = pos.y - 16;
    this.ylist.push({ y, draw: (ctx) => {
      const t = Tex.mcBig(PROP_TILE[kind] ?? 543, PX);
      ctx.save(); ctx.imageSmoothingEnabled = false;
      ctx.drawImage(t, pos.x - PX / 2, y - PX / 2);
      const lbl = String(p.label ?? "");
      ctx.font = "15px system-ui, sans-serif";
      ctx.fillStyle = "rgba(0,0,0,0.85)"; ctx.fillText(lbl, pos.x - 60 + 2, pos.y + 20 + 15 + 2);
      ctx.fillStyle = "rgba(255,255,255,0.95)"; ctx.fillText(lbl, pos.x - 60, pos.y + 20 + 15);
      ctx.restore();
    } });
  }

  _doorOut() {
    for (const b of (this.game.D.city ?? {}).buildings ?? []) {
      if (String(b.id) === this.mapId) {
        const d = b.door ?? [400, 400];
        return { x: d[0], y: d[1] + 60 };
      }
    }
    return { x: 400, y: 400 };
  }

  _spawnNpcsCity() {
    const spots = this.city.npc_spots ?? {};
    for (const n of this.game.D.npcs?.npcs ?? []) {
      const post = this.game.npcWhere(String(n.id));
      if (!post.loc) continue;
      if (!(["city", "district"].includes(String(post.loc)))) continue;
      const sv = spots[String(n.id)] ?? [100, 100];
      let px = sv[0], py = sv[1];
      if (post.cx !== undefined) { px = post.cx; py = post.cy; }
      this._addNpc(String(n.id), px, py);
    }
  }

  _spawnAmbient() {
    for (const rule of this.city.ambient ?? []) {
      if (this.game.day < (rule.day_min ?? 1)) continue;
      if (rule.day_max && this.game.day > rule.day_max) continue;
      const count = rule.count ?? 1;
      for (let i = 0; i < count; i += 1) {
        const px = rule.x + (i % 3) * 55 - 55;
        const py = rule.y + Math.floor(i / 3) * 50;
        this._addAmbient(String(rule.emoji ?? "🧍"), String(rule.line ?? "..."), px, py);
      }
    }
  }

  _spawnNpcsInterior() {
    const spots = this.conf.npc_spots ?? {};
    for (const n of this.game.D.npcs?.npcs ?? []) {
      const post = this.game.npcWhere(String(n.id));
      if (!post.loc) continue;
      if (String(post.loc) !== this.mapId) continue;
      const s = spots[String(n.id)] ?? [550, 350];
      this._addNpc(String(n.id), s[0], s[1]);
    }
  }

  // Человек в мире: имя, зона взаимодействия (npc.gd).
  _addNpc(npcId, x, y) {
    const n = this.game.npcById(npcId);
    const tex = Tex.personTex(Tex.personIndex(npcId));
    const tag = String(n.name ?? "?");
    this.ylist.push({ y, draw: (ctx) => {
      this._drawPerson(ctx, tex, x, y - 34, 3.0);
      this._drawText(ctx, tag, x - 45, y - 84, 45, 90, 15, "center", "rgba(255,255,255,1)");
    } });
    this.interact.push({ x, y, r: 70, kind: "npc", npc: npcId, tag });
  }

  _addAmbient(emoji, line, x, y) {
    void emoji;
    const idx = Math.abs(this._hashStr(line)) % 6;
    const tex = Tex.ambientChar(idx);
    this.ylist.push({ y, draw: (ctx) => {
      this._drawPerson(ctx, tex, x, y - 32, 3.0);
      this._drawText(ctx, line, x - 115, y - 74, 230, 230, 14, "center", "rgba(255,242,204,1)");
    } });
  }

  _hashStr(s) {
    // аналог line.hash() Godot (не обязателен 1:1 — только детерминизм)
    let h = 0;
    for (let i = 0; i < s.length; i += 1) {
      h = (h * 31 + s.charCodeAt(i)) & 0x7fffffff;
    }
    return h;
  }

  _drawPerson(ctx, texCv, cx, cy, scale) {
    ctx.save();
    ctx.imageSmoothingEnabled = false;
    const w = 16 * scale, h = 24 * scale;
    ctx.drawImage(texCv, cx - w / 2, cy - h / 2, w, h);
    ctx.restore();
  }

  _drawText(ctx, text, x, y, width, minw, size, align, color) {
    void width; void minw;
    ctx.font = `${size}px system-ui, sans-serif`;
    ctx.textAlign = align;
    ctx.fillStyle = "rgba(0,0,0,0.88)";
    ctx.fillText(text, x + 1, y + size + 1);
    ctx.fillStyle = color;
    ctx.fillText(text, x, y + size);
  }

  // ================= логика (world_base) =================

  _checkZone() {
    if (!this.districtRect) return;
    const p = this.player;
    const inDistrict = p.x >= this.districtRect.x && p.x <= this.districtRect.x + this.districtRect.w
      && p.y >= this.districtRect.y && p.y <= this.districtRect.y + this.districtRect.h;
    const z = inDistrict ? "district" : "city";
    if (z !== this.game.currentLocation && (this.game.currentLocation === "city" || this.game.currentLocation === "district")) {
      this.game.currentLocation = z;
    }
  }

  // Продвижение времени при ходьбе/бездействии; при переходе ночи показать экран.
  _processTime(dt) {
    if (this.ui.blocksWorld()) {
      this.still = 0;
      return;
    }
    if (this.playerMoving()) {
      this.still = 0;
      this.idleWarned = false;
      const note = this.game.tickTime(dt * WALK_MIN_PER_SEC);
      this._afterAction(note);
      this._checkZone();
    } else {
      this.still += dt;
      let rate = IDLE_MIN_PER_SEC;
      if (this.still >= IDLE_LIMIT) {
        rate = 0.5;
        if (!this.idleWarned) {
          this.idleWarned = true;
          this.ui.toast("Прошло время… Стоять — тоже выбор.");
        }
      }
      const note2 = this.game.tickTime(dt * rate);
      this._afterAction(note2);
    }
  }

  _afterAction(note) {
    this.ui.drainUnlocksToasts();
    if (this.game.gameOver) {
      this.ui.showElection();
      return;
    }
    if (this.game.justSlept) {
      this.game.justSlept = false;
      this.ui.showNight(this.game.lastNight);
    } else if (note !== "") {
      this.ui.showNight(note);
    }
  }

  playerMoving() {
    const p = this.player;
    return p.vx * p.vx + p.vy * p.vy > 400; // velocity.length() > 20
  }

  // Физика игрока: WASD + джойстик, столкновения с AABB (move_and_slide упрощённый).
  _physics(dt) {
    const p = this.player;
    if (p.frozen || this.ui.blocksWorld()) {
      p.vx = 0; p.vy = 0;
      return;
    }
    let dx = 0, dy = 0;
    const k = this.keys;
    if (k.has("move_left")) dx -= 1;
    if (k.has("move_right")) dx += 1;
    if (k.has("move_up")) dy -= 1;
    if (k.has("move_down")) dy += 1;
    if (Math.hypot(dx, dy) < 0.1 && (Math.abs(this.joy.x) + Math.abs(this.joy.y)) > 0.1) {
      dx = this.joy.x; dy = this.joy.y;
      const len = Math.hypot(dx, dy);
      if (len > 1) { dx /= len; dy /= len; }
    }
    p.vx = dx * SPEED;
    p.vy = dy * SPEED;
    const stepX = p.vx * dt;
    const stepY = p.vy * dt;
    p.x = this._slide(p.x + stepX, p.y, true);
    p.y = this._slide(p.x, p.y + stepY, false);
    // лёгкое покачивание при ходьбе
    if (this.playerMoving()) {
      p.stepPhase += dt * 10.0;
      p.bounce = Math.abs(Math.sin(p.stepPhase)) * -4.0;
    } else {
      p.bounce = 0;
    }
  }

  // Раздельное скольжение: двигаем по одной оси, при столкновении — останавливаем.
  _slide(nx, ny, isXAxis) {
    const p = this.player;
    const r = p.r;
    for (const s of this.solids) {
      // расширенный AABB circle vs rect
      const cx = Math.max(s.x, Math.min(nx, s.x + s.w));
      const cy = Math.max(s.y, Math.min(ny, s.y + s.h));
      const ddx = nx - cx, ddy = ny - cy;
      if (ddx * ddx + ddy * ddy < r * r) {
        if (isXAxis) return p.x;
        return p.y;
      }
    }
    return isXAxis ? nx : ny;
  }

  // ================= взаимодействие =================

  findTarget() {
    if (this.ui.blocksWorld()) { this.target = null; return null; }
    let best = null;
    let bestD = Infinity;
    const p = this.player;
    for (const a of this.interact) {
      const d = Math.hypot(a.x - p.x, a.y - p.y);
      if (d < a.r + SENSOR_R && d < bestD) { bestD = d; best = a; }
    }
    this.target = best;
    return best;
  }

  promptFor(a) {
    switch (a.kind) {
      case "npc": {
        const n = this.game.npcById(String(a.npc));
        return `💬 Поговорить: ${n.name ?? "?"}`;
      }
      case "door": return `🚪 ${String(a.label ?? "?").startsWith("Войти:") ? String(a.label) : `Войти: ${a.label ?? "?"}`}`;
      case "exit": return "🚪 Выйти в город";
      case "printer": return this.game.isUnlocked("printing") ? "🖨 Печатать листовки (30 мин, 150€)" : "🖨 Принтер (пока молчит…)";
      case "paper": return this.game.paperUnread() ? "📰 Взять газету (новое!)" : "📰 Газета";
      case "bed": return "🛏 Спать до утра";
      case "board": return "📌 Стенд объявлений";
      case "flavor": return `❔ ${a.label ?? "Осмотреть"}`;
      case "bus": return "🚌 Автобус: 8 мин, 5€";
      case "mailbox": return "📮 Опустить листовки (массово)";
    }
    return "E";
  }

  boardText() {
    for (const p of this.conf?.props ?? []) {
      if (String(p.kind ?? "") === "info_board") {
        const topic = String(p.topic ?? "school");
        if (this.game.isUnlocked("agenda_view")) {
          return `Стенд: ${this.game.topicName(topic)} — ${this.game.agendaWord(this.game.agenda.get(topic) ?? 0)}`;
        }
        return `Стенд: объявления, жалобы. Кажется, людей волнует ${this.game.topicName(topic)}.`;
      }
    }
    return "Стенд объявлений.";
  }

  doInteract(a) {
    if (!a || this.ui.blocksWorld()) return;
    switch (a.kind) {
      case "npc": {
        if (this.game.unlockMechanic("talking")) this.ui.toast(this.game.mechToast("talking"));
        if (this.game.seenHint("talk")) this.ui.toast("Выбирай реплики — слова имеют цену и последствия.");
        this.ui.openDialog(String(a.npc));
        break;
      }
      case "door":
        this.gotoMap(String(a.loc), { x: 550, y: 600 });
        break;
      case "exit":
        this.gotoMap("city", a.out ?? { x: 400, y: 400 });
        break;
      case "printer":
        if (!this.game.isUnlocked("printing")) { this.ui.toast("Принтер молчит. Загляни позже."); return; }
        this.ui.toast(this.game.printLeaflets());
        this._afterAction("");
        break;
      case "paper":
        this.game.markPaperRead();
        this.ui.openPaper(this.game.pickupPaper());
        this._afterAction("");
        break;
      case "bed":
        this._afterAction(this.game.endDay());
        break;
      case "board":
        this.ui.toast(this.boardText());
        break;
      case "flavor":
        this.ui.toast(String(a.text ?? "..."));
        break;
      case "bus":
        this._rideBus(a);
        break;
      case "mailbox":
        if (!this.game.isUnlocked("campaigning")) { this.ui.toast("Сначала напечатай листовки в офисе."); return; }
        this.ui.toast(this.game.distribute("mass"));
        this._afterAction("");
        break;
    }
  }

  _rideBus(a) {
    if (this.game.money < 5) { this.ui.toast("Нужно 5€ на билет."); return; }
    this.game.money -= 5;
    const to = a.to_pos ?? { x: this.player.x, y: this.player.y };
    this.player.x = to.x; this.player.y = to.y;
    this._depenetrate();
    this.still = 0;
    this.ui.toast("🚌 Автобус (−5€, −8 мин).");
    this._afterAction(this.game.tickTime(8.0));
  }

  gotoMap(next, spawn) {
    // Фиксируем назначение ДО смены сцены: интерьер строится по currentLocation.
    this.game.currentLocation = next;
    if (!this.game.visited.includes(next)) this.game.visited.push(next);
    this.game.spawnOverride = { map: next, pos: spawn };
    if (next === "city") this.buildCity();
    else this.buildInterior(next);
  }

  wakeHome() {
    if (this.mapId === "office") {
      this.player.x = 220; this.player.y = 480;
      this._depenetrate();
    } else {
      this.gotoMap("office", { x: 220, y: 480 });
    }
  }

  // После loadGame: пересобрать карту по currentLocation (аналог show_city в старом UI).
  gameOverRelaunch() {
    const loc = this.game.currentLocation;
    if (loc === "city" || loc === "district") this.buildCity();
    else this.buildInterior(loc);
  }

  update(dt) {
    this.view.w = this.viewW();
    this.view.h = this.viewH();
    this._physics(dt);
    this._processTime(dt);
    this.findTarget();
    const t = this.target;
    if (t) this.ui.setPrompt(this.promptFor(t));
    else this.ui.setPrompt("");
    // камера плавно следует за игроком (position_smoothing_speed 6)
    const k = 1 - Math.exp(-6 * dt);
    this.cam.x += (this.player.x - this.cam.x) * k;
    this.cam.y += (this.player.y - this.cam.y) * k;
  }

  // ================= отрисовка =================

  render(ctx) {
    const vw = this.view.w, vh = this.view.h;
    // фон как RenderingServer.set_default_clear_color(0.05,0.07,0.05) — в экранных координатах
    ctx.fillStyle = "rgb(13,18,13)";
    ctx.fillRect(0, 0, vw, vh);
    ctx.imageSmoothingEnabled = false;
    const camX = Math.round(this.cam.x - vw / 2);
    const camY = Math.round(this.cam.y - vh / 2);
    ctx.save();
    ctx.translate(-camX, -camY);

    // земляной слой
    for (const fn of this.groundFns) fn(ctx);

    // y-sort: персонажи/здания/пропсы
    const p = this.player;
    // тень игрока (shade polygon)
    this.ylist.push({ y: p.y, draw: (c) => {
      c.fillStyle = "rgba(0,0,0,0.35)";
      c.beginPath();
      c.moveTo(p.x - 14, p.y + 10);
      c.lineTo(p.x + 14, p.y + 10);
      c.lineTo(p.x + 10, p.y + 16);
      c.lineTo(p.x - 10, p.y + 16);
      c.closePath();
      c.fill();
      const tex = Tex.personTex(0);
      this._drawPerson(c, tex, p.x, p.y - 34 + (p.bounce ?? 0), 3.0);
    } });

    const sorted = [...this.ylist].sort((a, b) => a.y - b.y);
    for (const it of sorted) it.draw(ctx);
    this.ylist.pop(); // убрать временный элемент игрока

    // тинт времени (world_base._update_tint)
    const h = this.game.minutes / 60;
    let c2 = null;
    if (h < 10.0) c2 = "rgba(255,242,217,0.06)";
    else if (h >= 16.0 && h < 18.0) c2 = "rgba(255,204,140,0.10)";
    else if (h >= 18.0) c2 = "rgba(217,153,191,0.16)";
    if (c2) {
      ctx.fillStyle = c2;
      ctx.fillRect(camX, camY, vw, vh);
    }
    ctx.restore();
  }
}
