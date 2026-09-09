# ldtk — LDtk level loader for Odin

Чистый, самодостаточный загрузчик проектов [LDtk](https://ldtk.io) (JSON-экспорт) на Odin.
Его можно встроить куда угодно: в движок, в конвертер, в тулзу, в чужой проект.

Зависимости — только `core:encoding/json` и `core:os`. Версия схемы-якоря: **LDtk JSON_SCHEMA 1.5.3**
(<https://ldtk.io/files/JSON_SCHEMA.json>).

---

## Содержание

- [Быстрый старт](#быстрый-старт)
- [Как подключить](#как-подключить)
- [Обзор API](#обзор-api)
- [Модель данных](#модель-данных)
  - [Что покрыто](#что-покрыто)
  - [Что сознательно не моделируется](#что-сознательно-не-моделируется)
- [Работа с полями сущностей](#работа-с-полями-сущностей)
- [Координаты](#координаты)
- [Память](#память)
- [Полный пример](#полный-пример)
- [Известные границы](#известные-границы)

---

## Быстрый старт

```odin
package main

import "core:fmt"
import ldtk "../ldtk"

main :: proc() {
	project, err, read_err := ldtk.load_file("assets/level.ldtk")
	if read_err != nil {
		fmt.eprintln("не удалось прочитать файл:", read_err)
		return
	}
	if err != nil {
		fmt.eprintln("не удалось распарсить:", err)
		return
	}
	defer ldtk.project_destroy(&project)

	fmt.println("проект:", project.header.app, project.json_version)

	levels := ldtk.levels_all(&project) // аллоцируется — удаляем сами
	defer delete(levels)
	fmt.println("уровней:", len(levels))
}
```

`load_file` возвращает три значения: проект, ошибку парсинга и ошибку чтения файла.
Ошибка чтения и ошибка парсинга — независимые каналы (`err == nil` + `read_err != nil` = файла нет).

---

## Как подключить

Odin резолвит относительные импорты **от папки entry-файла**, поэтому размещение имеет значение:

```
my_game/
├── main.odin          # package main, import ldtk "../ldtk"
└── vendor/
    └── ldtk/          # копия этого пакета
```

```odin
import ldtk "../vendor/ldtk"   // из main.odin, лежащего рядом с vendor/
```

Если папка с проектом содержит `ecs/` и `ldtk/` как подпапки, а entry (`package main`) лежит рядом —
импорт будет `import ldtk "ldtk"`. Главное правило: путь считается от директории того файла, который импортирует.

Пакет собирается обычным `odin build`/`odin run`; специальных тегов сборки нет.

---

## Обзор API

Всё определено в двух файлах: `schema.odin` (типизированная модель) и `ldtk.odin` (функции).

### Загрузка

| Функция | Что делает |
|---|---|
| `load(data: []byte) -> (Project, json.Unmarshal_Error)` | парсит проект из памяти |
| `load_file(path) -> (Project, json.Unmarshal_Error, os.Error)` | читает файл и парсит |

### Поиск (возвращают `Maybe(^T)`, `nil` если не найдено)

| Функция | Ищет |
|---|---|
| `layer_def_by_uid(project, uid)` / `layer_def_by_identifier(project, name)` | определение слоя |
| `entity_def_by_uid(project, uid)` | определение сущности |
| `tileset_by_uid(project, uid)` | тайлсет |
| `level_by_uid(project, uid)` / `level_by_identifier(project, name)` | уровень (root и миры) |
| `world_bounds(project)` | границы всех уровней в px (камера/куллинг) |
| `level_at_world_point(project, x, y)` | уровень, содержащий мировую точку |
| `entity_by_iid(project, iid)` | энтити-инстанс по project-wide iid |
| `layer_instance(level, name)` | слой-инстанс уровня |
| `levels_all(project) -> []Level` | все уровни (root + миры), **вызывающий удаляет** |

### Поля сущностей (`^Entity_Instance` + имя поля)

| Функция | Тип значения |
|---|---|
| `field(ei, name) -> Maybe(^Field_Instance)` | сам инстанс поля (сырой доступ) |
| `field_int` / `field_float` / `field_string` / `field_bool` | скаляры (`Maybe`) |
| `field_ints` / `field_floats` / `field_strings` | массивы (`[]i64`/`[]f64`/`[]string`, аллоцируются) |
| `field_entity_refs(ei, name) -> ([]Entity_Ref, bool)` | LDtk-ссылки (одиночные и массивы) |

Низкоуровневые `value_int/float/string/bool/array/object/ints/floats/strings` работают с сырым
`json.Value` — для экзотических типов полей (точки `F_Point`, кастомные конфиги и т.п.).

### Уровень

- `int_grid_cell(li, x, y) -> (value: int, ok: bool)` — клетка коллизий (0 = пусто, `ok=false` = вне границ).

### Память

- `project_destroy(&project)` — освобождает всё дерево проекта (см. [Память](#память)).

---

## Модель данных

Ключи JSON сопоставляются со структурой **точно** через теги `json:"..."`, поэтому имена полей
в коде — snake_case, а в файле они остаются оригинальными (`__cWid`, `defUid`, `bgColor`, ...).

### Что покрыто

- **Корень проекта** `Project` (+ `Header`): версия, настройки мира, флаги, дефолты грида и сущностей.
- **Определения** `Defs`:
  - `Layer_Def` — все четыре типа слоёв (`IntGrid` / `AutoLayer` / `Entities` / `Tiles`),
    включая `int_grid_values` (значения intGrid с идентификаторами и цветами);
  - `Entity_Def` — геометрия, pivot, tileRect, теги, `field_defs`;
  - `Tileset_Def` — размеры, `tile_grid_size`, `enum_tags`, путь к атласу (`rel_path`);
  - `Enum_Def` / `Enum_Value` — значения с цветами и тайлами;
  - `Field_Def` — типы полей (`Int`, `String`, `Bool`, `Float`, `LocalEnum.X`, `EntityRef`, ...);
- **Уровни** `Level`: размеры, фон, `layer_instances`, `__neighbours`;
- **Слои-инстансы** `Layer_Instance`: `int_grid_csv`, `auto_layer_tiles`/`grid_tiles` (`Tile`),
  `entity_instances`;
- **Сущности** `Entity_Instance` + **поля** `Field_Instance` (значение — гетерогенный `json.Value`).

Поддерживаются оба режима экспорта уровней: одиночный мир (уровни в `Project.levels`) и
multi-worlds (уровни внутри `World`). `levels_all` отдаёт и те, и другие.

### Что сознательно не моделируется

Редакторские и round-trip-данные не имеют структур и **безопасно пропускаются** парсером:

- правила авто-тайлов `autoRuleGroups` и группы intGrid (`intGridValuesGroups`);
- `realEditorValues`, editor-поля `Field_Def`, `defaultOverride`;
- `cachedPixelData`/`customData`/`savedSelections` тайлсетов, `embedAtlas`;
- `toc`, `customCommands`, legacy `intGrid` (sparse).

Это сделано намеренно: baked-тайлы уже лежат в файле, а правила нужны только редактору.
Пропуск неизвестных ключей — проверенное поведение `json.unmarshal`, поэтому модель остаётся
**forward-compatible**: файлы с новыми/чужими полями грузятся без ошибок, а смоделированные
части — без потерь.

---

## Работа с полями сущностей

LDtk хранит значения полей гетерогенно (`__value`). Пакет превращает их в удобные типы.

```odin
// Player-сущность с полями из редактора
player: ^ldtk.Entity_Instance = ... // из li.entity_instances

if life := ldtk.field_int(player, "life"); life != nil {
	// life.? == 100
}

// enum-поле: __value = id строкой, например "KeyA"
switch key := ldtk.field_string(&door, "lockedWith"); key {
case "KeyA": // дверь открывается ключом A
case nil:    // поле пустое (canBeNull)
}

// массивы
loot, ok := ldtk.field_ints(&chest, "loot")   // Array<Int>, null-элементы пропускаются
defer delete(loot)
dialog, ok := ldtk.field_strings(&npc, "lines") // MultiLines
defer delete(dialog)

// ссылки на другие сущности: Button.targets -> []Entity_Ref
refs, ok := ldtk.field_entity_refs(&button, "targets")
defer delete(refs)
for r in refs {
	// r.entity_iid, r.layer_iid, r.level_iid, r.world_iid
}
```

Правила типизации:

- `field_int` не сработает на строке, `field_string` — на числе: несоответствие даёт `nil`, не паникует.
- **enum-значения** — это строки-идентификаторы из LDtk (`"KeyA"`, `"Wood"`), а не числа.
- **`null` и отсутствующее поле неразличимы**: оба оставляют результат `nil` / нулевой массив.
  Для игровых данных этого достаточно; если нужен round-trip — значение считается «пустым».
- `EntityRef` бывает одиночным объектом или массивом; `field_entity_refs` обрабатывает оба случая
  и всегда возвращает срез.

---

## Координаты

Важно понимать, в какой системе координат лежат числа, чтобы не нарисовать уровень со сдвигом:

- **Сущности.** `px` (`[x, y]`) — позиция **якоря сущности** в пикселях уровня: левый верхний угол
  при pivot `(0,0)`, центр при pivot `(0.5, 0.5)` (обычное значение). Pivot лежит в `ei.pivot`.
  `__worldX`/`__worldY` — та же точка, но в мировых координатах (с учётом позиции уровня в мире).
  Формула: `world = level.world_x + entity.px.x` (или берите готовые `__worldX/Y`).
- **Тайлы.** `Tile.px` — левый верхний угол тайла, локально к уровню. У авто-слоёв со смещением
  (например «стены сверху» сдвинуты на −16 px) учитывайте `px_total_offset_x/y` слоя.
  `src` — координаты тайла в атласе тайлсета; `t` — id тайла внутри тайлсета; `f` — биты флипов.
- **intGrid.** `int_grid_cell(li, x, y)` индексируется по сетке: `csv[y * c_wid + x]`, 0 = пусто.
  Пиксельная координата клетки = `x * grid_size` (грид слоя — `li.grid_size`).
- Уровень в мире (GridVania): `level.world_x/y` — позиция уровня на мировой карте.

---

## Память

Всё, что возвращают `load`/`load_file` — строки, срезы, динамические массивы и содержимое
`json.Value` — аллоцируется переданным аллокатором (по умолчанию `context.allocator`).

**Два легальных режима владения:**

1. **`project_destroy(&project)`** — рекурсивно освобождает всё дерево (обязательно тем же
   аллокатором, которым грузили). После вызова проект использовать нельзя.
2. **Arena/temp-аллокатор** — грузите в `mem.Arena` или на кадровый темп и освобождайте всё разом;
   тогда `project_destroy` можно не вызывать.

```odin
import "core:mem"

arena: mem.Arena
mem.arena_init(&arena, allocator = context.allocator)
defer mem.arena_destroy(&arena)

project, err, _ := ldtk.load_file("level.ldtk", allocator = mem.arena_allocator(&arena))
// живёт, пока живёт арена
```

Результаты хелперов, которые аллоцируют, — на вашей совести (освобождать `delete`):

- `levels_all` → `[]Level`;
- `field_ints` / `field_floats` / `field_strings` / `field_entity_refs` и `value_*`-аналоги.

Входной буфер `data` после `load` можно удалять сразу: строки копируются при парсинге.
`load_file` так и делает сам.

---

## Полный пример

Иллюстрация типичного использования «из коробки»: грузим проект, находим уровень, читаем слои,
спавним сущности с полями и проверяем коллизии. Семантика игровых сущностей — ваша, пакет
отдаёт только данные.

```odin
package main

import "core:fmt"
import ldtk "../ldtk"

Entity :: struct { // игровой компонент (пример; у вас будет свой ECS-компонент)
	kind: string,   // "Player", "Door", ...
	x, y: int,      // мировая позиция (px), левый верхний угол
	life: int,
}

main :: proc() {
	project, err, read_err := ldtk.load_file("ldtk/example/example.ldtk")
	if read_err != nil { fmt.eprintln("read:", read_err); return }
	if err != nil        { fmt.eprintln("parse:", err);      return }
	defer ldtk.project_destroy(&project)

	level := ldtk.level_by_identifier(&project, "World_Level_0")
	if level == nil do return
	lv := level.?
	fmt.printf("уровень %s: %dx%d px, фон %s\n",
		lv.identifier, lv.px_wid, lv.px_hei, lv.bg_color)

	// --- сущности уровня (слой "Entities") ---
	entities_li := ldtk.layer_instance(lv, "Entities")
	if entities_li == nil do return
	entities := entities_li.?

	spawned: [dynamic]Entity
	defer delete(spawned)

	for &ei in entities.entity_instances {
		// px — позиция якоря по pivot: вычитаем половину размера при pivot (0.5, 0.5),
		// чтобы получить левый верхний угол
		anchor_x := ei.px[0] - int(ei.pivot[0] * f64(ei.width))
		anchor_y := ei.px[1] - int(ei.pivot[1] * f64(ei.height))

		ent := Entity {
			kind = ei.identifier,
			x    = lv.world_x + anchor_x,
			y    = lv.world_y + anchor_y,
		}
		if life := ldtk.field_int(&ei, "life"); life != nil {
			ent.life = int(life.?)
		}
		append(&spawned, ent)
		fmt.printf("  %s @ (%d, %d) defUid=%d fields=%d\n",
			ei.identifier, ent.x, ent.y, ei.def_uid, len(ei.field_instances))
	}

	// --- коллизии (IntGrid-слой) ---
	if grid_li := ldtk.layer_instance(lv, "Collisions"); grid_li != nil {
		if v, ok := ldtk.int_grid_cell(grid_li.?, 10, 7); ok {
			fmt.println("клетка (10,7) =", v, "(0 — проходимо)")
		}
	}

	// --- тайлы уровня (рендер: свой код поверх данных) ---
	if floor := ldtk.layer_instance(lv, "Default_floor"); floor != nil {
		fmt.printf("тайлов в полу: %d (auto) + %d (ручные)\n",
			len(floor.?.auto_layer_tiles), len(floor.?.grid_tiles))
	}
}
```

Обратите внимание: ни одной функции «спавна в ECS» в пакете нет — это осознанная граница.
`Entity_Instance` содержит всю геометрию (`px`, `width/height`, `pivot`, `tile`) и поля,
а как превратить их в компоненты вашего мира — решает интегратор (например, тонким слоем-мостом
поверх этого пакета).

---

## Известные границы

- **Версия-якорь 1.5.3.** Более новые версии LDtk добавляют поля; неизвестные ключи пропускаются,
  но новые *значимые* поля могут требовать добора в модель.
- **External levels** (`.ldtkl`): корень проекта с `external_levels: true` парсится, но данные
  уровней лежат в отдельных файлах и пока не загружаются. Для игр с одним уровнем в файле неактуально.
- **Round-trip** (изменить и сохранить проект) не реализован: модель намеренно не хранит
  редакторские данные, необходимые для потерь-свободного экспорта.
- Типы чисел: координаты/uid — `int`, смещения/масштабы — `f64`, значения полей LDtk — `i64/f64/string/bool`.

---

## Совместимость

Пакет не использует магию компилятора и собирается обычным `odin check/build`.
Проверялся на корпусе из официальных сэмплов LDtk 1.5.3 (15 файлов, включая multi-world
и `Test_file_for_API_showing_all_features`): все парсятся без ошибок.
