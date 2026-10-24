// Tex — порт scripts/world/tex.gd (Godot) на Canvas2D.
// Атлас Kenney Roguelike Modern City (CC0) + генерация пиксельных пешеходов кодом.

export const MC_COLS = 37;
export const MC_PITCH = 17;
export const PX = 80; // размер сетки мира

let atlasImg = null;
let atlasCv = null;
const _cache = new Map();

export async function loadAtlas(url = "assets/mc_atlas.png") {
  atlasImg = await new Promise((res, rej) => {
    const img = new Image();
    img.onload = () => res(img);
    img.onerror = rej;
    img.src = url;
  });
  atlasCv = document.createElement("canvas");
  atlasCv.width = atlasImg.width;
  atlasCv.height = atlasImg.height;
  atlasCv.getContext("2d").drawImage(atlasImg, 0, 0);
}

// Один тайл modern-city по индексу (row*37+col), увеличенный до px пикселей.
export function mcBig(i, px = PX) {
  const k = `mcb${i}x${px}`;
  if (_cache.has(k)) return _cache.get(k);
  const col = i % MC_COLS;
  const row = Math.floor(i / MC_COLS);
  const cv = document.createElement("canvas");
  cv.width = px; cv.height = px;
  const c = cv.getContext("2d");
  c.imageSmoothingEnabled = false;
  c.drawImage(atlasCv, col * MC_PITCH, row * MC_PITCH, 16, 16, 0, 0, px, px);
  _cache.set(k, cv);
  return cv;
}

// Заливка прямоугольника тайлом (земля, дороги, стены, полы). Аналог Tex.tiled().
export function tiled(ctx, i, x, y, w, h, px = PX) {
  if (w <= 0 || h <= 0) return;
  const t = mcBig(i, px);
  const key = `pat${i}x${px}`;
  let pat = _cache.get(key);
  if (!pat) {
    pat = ctx.createPattern(t, "repeat");
    _cache.set(key, pat);
  }
  ctx.save();
  ctx.translate(x, y);
  ctx.fillStyle = pat;
  ctx.fillRect(0, 0, w, h);
  ctx.restore();
}

// Сброс кэша (при пересоздании DynamicTexture новый контекст).
export function clearTexCache() {
  for (const k of Array.from(_cache.keys())) {
    if (String(k).startsWith("pat")) _cache.delete(k);
  }
}

// Мозаика из атласа: col,row — левый верхний тайл, w,h — размер в тайлах.
// Тайлы сшиваются вплотную (щель атласа в 1px не рисуем) — машины/деревья цельные.
export function drawMosaic(ctx, col, row, w, h, cx, cy, scale) {
  ctx.save();
  ctx.imageSmoothingEnabled = false;
  const ox = cx - (w * 16 * scale) / 2;
  const oy = cy - (h * 16 * scale) / 2;
  for (let ty = 0; ty < h; ty += 1) {
    for (let tx = 0; tx < w; tx += 1) {
      ctx.drawImage(atlasCv, (col + tx) * MC_PITCH, (row + ty) * MC_PITCH, 16, 16,
        ox + tx * 16 * scale, oy + ty * 16 * scale, 16 * scale, 16 * scale);
    }
  }
  ctx.restore();
}

// пиксельный пешеход: [цвет волос, цвет пиджака/платья, цвет брюк]
const P_PAL = [
  [[71, 48, 31], [41, 51, 82], [26, 26, 36]],       // игрок: депутат
  [[217, 179, 102], [153, 158, 168], [64, 69, 77]], // помощник
  [[51, 38, 26], [51, 115, 115], [51, 61, 71]],     // учительница
  [[179, 179, 179], [115, 51, 61], [38, 38, 46]],   // директор
  [[31, 26, 26], [51, 77, 56], [26, 26, 26]],       // чиновник
  [[153, 115, 77], [89, 64, 115], [38, 38, 51]],    // коллега
  [[26, 26, 31], [64, 89, 140], [31, 31, 41]],      // журналист
  [[89, 61, 36], [235, 235, 235], [89, 102, 115]],  // врач
  [[217, 217, 217], [191, 128, 140], [128, 89, 102]],// бабушка
  [[51, 38, 26], [204, 115, 38], [51, 51, 64]],     // водитель
  [[26, 20, 20], [128, 89, 51], [77, 77, 87]],      // строитель
  [[179, 77, 38], [77, 128, 77], [51, 51, 61]],     // активист
];

