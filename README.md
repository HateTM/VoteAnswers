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
5. **Рекомендуется для разработки**: **My Assistant KEN**
   (https://www.nexusmods.com/baldursgate3/mods/22530, автор Mazzle23) и
   парный **KEN Noesis debugger** — библиотека и отладчик, сделанные
   сообществом ровно для поиска/мониторинга Noesis UI-объектов игры (в т.ч.
   диалогового окна) из Lua-мода. См. раздел ниже.

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
      Client/UIExplore.lua          — дамп дерева Noesis UI (свой, без зависимостей)
      Client/KENIntegration.lua     — опциональная интеграция с "My Assistant KEN"
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
  Noesis-интерфейса (только на клиенте).
- **Конкретная зацепка**: страница мода **My Assistant KEN**
  (https://www.nexusmods.com/baldursgate3/mods/22530) — библиотеки
  сообщества именно для поиска/мониторинга Noesis-объектов — в собственном
  примере пути называет диалоговый узел напрямую:
  `Ext.UI:GetRoot():Find('ContentRoot'):FindChildWithName('Dialog_box')`.
  Там же подтверждён паттерн вызова UI-команд через
  `obj.DataContext.<Command>:Execute()` (на примере `ContinueCommand`) —
  вероятно, тем же способом можно будет выбрать конкретную реплику. Событие
  `Ext.ModEvents.KEN_Helper["MenuOpened"]` явно триггерится в т.ч. на
  диалог ("cut scenes and dialog").

  Это по-прежнему не точное имя/свойство того, что нужно нам (`Dialog_box`
  — из документации KEN, не из нашего собственного теста), но это
  конкретная стартовая точка для поиска вместо дампа с нуля.

**Инструменты для дальнейшего поиска (оба уже в моде):**

- `Client/UIExplore.lua` — свой дамп дерева, без зависимостей:
  `VoteAnswers.DumpUITree(findName, maxDepth)` / консольная команда
  `!votedump`.
- `Client/KENIntegration.lua` — опциональная интеграция с My Assistant
  KEN (активна только если та библиотека установлена и включена как
  зависимость мода); сейчас логирует `MenuOpened`/`MenuClosed` и содержит
  закомментированный шаблон `ResolveAndMonitor(...)` для узла
  `Dialog_box`, готовый к раскомментированию после проверки в игре.

План проверки в игре:

1. Установить **My Assistant KEN** + **KEN Noesis debugger** как
   зависимости мода (рекомендуется — отладчик сильно быстрее, чем искать
   вручную по дампу).
2. Открыть диалог с несколькими репликами, найти в KEN-дебаггере узел
   реплик и скопировать его путь (или, без KEN, вызвать `!votedump` и
   поискать в дампе).
3. Проверить, действительно ли путь `Find('ContentRoot'):FindChildWithName('Dialog_box')`
   (или похожий) ведёт к нужному узлу, прочитать текст реплик из
   `.DataContext`, найти команду для выбора конкретной реплики.
4. Раскомментировать и доработать шаблон в `Client/KENIntegration.lua`,
   подключить найденное к `VoteAnswers.OnDialogOptionsAvailable` /
   `VoteAnswers.ApplyWinningLine` в `Server/DialogVote.lua` (подробности и
   запасные варианты — в комментарии в начале этого файла: вопрос в
   Discord/issues bg3se, либо, в крайнем случае, нативное расширение bg3se
   на C++).

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
