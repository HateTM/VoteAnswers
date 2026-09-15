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

## Что нужно доверифицировать перед первым запуском в игре

Точные названия хуков диалоговой системы регулярно меняются между патчами
BG3 и релизами BG3SE. В коде явно помечено `TODO` в трёх местах:

- `Server/DialogVote.lua`: `GetConnectedPlayerUserIds()` — как получить
  список подключённых игроков (Osiris DB или `Ext.Entity`).
- `Server/DialogVote.lua`: `VoteAnswers.ApplyWinningLine()` — реальный вызов,
  которым выбранная реплика подставляется в диалог (Osiris-событие или
  `Ext.Entity`-компонент диалога).
- `Client/VoteUI.lua`: `LocalPlayerUserId()` — как получить ID локального
  игрока на клиенте.

Сама логика голосования/бросков/сети (`NetChannels.lua`, приём/рассылка
сообщений, разрешение ничьих) от конкретных названий хуков не зависит и
готова к использованию как есть. Нужно также подключить
`VoteAnswers.OnDialogOptionsAvailable(...)` к реальному событию "диалог
открылся с N репликами" — сверьтесь с актуальной документацией
https://github.com/Norbyte/bg3se и Osiris story events на момент сборки.

## Сборка `.pak`

```
# пример, конкретные флаги зависят от версии lslib/Multitool
Divine.exe -a create-package -s Mods/VoteAnswers -d VoteAnswers.pak --game bg3
```

После сборки добавить запись в `modsettings.lsx` (через BG3 Mod Manager
или вручную) и включить мод в лаунчере игры на каждом клиенте — в BG3
мультиплеере мод должен быть установлен у всех участников сессии.
