# OGame 
Маленький каркас для игр: **собственный ECS** + **главный цикл на raylib**.

## Структура репозитория

| Путь        | Что это                                                             |
|-------------|---------------------------------------------------------------------|
| `game.odin` | сам каркас `ogame`: `Game`, системы, `Ctx`, главный цикл `run`      |
| `ecs/`      | пакет `ecs` — компоненты, сущности, запросы, отложенное уничтожение |
| `example/`  | рабочая демо-игра (мини-шутер) — лучший способ начать               |
| `ldtk/`     | независимый загрузчик уровней LDtk (см. `ldtk/README.md`)           |

---

## Минимальная игра

```odin
package main

import g "../"        // каркас ogame
import ecs "../ecs"   // ECS

init :: proc(ctx: ^g.Ctx) {
	player := ecs.entity_new(ctx.world)
	ecs.add_component(ctx.world, player, Pos{10, 10})
}

main :: proc() {
	world := ecs.world_new()

	game: g.Game
	game.settings.window = {title = "game", size = {1280, 720}}
	game.init = init
	game.update = { /* UpdateSystem'ы */ }
	game.render = { /* RenderSystem'ы */ }

	g.run(&game, &world)
	ecs.world_destroy(&world)
}
```

Запуск демо из корня репозитория:

```
odin run example
```

---

## Жизненный цикл

Порядок исполнения в `run` жёстко определён:

```
main:
  context.allocator      = обычный (heap, по умолчанию) — мир и долгоживущее
  context.temp_allocator = vmem-арена (по желанию) — кадровое, сбрасывается каждый кадр
  world := ecs.world_new(context.allocator)
  game: g.Game { init, cleanup, update, render }

run(&game, &world):
  rl.InitWindow / InitAudioDevice          (defer: CloseWindow)
  g.init(ctx)                              ← создание игровых данных
  build query-таблиц всех систем (1 раз)
  loop, пока окно открыто:
      update-системы (delta = GetFrameTime)
      ecs.cmds_flush                       ← применяет отложенные уничтожения
      render-системы (внутри BeginDrawing)
  cleanup-системы                          ← окно и мир ещё живы
  run освобождает СВОЁ: query-таблицы, буфер команд
  (defers закрывают окно и аудио)

после run:
  ecs.world_destroy(&world)                ← main освобождает мир
```

### Кто что чистит

- **Игра (user)** — в `init` создаёт, в `cleanup` освобождает **свои** данные: текстуры,
  звуки, строки/слайсы внутри компонентов. Cleanup-системы выполняются после главного цикла,
  пока ECS и raylib ещё доступны, — можно читать компоненты и выгружать ресурсы.
- **`run` (каркас)** — сам освобождает то, что сам аллоцировал: query-таблицы систем
  (`query_table_destroy`) и буфер отложенных команд.
- **`main` (владелец мира)** — вызывает `ecs.world_destroy(&world)` после `run`.

### Память: две зоны

Рекомендуемая схема (так сделано в `example/main.odin`) — разделить долгоживущее и кадровое:

- **`context.allocator` — обычный heap.** Здесь живут мир (`ecs.world_new`) и всё, что живёт
  дольше кадра: пулы компонентов растут тут же. Поэтому `ecs.world_destroy(&world)` **обязателен**.
- **`context.temp_allocator` — vmem-арена.** Здесь живёт всё, что нужно только внутри кадра:
  `run` вызывает `free_all(context.temp_allocator)` каждый кадр, так что арена сбрасывается
  сама. В примере: `context.temp_allocator = vmem.arena_allocator(&arena)`.

Кадровые аллокации всегда делайте **явно** на `context.temp_allocator` (или в стек-буфер),
а не «молча» на контексте: `fmt.tprintf/caprintf` по умолчанию аллоцируют через
`context.allocator` (heap) и будут копить мусор каждый кадр. Пример — `ui.odin` (стек-буфер
`fmt.bprintf`).

При этом весь каркас остаётся аллокатор-нейтральным:

- `[dynamic]`/`map` помнят свой аллокатор в заголовке — `delete()` корректен всегда;
- каждый пул компонентов помнит аллокатор **своего** создания — `world_destroy` ничего не угадывает;
- если всё же посадить мир на арену, delete/free станут no-op, а реальное освобождение
  сделает `arena_destroy` — `world_destroy` можно и не звать; на heap он обязателен
  (проверено: ноль утечек под tracking-аллокатором).

Ограничение (осознанное): компоненты копируются в пул байт-в-байт. Если компонент содержит
строку или слайс — копируется заголовок, владение остаётся у игры: такие данные игра
освобождает сама в cleanup (или живёт на арене вечно).

---

## Системы

Система — это процедура над запросом. Два вида:

```odin
UpdateSystem :: struct {
	name:   string,
	types:  []typeid,           // какие компоненты нужны (запрос системы)
	reads:  []ecs.Query_Def,    // именованные дополнительные запросы (кешируются 1 раз)
	update: proc(ctx: ^g.Ctx, q: ^ecs.Query, delta: f32),
}

RenderSystem :: struct {
	//...
	render: proc(ctx: ^g.Ctx, q: ^ecs.Query),
}
```

Внутри системы:

