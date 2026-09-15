# VoteAnswers — кооперативное голосование за реплики (BG3)

Мод для Baldur's Gate 3: в кооперативе при открытии диалога с несколькими
вариантами ответа каждый игрок выбирает свою реплику, затем за каждый
выбранный вариант бросается d20 (как в Solasta) — побеждает наибольший
бросок, и именно эта реплика произносится.

## Требуемое окружение (настройка с нуля)

1. **BG3 Script Extender (Norbyte's Script Extender)**
   https://github.com/Norbyte/bg3se — скачать релиз, распаковать
   `DWrite.dll` и `NativeMods/` в папку с `bg3_dx11.exe` /
   `bg3.exe` (обычно `...\Baldurs Gate 3\bin`).
2. **Папка модов игры**: `%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Mods\`
   и `...\PlayerProfiles\Public\modsettings.lsx` — сюда пойдёт собранный
   `.pak`, либо для разработки мод можно подключить как "loose files" через
   `ScriptExtender/Config.json` каждого мода (см. документацию BG3SE о
   `--game-dir`/loose-mod loading).
3. **BG3 Modder's Multitool / lslib** — для упаковки `Mods/VoteAnswers/`
   в `.pak` и генерации `modsettings.lsx` записи.
4. Опционально: официальный **BG3 Toolkit** (Steam) — если понадобится
   редактировать сами диалоговые узлы, а не только перехватывать их.

## Структура мода

```
Mods/VoteAnswers/
  meta.lsx                          — метаданные мода
  ScriptExtender/
    Config.json                     — включает Lua-загрузку BG3SE
    Lua/
      BootstrapServer.lua           — точка входа на хосте
      BootstrapClient.lua           — точка входа на каждом клиенте
      Shared/NetChannels.lua        — имена каналов + бросок кубика
      Server/DialogVote.lua         — сбор голосов, броски, разрешение
      Client/VoteUI.lua             — IMGUI-оверлей голосования и результатов
```

## Как это работает

1. Диалог открывается с несколькими репликами → сервер вызывает
   `VoteAnswers.OnDialogOptionsAvailable(instanceId, speakerName, lines)`
   и рассылает список всем клиентам.
2. Каждый клиент показывает окно голосования (`Client/VoteUI.lua`),
   игрок жмёт на свою реплику — уходит `PlayerVoteCast`.
3. Как только проголосовали все присутствующие игроки (или истёк таймаут
   15 сек), сервер бросает d20 за каждый выбранный вариант, при ничьей —
   переброс между теми, кто на первом месте.
4. Результат (`VoteResultBroadcast`) рассылается всем, окно 3 секунды
   показывает броски и победителя, затем сервер вызывает
   `VoteAnswers.ApplyWinningLine(instanceId, winningLineIndex)`.

## Статус: известное нерешённое препятствие

Игра сейчас на финальном патче 8 (дальнейших обновлений не будет), поэтому
API BG3SE для неё — стабильная цель, и часть кода уже сверена с актуальной
документацией:

- **Подтверждено и подключено**: сетевой слой на современном `NetChannel`
  API (`Ext.Net.CreateChannel` / `:Broadcast` / `:SendToServer` /
  `:SetHandler`), список игроков в диалоге через реальные Osiris-события
  `DialogActorJoined` / `DialogActorLeft` / `DialogEnded`, конвертация
  `peerId -> userId` (`peerId + 1`).
- **Не решено (текст+индекс реплик и принудительный выбор)**: Osiris отдаёт
  только грубые диалоговые события — `DialogStarted`, `DialogEnded`,
  `DialogActorJoined`, `DialogRollResult` — но **не** список реплик открытого
  узла и не способ выбрать конкретную. Реплики — узлы `TagQuestion`,
  которые рендерит клиентский UI, а не Osiris.
- **Подтверждённый путь дальше**: у bg3se есть настоящий (хоть и скупо
  задокументированный) `Ext.UI` — например, рабочий паттерн
  `Ext.UI.GetRoot():Find("ContentRoot"):VisualChild(1)` для обхода дерева
  Noesis-интерфейса (только на клиенте). Конкретных имён элемента/свойств
  viewmodel, отвечающих за реплики диалога, в документации и коде мода
  найти не удалось — их нужно вытащить дампом прямо в игре.

**Добавлен инструмент для этого**: `Client/UIExplore.lua` —
`VoteAnswers.DumpUITree(findName, maxDepth)` (или консольная команда
`!votedump`), которая обходит дерево `Ext.UI.GetRoot()` и печатает
типы/имена узлов в лог SE. План использования:

1. Открыть диалог с несколькими репликами в игре (с включённой консолью SE).
2. Вызвать `!votedump` (или `VoteAnswers.DumpUITree()` из консоли) и найти
   в дампе узел, отвечающий за список реплик.
3. Через `Ext.UI.GetRoot():Find(...)`, зная точное имя, прочитать текст
   реплик и повесить обработчик на выбор — подключить найденное к
   `VoteAnswers.OnDialogOptionsAvailable` / `VoteAnswers.ApplyWinningLine`
   в `Server/DialogVote.lua` (подробности и альтернативы — в комментарии в
   начале этого файла).

Если и через `Ext.UI` конкретный виджет реплик не найдётся или окажется
недоступен для чтения/управления — см. запасные варианты в комментарии
файла: вопрос в Discord/issues bg3se (https://github.com/Norbyte/bg3se),
либо, в крайнем случае, нативное расширение bg3se на C++.

Оставшиеся мелкие TODO (фильтрация NPC vs игроков в
`GetConnectedPlayerUserIds`, `LocalPlayerUserId()` на клиенте, точная
сигнатура `Ext.RegisterConsoleCommand`) — второстепенны по сравнению с
пунктом выше.

## Сборка `.pak`

```
# пример, конкретные флаги зависят от версии lslib/Multitool
Divine.exe -a create-package -s Mods/VoteAnswers -d VoteAnswers.pak --game bg3
```

После сборки добавить запись в `modsettings.lsx` (через BG3 Mod Manager
или вручную) и включить мод в лаунчере игры на каждом клиенте — в BG3
мультиплеере мод должен быть установлен у всех участников сессии.
