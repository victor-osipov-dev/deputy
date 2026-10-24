// Смоук-тест игровой логики — порт tests/smoke_test.gd.
// Запуск: node tests/smoke.js (или npm test). Проверяет ядро game_state.js.

import { GameState } from "../src/game_state.js";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const DATA_FILES = ["locations", "topics", "infos", "npcs", "dialogues", "promises", "travel", "events", "newspaper"];
const D = {};
for (const f of DATA_FILES) D[f] = JSON.parse(readFileSync(join(here, "../data", `${f}.json`), "utf8"));

const results = [];
const check = (name, cond) => results.push((cond ? "PASS " : "FAIL ") + name);

const gs = new GameState(D);
gs.resetRun();

// --- база (ядро) ---
check("старт день=1", gs.day === 1);
check("старт деньги=3500", gs.money === 3500);
check("повестка 5 тем", gs.agenda.size === 5);
check("механики закрыты", !gs.isUnlocked("notebook") && !gs.isUnlocked("printing"));
check("цель 1: найти офис", String(gs.currentObjective().title ?? "") === "Найди свой офис");
gs.enterMap("office");
check("офис посещён", gs.visited.includes("office"));
check("цель 2: поговорить", String(gs.currentObjective().title ?? "") === "Поговори с жителями");

// --- диалог с Милой ---
const dass = gs.dialogueById("dlg_assistant");
gs.applyDialogue("assistant", dass, dass.options[0]);
check("разговор открыл talking", gs.isUnlocked("talking"));
check("инфа от Милы подтверждена (1.0)", String(gs.infoState.assistant_brief ?? "") === "confirmed");

// --- слухи: баба Валя -> врач ---
const dpat = gs.dialogueById("dlg_patient");
gs.applyDialogue("patient_granny", dpat, dpat.options[0]);
check("слух записан", String(gs.infoState.hospital_queues ?? "") === "rumor");
check("блокнот открыт (2 инфо)", gs.isUnlocked("notebook"));
const ddoc = gs.dialogueById("dlg_doctor");
gs.applyDialogue("doctor_elena", ddoc, ddoc.options[0]);
check("второй источник подтвердил", String(gs.infoState.hospital_queues ?? "") === "confirmed");
check("журнал-блокнот группирует", gs.journalNotebook().includes("БЛОКНОТ"));

// --- rel-гейт: журналист закрыт, потом открыт ---
const dj = gs.dialogueById("dlg_journalist");
check("гейт Иры держит", gs.relGate(dj.options[0], "journalist") !== "");
gs.applyDialogue("journalist", dj, dj.options[1]);
gs.applyDialogue("journalist", dj, dj.options[1]);
check("гейт Иры открыт при rel>=2", gs.relGate(dj.options[0], "journalist") === "");

// --- увидел опции, но ушёл: телефон уже знает ---
const peek = gs.dialogueById("dlg_anna");
const notes = gs.noteDialogueShown(peek);
check("увиденное открыто без выбора", gs.unlockedPromises.includes("p_school_teachers"));
check("без выбора обещаний нет", gs.activePromises().length === 0);
check("заметка об узнанном", notes.length > 0);
// --- Анна: обещание прямо из диалога ---
const dlg = gs.dialogueById("dlg_anna");
let opt = {};
for (const o of dlg.options ?? []) {
  if (String(o.creates_promise ?? "") === "p_school_teachers") opt = o;
}
check("опция-создатель найдена", !!opt.creates_promise);
gs.applyDialogue("teacher_anna", dlg, opt);
check("обещание создано диалогом", gs.activePromises().length === 1);
check("механика обещаний открыта", gs.isUnlocked("promises"));
const dup = gs.makePromise("p_school_teachers");
check("дубликат запрещён", dup.includes("уже активно"));
const ff = gs.fulfillPromise(gs.activePromises()[0].uid);
check("без Кольцова отказ", ff.includes("Кольцова"));

