-- Reads live dialogue reply data from the Noesis UI, using the path the
-- user confirmed in-game with the KEN Noesis debugger (screenshot,
-- 2026-09-17):
--
--   Ext.UI:GetRoot():Find('ContentRoot'):FindChildWithName('Dialogue')
--       :Child(1).Data.Dialogues[N].Answers
--
-- Each entry in .Answers is a gui::VMDialogueAnswer with (all confirmed
-- present in the live debugger dump):
--   AnswerIdx              -- 0-based(?) index of this answer
--   BodyText                -- the reply's display text, e.g. "Можно тебя поцеловать?"
--   BoundEvent               -- e.g. "UISelectSlot1" -- the name of the UI
--                               event that fires when this answer is picked
--   Enabled                  -- bool
--   HighlightedByHost         -- bool
--   PollResultIsMostVoted     -- bool  -- confirms BG3 already tracks a
--   PollResultNumVotes        -- number   per-answer vote count/percentage
--   PollResultPercent         -- number   natively (currently 0 in solo
--                                         testing; shape only confirmed,
--                                         not exercised with real votes yet)
--   CtxAnswer.Text.Params[i].Text / .DiceTypeSet.{Amount,DiceType,...}
--                             -- skill-check/DC flavor text, if any
--
-- STILL UNCONFIRMED: how to force-select an answer. BoundEvent is a plain
-- string, and neither the Dialogue root widget nor the VMDialogueAnswer
-- itself showed an obvious Command/Execute in the KEN debugger's property
-- panel -- but that panel may only list properties, not callable methods.
-- VoteAnswers.DumpAnswerKeys() below enumerates *everything* on a live
-- answer object (via pairs(), which reaches methods a property-only UI
-- wouldn't show) so we can find the real selection mechanism without
-- more manual tree-clicking.

VoteAnswers = VoteAnswers or {}

--- Walks to the live Answers array for the currently open dialogue.
--- @param dialogueIndex number|nil which entry in .Data.Dialogues to use (default 2, matching the confirmed screenshot)
--- @return table|nil answers, string|nil error
function VoteAnswers.GetLiveAnswers(dialogueIndex)
    dialogueIndex = dialogueIndex or 2

    local root = Ext.UI.GetRoot()
    if not root then
        return nil, "Ext.UI.GetRoot() returned nothing"
    end

    local ok, dialogueWidget = pcall(function()
        return root:Find("ContentRoot"):FindChildWithName("Dialogue")
    end)
    if not ok or dialogueWidget == nil then
        return nil, "FindChildWithName('Dialogue') did not match anything"
    end

    local ok2, answers = pcall(function()
        return dialogueWidget:Child(1).Data.Dialogues[dialogueIndex].Answers
    end)
    if not ok2 or answers == nil then
        return nil, "Child(1).Data.Dialogues[" .. dialogueIndex .. "].Answers not present"
    end

    return answers, nil
end

--- Reads the current reply lines as {index, text} pairs, in the same shape
--- VoteAnswers.OnDialogOptionsAvailable (Server/DialogVote.lua) expects.
function VoteAnswers.ReadDialogueLines(dialogueIndex)
    local answers, err = VoteAnswers.GetLiveAnswers(dialogueIndex)
    if not answers then
        Ext.Utils.Print("[VoteAnswers] ReadDialogueLines failed: " .. tostring(err))
        return nil
    end

    local lines = {}
    for i, answer in ipairs(answers) do
        local ok, bodyText = pcall(function() return answer.BodyText end)
        if ok and bodyText and bodyText ~= "" then
            table.insert(lines, { index = i, text = bodyText })
        end
    end
    return lines
end

--- Diagnostic: enumerates every key on a live answer object (properties
--- AND methods -- pairs() sees both, unlike the KEN debugger's property
--- panel), to find the real way to force-select an answer.
--- @param answerNumber number|nil which answer in the array to inspect (1-based, default 1)
--- @param dialogueIndex number|nil default 2, matching the confirmed screenshot
function VoteAnswers.DumpAnswerKeys(answerNumber, dialogueIndex)
    answerNumber = answerNumber or 1

    local answers, err = VoteAnswers.GetLiveAnswers(dialogueIndex)
    if not answers then
        Ext.Utils.Print("[VoteAnswers] DumpAnswerKeys failed: " .. tostring(err))
        return
    end

    local answer = answers[answerNumber]
    if not answer then
        Ext.Utils.Print("[VoteAnswers] No answer at index " .. answerNumber)
        return
    end

    Ext.Utils.Print("[VoteAnswers] Keys on answer " .. answerNumber .. ":")
    local ok = pcall(function()
        for key, value in pairs(answer) do
            Ext.Utils.Print(string.format("  %s : %s", tostring(key), type(value)))
        end
    end)
    if not ok then
        Ext.Utils.Print("[VoteAnswers]   pairs() failed on this object -- it may be a userdata proxy that doesn't support iteration; try dumping the Dialogue widget itself instead with a similar pairs() loop.")
    end
end

-- Console commands: `!votelines` / `!voteanswerkeys [answerNumber] [dialogueIndex]`
if Ext.RegisterConsoleCommand then
    Ext.RegisterConsoleCommand("votelines", function(_, dialogueIndex)
        local lines = VoteAnswers.ReadDialogueLines(dialogueIndex and tonumber(dialogueIndex) or nil)
        if lines then
            for _, l in ipairs(lines) do
                Ext.Utils.Print(string.format("[VoteAnswers] %d: %s", l.index, l.text))
            end
        end
    end)

    Ext.RegisterConsoleCommand("voteanswerkeys", function(_, answerNumber, dialogueIndex)
        VoteAnswers.DumpAnswerKeys(
            answerNumber and tonumber(answerNumber) or nil,
            dialogueIndex and tonumber(dialogueIndex) or nil
        )
    end)
end
