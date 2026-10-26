// Boot: данные → GameState → Babylon (DynamicTexture) → World → UI.

import { GameState } from "./game_state.js";
import { World } from "./world.js";
import { UI } from "./ui.js";
import { Editor } from "./editor.js";
import { loadAtlas, clearTexCache } from "./tex.js";

const DATA_FILES = ["locations", "topics", "infos", "npcs", "dialogues", "promises", "travel", "events", "newspaper", "city", "interiors"];

// DEV: ошибки видимы на скриншотах без консоли.
window.addEventListener("error", (e) => {
  document.getElementById("hud-obj").textContent = `⚠ ${e.message} @ ${e.filename?.split("/").pop()}:${e.lineno}`;
});
window.addEventListener("unhandledrejection", (e) => {
  document.getElementById("hud-obj").textContent = `⚠ ${e.reason}`;
});

async function loadData() {
  const D = {};
  await Promise.all(DATA_FILES.map(async (f) => {
    const r = await fetch(`data/${f}.json`, { cache: "no-store" });
    D[f] = r.ok ? await r.json() : {};
  }));
  // Раскладка карты из редактора (если сохраняли)
  try {
    const r = await fetch("data/city_layout.json", { cache: "no-store" });
    if (r.ok) D.city_layout = await r.json();
  } catch {
    // файла ещё нет — не страшно
  }
  return D;
}

const canvas = document.getElementById("scene");
const engine = new BABYLON.Engine(canvas, true, { preserveDrawingBuffer: true, stencil: false });
const scene = new BABYLON.Scene(engine);
scene.clearColor = new BABYLON.Color4(0.05, 0.07, 0.05, 1);
const camera = new BABYLON.FreeCamera("cam", new BABYLON.Vector3(0, 0, -10), scene);
camera.mode = BABYLON.Camera.ORTHOGRAPHIC_CAMERA;
camera.orthoLeft = -1; camera.orthoRight = 1;
camera.orthoTop = 1; camera.orthoBottom = -1;
camera.setTarget(BABYLON.Vector3.Zero());

const plane = BABYLON.MeshBuilder.CreatePlane("screen", { width: 2, height: 2 }, scene);
const mat = new BABYLON.StandardMaterial("mat", scene);
mat.emissiveTexture = null;
mat.diffuseColor = new BABYLON.Color3(1, 1, 1);
mat.specularColor = new BABYLON.Color3(0, 0, 0);
mat.backFaceCulling = false;
plane.material = mat;

let dynTex = null;
let ctx = null;

function makeDynTex(w, h) {
  dynTex = new BABYLON.DynamicTexture("world", { width: w, height: h }, scene, false);
  mat.emissiveTexture = dynTex;
  ctx = dynTex.getContext();
  clearTexCache();
  return ctx;
}

async function main() {
  const D = await loadData();
  await loadAtlas();
  const game = new GameState(D);
  const world = new World(game, null, canvas);
  const ui = new UI(game, world);
  world.ui = ui;

  function fit() {
    const w = canvas.clientWidth || window.innerWidth;
    const h = canvas.clientHeight || window.innerHeight;
    world.view.w = w; world.view.h = h;
    makeDynTex(w, h);
  }
  fit();
  window.addEventListener("resize", () => engine.resize());

  ui.init();
  world.attachInput();

  // Виртуальный джойстик (joystick.gd → touch): тяни левый круг — идти.
  const stick = document.getElementById("stick");
  const knob = document.getElementById("stick-knob");
  if (window.matchMedia("(pointer: coarse)").matches) stick.classList.remove("hidden");
  let stickId = null;
  const stickSet = (e) => {
    const r = stick.getBoundingClientRect();
    let dx = (e.clientX - (r.left + r.width / 2)) / (r.width / 2);
    let dy = (e.clientY - (r.top + r.height / 2)) / (r.height / 2);
    const len = Math.hypot(dx, dy);
    if (len > 1) { dx /= len; dy /= len; }
    world.joy.x = dx; world.joy.y = dy;
    knob.style.transform = `translate(calc(-50% + ${dx * 70}px), calc(-50% + ${dy * 70}px))`;
  };
  stick.addEventListener("pointerdown", (e) => {
    stickId = e.pointerId;
    stick.setPointerCapture(e.pointerId);
    stickSet(e);
  });
  stick.addEventListener("pointermove", (e) => {
    if (e.pointerId === stickId) stickSet(e);
  });
  const stickEnd = (e) => {
    if (e.pointerId !== stickId) return;
    stickId = null;
    world.joy.x = 0; world.joy.y = 0;
    knob.style.transform = "translate(-50%, -50%)";
  };
  stick.addEventListener("pointerup", stickEnd);
  stick.addEventListener("pointercancel", stickEnd);

  // DEV/скриншоты: ?map=office&pos=550,600 — сразу в нужную карту.
  const qs = new URLSearchParams(window.location.search);
  const qmap = qs.get("map");
  const qpos = qs.get("pos");
  if (qpos) {
    const [px, py] = qpos.split(",").map(Number);
    game.spawnOverride = { map: qmap ?? "city", pos: { x: px, y: py } };
  }
  if (qmap && qmap !== "city") world.buildInterior(qmap);
  else world.buildCity();

  // Редактор карты (после постройки карты): F2 или ?edit=1
  const editor = new Editor(world);
  if (qs.get("edit") === "1") editor.setActive(true);

  // Подсказка при входе (world_base._intro_hints).
  if (game.seenHint("move")) {
    if (window.matchMedia("(pointer: coarse)").matches) {
      ui.toast("Тяни левый круг — идти. Подходи к людям.");
    } else {
      ui.toast("WASD — идти, E — говорить. Найди свой офис.");
    }
  }

  engine.runRenderLoop(() => {
    const w = canvas.clientWidth || window.innerWidth;
    const h = canvas.clientHeight || window.innerHeight;
    if (!dynTex || dynTex.getSize().width !== w || dynTex.getSize().height !== h) fit();
    const dt = Math.min(engine.getDeltaTime() / 1000, 0.1);
    world.update(dt);
    world.render(ctx);
    dynTex.update(true);
    scene.render();
  });
}

main();