export function personIndex(npcId) {
  switch (npcId) {
    case "player": return 0;
    case "assistant": return 1;
    case "teacher_anna": return 2;
    case "principal": return 3;
    case "official": return 4;
    case "deputy_kol": return 5;
    case "journalist": return 6;
    case "doctor_elena": return 7;
    case "patient_granny": return 8;
    case "driver_sergey": return 9;
    case "builder": return 10;
    case "activist": return 11;
    default: return 4;
  }
}

const _people = [];

// Спрайт-канва пешехода 16x24 по индексу (порт _build_people/_one_person).
export function personTex(i) {
  if (_people.length === 0) buildPeople();
  return _people[Math.abs(i) % _people.length];
}

function buildPeople() {
  for (const p of P_PAL) {
    const cv = document.createElement("canvas");
    cv.width = 16; cv.height = 24;
    const c = cv.getContext("2d");
    const img = c.createImageData(16, 24);
    onePerson(img, p);
    c.putImageData(img, 0, 0);
    _people.push(cv);
  }
}

function setPx(img, x, y, r, g, b, a = 255) {
  if (x < 0 || x >= 16 || y < 0 || y >= 24) return;
  const o = (y * 16 + x) * 4;
  img.data[o] = r; img.data[o + 1] = g; img.data[o + 2] = b; img.data[o + 3] = a;
}

function onePerson(img, p) {
  const [hair, suit, pants] = p;
  const skin = [235, 199, 163];
  const shirt = [255, 255, 255];
  const dark = [33, 31, 31];
  const eye = [20, 18, 18];
  // волосы
  for (let y = 0; y < 3; y += 1) for (let x = 4; x < 12; x += 1) setPx(img, x, y, ...hair);
  // лицо
  for (let y = 3; y < 8; y += 1) for (let x = 4; x < 12; x += 1) setPx(img, x, y, ...skin);
  for (let y = 3; y < 5; y += 1) { setPx(img, 3, y, ...hair); setPx(img, 12, y, ...hair); }
  setPx(img, 6, 5, ...eye);
  setPx(img, 9, 5, ...eye);
  // пиджак
  for (let y = 8; y < 17; y += 1) for (let x = 3; x < 13; x += 1) setPx(img, x, y, ...suit);
  for (let x = 7; x < 9; x += 1) setPx(img, x, 8, ...shirt);
  setPx(img, 3, 16, ...skin);
  setPx(img, 12, 16, ...skin);
  // штанины
  for (let y = 17; y < 22; y += 1) {
    for (let x = 4; x < 7; x += 1) setPx(img, x, y, ...pants);
    for (let x = 9; x < 12; x += 1) setPx(img, x, y, ...pants);
  }
  // обувь
  for (let x = 3; x < 7; x += 1) setPx(img, x, 22, ...dark);
  for (let x = 9; x < 13; x += 1) setPx(img, x, 22, ...dark);
}

// Случайный прохожий для толпы.
export function ambientChar(i) {
  const pool = [11, 1, 9, 3, 6, 10];
  return personTex(pool[((i % pool.length) + pool.length) % pool.length]);
}

// Конвертация Godot Color(0..1 floats) → css строка.
export function col(r, g, b, a = 1) {
  const c = (v) => Math.round(Math.min(1, Math.max(0, v)) * 255);
  return `rgba(${c(r)},${c(g)},${c(b)},${a})`;
}
