# Депутат: 7 дней до выборов — web-порт на Babylon.js

Порт «1 в 1» Godot-версии проекта (`../`): вся логика перенесена, рендер мира —
Canvas2D в `BABYLON.DynamicTexture` (top-down пиксель-арт), интерфейс — DOM-оверлей.

## Запуск

```bash
cd deputy-babylon
node serve.js 8137        # или: npx http-server -p 8137
# открыть http://localhost:8137
```

Тесты логики (порт tests/smoke_test.gd, 43 проверки):

```bash
node tests/smoke.js       # или: npm test
```

Babylon.js лежит локально (`assets/vendor/babylon.js`, UMD с jsDelivr) — интернет не нужен.

## Управление

- WASD / стрелки — идти (на сенсорных экранах — левый джойстик)
- E / Space — взаимодействие (можно кликать подсказку внизу)
- Q / Tab — телефон, Esc — меню

## Структура

| Файл | Источник (Godot) | Что |
|---|---|---|
| `src/game_state.js` | `scripts/game_state.gd` | вся игровая логика (сигналы → колбеки `onState/onDayStarted/onGameEnded`, сейвы → localStorage) |
| `src/tex.js` | `scripts/world/tex.gd` | тайлы из атласа modern-city, генерация пиксельных пешеходов |
| `src/world.js` | `scripts/world/{world_base,city,interior,player,npc}.gd` | сборка карт, физика, y-sort, взаимодействия, рендер |
| `src/ui.js` | `scripts/world/world_ui.gd` | HUD, тосты, диалог, телефон, ночь, выборы, меню |
| `src/main.js` | `scenes/*.tscn`, autoload | boot, Babylon-движок, джойстик |
| `data/`, `assets/` | копии тех же JSON и атласа | данные идентичны оригиналу |

## Отличия (осознанные)

- Сейвы в `localStorage` вместо `user://`.
- «🕹 Старый интерфейс» (Main.tscn) не портирован — в меню его пункт убран.
- Дев-параметры URL: `?map=office&pos=550,300` — сразу в интерьер.
