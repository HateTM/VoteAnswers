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
      Client/DialogueReader.lua     — чтение текста реплик (подтверждённый путь) + поиск команды выбора
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

## Статус: чтение реплик решено, выбор — последний открытый вопрос

Игра сейчас на финальном патче 8 (дальнейших обновлений не будет), поэтому
API BG3SE для неё — стабильная цель, и часть кода уже сверена с актуальной
документацией:

- **Подтверждено и подключено**: сетевой слой на современном `NetChannel`
  API (`Ext.Net.CreateChannel` / `:Broadcast` / `:SendToServer` /
  `:SetHandler`), список игроков в диалоге через реальные Osiris-события
  `DialogActorJoined` / `DialogActorLeft` / `DialogEnded`, конвертация
  `peerId -> userId` (`peerId + 1`).
- **Не решено, проверено исчерпывающе (текст+индекс реплик и принудительный
  выбор)**: просмотрен полный официальный список всех 493 Osiris Calls
  (docs.baldursgate3.game, Category:Osiris_Calls) — диалоговых среди них
  только `ClearDialogTag`, `DialogRequestStop`,
  `DialogRequestStopForDialog`, `DialogSetTeleportPartyOnEnded`,
  `DialogSetTeleportPartyToLevelOnEnded`,
  `DialogSetVariableTranslatedString`, `DebugDialogSkillCheck`,
  `SetHasDialog`, `SetHasOsirisDialog`, `SetEntityEventDialog`,
  `SetDualEntityEventDialog` — и ни один не читает список реплик и не
  выбирает конкретную. Дополнительно просмотрен и полный список **Osiris
  Events** (диалоговые: `DialogStarted/Ended`,
  `DialogActorJoined/JoinFailed/Left`, `DialogStartRequested`,
  `DialogForceStopping`, `DialogRequestFailed`, `DialogRollResult`,
  `DialogAttackRequested`, `ActorSpeakerIndexChanged`,
  `InstanceDialogChanged`, `NestedDialogPlayed`, `AutomatedDialog*`,
  `FlagSet`/`FlagCleared`, `DialogueCapabilityChanged`,
  `TimelineScreenFadeStarted`, `RollResult`) — ближе всего
  `ActorSpeakerIndexChanged` (чья очередь говорить, не текст реплик) и
  `FlagSet`/`FlagCleared` (флаг диалога меняется уже *после* сделанного
  выбора, а не позволяет прочитать варианты заранее). И, наконец, полный
  список **Osiris Queries** (387 записей) — диалоговые: `DialogIsCrimeDialog`,
  `DialogRemoveActorFromDialog`, `GetHasOsirisDialog`, `IsSpeakerReserved`,
  плюс общие `GetFlagName`/`GetFlagDescription` и `ResolveTranslatedString`
  (резолвит уже известный handle перевода в текст — полезная утилита, но не
  даёт сам список реплик узла). Нигде ничего подходящего нет. Это закрывает
  вопрос окончательно по всем трём категориям — Calls, Events и Queries:
  **через Osiris этого сделать нельзя**, не только «не нашли в
  документации». Реплики — узлы `TagQuestion`, которые рендерит клиентский
  UI, а не Osiris.
- **ЧТЕНИЕ реплик — решено и подтверждено вживую** (в игре, через KEN
  Noesis debugger, скриншот от 17.09.2026):

  ```
  Ext.UI:GetRoot():Find('ContentRoot'):FindChildWithName('Dialogue')
      :Child(1).Data.Dialogues[N].Answers
  ```

  Это рабочий, живой путь к массиву `gui::VMDialogueAnswer`. У каждого
  элемента подтверждены поля:
  - `BodyText` — сам текст реплики (например, `"Можно тебя поцеловать?"`);
  - `AnswerIdx`, `Enabled`;
  - `BoundEvent` — имя UI-события выбора (`"UISelectSlot1"`, судя по
    паттерну — `"UISelectSlot2"`/`"3"` для остальных вариантов);
  - `PollResultIsMostVoted` / `PollResultNumVotes` / `PollResultPercent` —
    подтверждает, что у игры **уже есть встроенная структура данных под
    голосование по репликам** на уровне каждого варианта (в соло-тесте
    везде нули, но сами поля реальны);
  - `CtxAnswer.Text.Params[i]` — текст описания проверки/DC, если есть.

  Реализовано в `Client/DialogueReader.lua`:
  `VoteAnswers.ReadDialogueLines()` / `VoteAnswers.GetLiveAnswers()`
  (плюс консольная команда `!votelines`).

- **ВЫБОР реплики — последний открытый вопрос.** `BoundEvent` — обычная
  строка, а не объект-команда. Ни у корневого виджета `Dialogue`, ни у
  самого `VMDialogueAnswer` в панели свойств KEN-дебаггера не нашлось
  явного `Command`/`Execute` — но эта панель, похоже, показывает только
  свойства, а не методы. Для поиска реального механизма выбора добавлена
  `VoteAnswers.DumpAnswerKeys()` (`!voteanswerkeys [answerNumber]
  [dialogueIndex]` в консоли) — она перебирает объект ответа через
  `pairs()`, что покажет и методы тоже, не только то, что видно в UI
  KEN-дебаггера.

**Инструменты в моде для дальнейшего поиска:**

- `Client/UIExplore.lua` — общий дамп дерева Noesis: `VoteAnswers.DumpUITree(findName, maxDepth)` / `!votedump`.
- `Client/DialogueReader.lua` — чтение реплик (`!votelines`) и поиск ключей/методов ответа (`!voteanswerkeys`).
- `Client/KENIntegration.lua` — опциональная интеграция с My Assistant KEN, логирует `MenuOpened`/`MenuClosed`.

План проверки в игре (осталось только это):

1. Открыть диалог с несколькими репликами, в консоли SE вызвать
   `!voteanswerkeys 1` (или `VoteAnswers.DumpAnswerKeys(1)`), посмотреть
   вывод в логе — там должны появиться все ключи объекта ответа, включая
   методы, которых не было видно в панели свойств KEN.
2. Найти среди них что-то вроде `Select`/`Execute`/`Click`/`Invoke` или
   способ поднять событие с именем из `BoundEvent`.
3. Подключить найденный вызов в `VoteAnswers.ApplyWinningLine` в
   `Server/DialogVote.lua`, и повесить клиентский слушатель открытия
   диалога (например, через `MenuOpened`/`UIOpened` в
   `Client/KENIntegration.lua`), который читает реплики через
   `VoteAnswers.ReadDialogueLines()` и зовёт
   `VoteAnswers.OnDialogOptionsAvailable(...)`.

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