```odin
player_update :: proc(ctx: ^g.Ctx, q: ^ecs.Query, delta: f32) {
	// первый подходящий (или перебор всех через query_next)
	player, ok := ecs.query_first(q).?
	if !ok do return

	pos := ecs.query_get(q, player, comp.Pos).?
	pos.x += 100 * delta
}
```

`types = {}` допустимо — система вызывается каждый кадр, но запрос пуст (удобно для
input/background).

### Чтение «чужих» данных: `reads` + `ctx_query`

Если системе нужны данные, которых нет в её собственном запросе (например, UI читает игрока,
пуля — врагов), объяви их в `reads` — каркас построит эти запросы **один раз** до цикла:

```odin
{
	name = "ui",
	types = {},
	reads = { { name = "player", types = {comp.TPlayer, comp.Pos} } },
	render = ui_render,
},
```

```odin
ui_render :: proc(ctx: ^g.Ctx, q: ^ecs.Query) {
	pq := g.ctx_query(ctx, "player").?  // именованный read-запрос
	if player, ok := ecs.query_first(&pq).?; ok {
		pos := ecs.query_get(&pq, player, comp.Pos).?
		// ...
	}
}
```

---

## ECS: как описывать сущности

Компоненты — обычные типы. Рекомендации из `example/components/`:

```odin
// данные-компоненты — distinct, чтобы не путать типы
Pos   :: distinct [2]f32
Speed :: distinct f32

// теги — нуль-размерные структуры (компонент-маркер без данных)
TPlayer :: struct {}

// поведение с данными
Weapon :: struct { mag: int, fire_rate: f32, reloading: bool }
```

Основной API:

| Процедура                                              | Действие                                    |
|--------------------------------------------------------|---------------------------------------------|
| `ecs.world_new(allocator)`, `ecs.world_destroy(w)`     | создать/освободить мир                      |
| `ecs.entity_new(w)` / `ecs.destroy_entity(w, e)`       | сущности (вне игровой фазы)                 |
| `ecs.add_component(w, e, value)`                       | добавить/записать компонент (вне игровой фазы) |
| `ecs.get_component(w, e, T) -> ^T`                     | прочитать/изменить (nil — нет)              |
| `ecs.remove_component(w, e, T)`                        | удалить компонент (вне игровой фазы)        |
| `ecs.query_new(w, types)` / `query_next` / `query_get` | итерация по набору компонентов              |
| `ecs.query_first(q) -> Maybe(Entity)`                  | первая подходящая сущность                  |
| `ecs.cmds_spawn(cmds) -> Entity`                       | отложенный спавн (id сразу, «рождение» на flush) |
| `ecs.cmds_add(cmds, e, value)`                         | отложенная запись компонента                |
| `ecs.cmds_remove(cmds, e, T)`                          | отложенное удаление компонента              |
| `ecs.cmds_destroy(cmds, e)`                            | отложенное уничтожение (без дублей)         |

Важные детали:

- **Две фазы. Значения — сразу, структура — отложенно.** `run` блокирует мир на время
  update/render (`world.locked`): прямые `add_component/remove_component/destroy_entity` в этот
  момент падают с подсказкой. Структуру меняют только через `cmds_*`, и один `cmds_flush`
  (в `run`, между update и render) применяет её в порядке **adds → removes → destroys**.
  Поэтому пулы не двигаются, пока системы держат указатели на компоненты: можно писать
  `pos.x += …` прямо, а спавнить рядом через cmds (см. `player_update`, `bullet_spawn`).
  Прямые структурные операции остаются для `init`/`cleanup` и вне `run`.
- **Созданное в кадре видно с ближайшего flush**: update-системы этого кадра новую сущность
  ещё не увидят (родилась на границе), рендер — уже увидят. Для пуль/врагов это незаметно.
  Несколько `cmds_add` одного типа на сущность за кадр — последнее побеждает; сущность,
  созданная и уничтоженная в одном кадре, корректно рождается и умирает (id возвращается).
- **Теги (нуль-размерные компоненты)** присутствуют в запросах, но `get_component` для них
  возвращает `nil` — их наличие проверяют запросом.
- `Query` — лёгкая структура с указателями; `query_reset` вызывается каркасом перед каждой
  системой, вручную (во вложенных циклах) — тоже `query_reset`.

---

## Настройки окна

```odin
game.settings.window = {
	title = "game",
	size  = {1280, 720},
	flags = {.VSYNC_HINT, .MSAA_4X_HINT},
}
```

---

## Как устроен `example/`

Мини-шутер: игрок (WASD + Shift-спринт + Enter-выстрел), пули, враги, коллизии, UI.

| Файл                         | Что демонстрирует                                                                            |
|------------------------------|----------------------------------------------------------------------------------------------|
| `main.odin`                  | полный набор систем, две зоны памяти (heap + temp-арена), порядок lifecycle, `world_destroy` |
| `components/`                | типизация компонентов: distinct-типы, теги, структуры                                        |
| `player.odin` / `enemy.odin` | спавн из `init`, чтение/запись компонентов в update                                          |
| `bullet.odin`                | массовая итерация, изменение size по направлению                                             |
| `collision.odin`             | вложенный запрос (`query_reset`/`query_next`), отложенное уничтожение                        |
| `ui.odin`                    | `reads` + `ctx_query` (кешированный запрос игрока)                                           |
| `background.odin`            | `types = {}` рендер-система                                                                  |
| `cleanup.odin`               | `CleanupSystem`: что выполняется после цикла                                                 |