// --- напоминание NPC ---
gs.day = 3;
const rem = gs.reminderFor("teacher_anna");
check("Анна напоминает про учителей", String(rem.template ?? "") === "p_school_teachers");
gs.day = 1;

// --- посты NPC ---
gs.minutes = 10 * 60;
gs.day = 1;
check("Анна в школе утром", String(gs.npcWhere("teacher_anna").loc ?? "") === "school");
gs.minutes = Math.floor(16.5 * 60);
check("Анны нет в 16:30 (перерыв)", Object.keys(gs.npcWhere("teacher_anna")).length === 0);
gs.minutes = 18 * 60;
check("Анна вечером в районе", String(gs.npcWhere("teacher_anna").loc ?? "") === "district");
gs.day = 4;
gs.minutes = 14 * 60;
check("Ира у школы днём 4+", String(gs.npcWhere("journalist").loc ?? "") === "city");
gs.day = 1;
gs.minutes = 8 * 60;

// --- газета подтверждает слухи ---
gs.day = 2;
check("газета дня 2", String(gs.todayPaper().topic ?? "") === "hospital");
const pt = gs.pickupPaper();
check("подбор газеты", pt.includes("Очереди") || pt.length > 20);
gs.day = 1;

// --- листовки с районным бонусом ---
gs.currentLocation = "office";
gs.minutes = 8 * 60;
gs.money = 3500;
gs.printLeaflets();
check("печать открыла агитацию", gs.isUnlocked("campaigning"));
gs.makePromise("p_roads_light");
gs.currentLocation = "city"; // дом дорог — улицы города
gs.distribute("hand");
let mem = 50;
for (const p of gs.promises) {
  if (p.template === "p_roads_light") mem = p.memory ?? 50;
}
check("домашний бонус памяти", mem >= 85);
let uidLight = "";
for (const p of gs.activePromises()) {
  if (p.template === "p_roads_light") uidLight = p.uid;
}
const moneyBefore = gs.money;
check("выполнение освещения", gs.fulfillPromise(uidLight).startsWith("✅"));
check("деньги списаны 400", gs.money === moneyBefore - 400);

// --- предсказание ---
gs.day = 1;
check("школа предсказана (подтверждено до дня 4)", gs.predictedTopics().includes("school"));

// --- сейв/лоад нового состояния ---
check("сейв ок", gs.saveGame().includes("Сохранено"));
gs.infoState = {};
gs.loadGame();
check("лоад вернул слухи", String(gs.infoState.hospital_queues ?? "") === "confirmed");
check("лоад вернул открытия", gs.isUnlocked("campaigning"));

// --- выборы: дешёвый спидран проигрывает ---
const gw = new GameState(D);
gw.resetRun();
gw.makePromiseSilent("p_roads_light");
gw.makePromiseSilent("p_meeting");
for (const p of gw.promises) p.status = "completed";
gw.money = 9999;
gw.day = 7;
gw.minutes = 19 * 60;
gw.endDay();
check("выборы кончились", gw.gameOver);
check("2 дешёвых НЕ дают победу", !gw.election.win);
check("текст без формулы", !gw.electionText().includes("45+"));

// --- выборы: значимая кампания выигрывает ---
const gv = new GameState(D);
gv.resetRun();
gv.flags.kol_support = true;
gv.makePromiseSilent("p_school_teachers");
gv.makePromiseSilent("p_transport_buses");
gv.makePromiseSilent("p_school_repair");
for (const p of gv.promises) {
  p.status = "completed";
  p.memory = 80;
}
gv.day = 7;
gv.minutes = 19 * 60;
gv.endDay();
check("сильная кампания побеждает", !!gv.election.win);
check("темы решены", (gv.election.resolved ?? []).includes("school"));

for (const line of results) console.log(line);
const bad = results.filter((l) => l.startsWith("FAIL")).length;
console.log(`ИТОГ: ${results.length - bad}/${results.length} passed`);
if (bad > 0) process.exit(1);
