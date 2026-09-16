-- Optional integration with the community library "My Assistant KEN"
-- (Nexus: baldursgate3/mods/22530, by Mazzle23), a Noesis-UI helper built
-- exactly for the problem this mod has: finding and monitoring BG3's
-- Noesis UI objects (the dialogue window included) from Lua, without
-- hand-rolling a recursive VisualChild walk.
--
-- CONFIRMED from KEN's own mod page (fetched 2026-09-16, patch-8 compatible):
--   * Ext.UI:GetRoot() / :Find(name) / :FindChildWithName(name) /
--     :FindVisualChildWithName(name) / :FindChildWithProperty(prop, value) /
--     :Child(i) / :VisualChild(i) / .DataContext / .FocusedElement are real,
--     working path operations.
--   * KEN's own example path names a dialogue node directly:
--       Ext.UI:GetRoot():Find('ContentRoot'):FindChildWithName('Dialog_box')
--   * KEN fires Ext.ModEvents.KEN_Helper["MenuOpened"] / ["MenuClosed"]
--     specifically when BG3 "opens UI elements that take over the UI, like
--     the GameMenu, MainMenu, cut scenes and dialog" -- i.e. dialogue open
--     is one of the cases this event exists for.
--   * UI commands are driven by calling :Execute() on a Command object
--     found on .DataContext, e.g. obj.DataContext.ContinueCommand:Execute().
--     This is the likely shape of how to force-select a reply line too,
--     once the right DataContext property name is found.
--
-- STILL UNCONFIRMED (needs the KEN in-game Noesis debugger, or
-- Client/UIExplore.lua's dump, run against a real multi-option dialogue):
--   * The exact DataContext property that holds the list of reply
--     lines/text for 'Dialog_box' (or whatever the live node turns out to
--     be named -- 'Dialog_box' comes from KEN's own doc example, not from
--     us testing it).
--   * The exact Command (if any) that selects a specific reply by index --
--     the analogue of ContinueCommand but for picking option N.
--
-- REQUIRES: "My Assistant KEN" (or the equivalent "Mazzle_Lib") installed
-- and enabled as a mod dependency alongside VoteAnswers. This file is
-- inert (does nothing) if KEN isn't present, so it's safe to keep even if
-- that dependency isn't installed yet.

VoteAnswers = VoteAnswers or {}

if not Ext.ModEvents or not Ext.ModEvents.KEN_Helper then
    return -- My Assistant KEN not installed/enabled; nothing to wire up here
end

-- Once a real dialogue reply node name/DataContext shape is confirmed via
-- the KEN debugger, resolve and monitor it here instead of guessing:
--
-- local handle = Mods.KEN_Helper.KEN_NoesisPathResolver.ResolveAndMonitor(
--     "Ext.UI:GetRoot():Find('ContentRoot'):FindChildWithName('Dialog_box')",
--     -1,
--     function(dialogBox)
--         -- TODO: read the confirmed reply-list property off
--         -- dialogBox.DataContext and call VoteAnswers.OnDialogOptionsAvailable
--         -- (see Server/DialogVote.lua) with the real line texts.
--     end,
--     function()
--         -- dialogue box closed/gone
--     end
-- )

-- MenuOpened/MenuClosed reliably bracket "BG3 took over the UI" (dialogue
-- included per KEN's own docs), so at minimum this tells us when a
-- dialogue-like takeover starts/ends even before the reply-list shape is
-- pinned down -- useful for the vote overlay's show/hide timing once wired.
Ext.ModEvents.KEN_Helper["MenuOpened"]:Subscribe(function(e)
    Ext.Utils.Print("[VoteAnswers] KEN MenuOpened")
end)

Ext.ModEvents.KEN_Helper["MenuClosed"]:Subscribe(function(e)
    Ext.Utils.Print("[VoteAnswers] KEN MenuClosed")
end)
