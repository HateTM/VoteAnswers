-- Server-side vote orchestration.
--
-- Flow:
--   1. A dialogue node with multiple selectable player lines opens.
--   2. We broadcast the available lines to every connected client instead of
--      letting the first click win immediately.
--   3. Each client's player casts one vote (their chosen line index).
--   4. Once every present player has voted (or the timeout expires), each
--      distinct chosen line gets a d20 roll; highest roll wins ties broken
--      by re-roll, exactly like Solasta's shared dialogue checks.
--   5. The winning line index is fed back into the vanilla dialogue system.
--
-- KNOWN OPEN PROBLEM (confirmed by research, patch 8 / current bg3se docs):
--   Osiris only exposes coarse dialogue events -- DialogStarted(dialog,
--   instanceID), DialogEnded, DialogActorJoined(dialog, instanceID, actor,
--   speakerIndex), DialogActorLeft, DialogRollResult(character, success,
--   dialog, isDetectThoughts, criticality).
--
--   This is now checked exhaustively, not just "not found by search": the
--   official Category:Osiris Calls listing (docs.baldursgate3.game) has 493
--   entries total, and every one of them has been reviewed. The only
--   dialogue-related Calls that exist are ClearDialogTag, DialogRequestStop,
--   DialogRequestStopForDialog, DialogSetTeleportPartyOnEnded,
--   DialogSetTeleportPartyToLevelOnEnded, DialogSetVariableTranslatedString,
--   DebugDialogSkillCheck, SetHasDialog, SetHasOsirisDialog,
--   SetEntityEventDialog, SetDualEntityEventDialog -- none of which reads a
--   node's reply line text/index or force-selects one.
--   (DialogSetVariableTranslatedString substitutes a text variable into a
--   line, e.g. a name; ClearDialogTag/SetTag affect whether a TagQuestion
--   node is available at all, not which available option gets picked.)
--
--   Conclusion: there is definitively no Osiris-level way to do this.
--   Player reply options are TagQuestion nodes rendered by the client-side
--   dialogue UI, not surfaced through Osiris at all -- the only remaining
--   avenue is client-side UI introspection (see below).
--
--   The confirmed path forward is client-side UI introspection: bg3se does
--   have a real, documented (if sparsely) Ext.UI namespace -- e.g.
--   Ext.UI.GetRoot():Find("ContentRoot"):VisualChild(1) is a real, working
--   call pattern for walking the Noesis visual tree, client-side only.
--   What is NOT yet confirmed is the specific element name(s)/viewmodel
--   properties behind the dialogue reply buttons -- that has to be found by
--   running Client/UIExplore.lua's VoteAnswers.DumpUITree() (or the
--   "!votedump" console command it registers) while a real multi-option
--   dialogue is open, and reading the resulting tree dump for the node that
--   holds the reply text/buttons.
--
--   VoteAnswers.OnDialogOptionsAvailable / VoteAnswers.ApplyWinningLine
--   below are the integration points for whatever that dump turns up: once
--   the dialogue reply UIObject is identified, a client-side listener on it
--   should call VoteAnswers.OnDialogOptionsAvailable(...) with the real
--   line texts, and VoteAnswers.ApplyWinningLine(...) should drive that same
--   UIObject's selection (or an underlying command binding) to pick the
--   winning line. Neither is wired to a real game hook yet -- the
--   vote/roll/broadcast logic itself is unaffected by this and can be
--   exercised standalone once a UI hook exists.

VoteAnswers = VoteAnswers or {}

local Config = {
    VoteTimeoutMs = 15000,     -- how long players get to pick a line
    DieSides = 20,
    MinPlayersToVote = 2,      -- below this, skip voting and just apply the pick instantly
}

-- Active vote state, keyed by dialogue instance id.
local activeVotes = {}

-- Players currently joined to the open dialogue instance, tracked via the
-- confirmed Osiris events DialogActorJoined/DialogActorLeft (see the header
-- comment). instanceId -> { [playerUserId] = true }
local dialogParticipants = {}

Ext.Osiris.RegisterListener("DialogActorJoined", 4, "after", function(dialog, instanceId, actor, speakerIndex)
    -- TODO: filter to player-controlled actors only (non-player NPCs also
    -- join dialogue instances); confirm the right "is this a player
    -- character" check for the current game version, e.g. Osiris' IsPlayer.
    dialogParticipants[instanceId] = dialogParticipants[instanceId] or {}
    dialogParticipants[instanceId][actor] = true
end)

Ext.Osiris.RegisterListener("DialogActorLeft", 3, "after", function(dialog, instanceId, actor)
    if dialogParticipants[instanceId] then
        dialogParticipants[instanceId][actor] = nil
    end
end)

Ext.Osiris.RegisterListener("DialogEnded", 2, "after", function(dialog, instanceId)
    dialogParticipants[instanceId] = nil
    activeVotes[instanceId] = nil
end)

local function GetConnectedPlayerUserIds(instanceId)
    local ids = {}
    for actor, _ in pairs(dialogParticipants[instanceId] or {}) do
        table.insert(ids, actor)
    end
    return ids
end

--- Called when a dialogue node opens with several selectable player lines.
--- @param instanceId string unique id of this dialogue node/instance
--- @param speakerName string display name, for the vote UI header
--- @param lines table array of { index = number, text = string }
function VoteAnswers.OnDialogOptionsAvailable(instanceId, speakerName, lines)
    if #lines <= 1 then
        return -- nothing to vote on
    end

    local playerIds = GetConnectedPlayerUserIds(instanceId)
    if #playerIds < Config.MinPlayersToVote then
        return -- solo play (or only one player present): fall back to vanilla behaviour
    end

    activeVotes[instanceId] = {
        speakerName = speakerName,
        lines = lines,
        votes = {},          -- playerUserId -> lineIndex
        expectedVoters = playerIds,
        startedAt = Ext.Utils.MonotonicTime(),
    }

    VoteAnswers.Channels.DialogOptions:Broadcast({
        instanceId = instanceId,
        speakerName = speakerName,
        lines = lines,
        timeoutMs = Config.VoteTimeoutMs,
    })

    Ext.Timer.WaitFor(Config.VoteTimeoutMs, function()
        VoteAnswers.ResolveVote(instanceId)
    end)
end

local function AllVotesIn(vote)
    for _, userId in ipairs(vote.expectedVoters) do
        if vote.votes[userId] == nil then
            return false
        end
    end
    return true
end

VoteAnswers.Channels.PlayerVote:SetHandler(function(data, user)
    local vote = activeVotes[data.instanceId]
    if not vote then
        return -- vote already resolved or unknown instance; ignore late/duplicate votes
    end

    vote.votes[data.playerUserId] = data.lineIndex

    if AllVotesIn(vote) then
        VoteAnswers.ResolveVote(data.instanceId)
    end
end)

--- Rolls dice for every distinct chosen line and applies the winner.
function VoteAnswers.ResolveVote(instanceId)
    local vote = activeVotes[instanceId]
    if not vote then
        return -- already resolved (timeout fired after votes completed)
    end
    activeVotes[instanceId] = nil

    -- Anyone who didn't vote in time gets no roll, matching Solasta (abstaining
    -- players simply don't influence the outcome).
    local rolls = {}
    local best = nil

    local function rollAndTrack(userId, lineIndex)
        local roll = VoteAnswers.RollDie(Config.DieSides)
        table.insert(rolls, { playerUserId = userId, lineIndex = lineIndex, roll = roll })
        if best == nil or roll > best.roll then
            best = { lineIndex = lineIndex, roll = roll }
        end
        return roll
    end

    for userId, lineIndex in pairs(vote.votes) do
        rollAndTrack(userId, lineIndex)
    end

    -- Re-roll ties between the current best contenders until a single winner
    -- emerges, mirroring a tabletop tie-break.
    local function tiedRollers()
        local tied = {}
        for _, r in ipairs(rolls) do
            if r.roll == best.roll then
                table.insert(tied, r)
            end
        end
        return tied
    end

    local tied = tiedRollers()
    while #tied > 1 do
        rolls = {}
        best = nil
        for _, r in ipairs(tied) do
            rollAndTrack(r.playerUserId, r.lineIndex)
        end
        tied = tiedRollers()
    end

    local winningLineIndex = best and best.lineIndex or vote.lines[1].index

    VoteAnswers.Channels.VoteResult:Broadcast({
        instanceId = instanceId,
        rolls = rolls,
        winningLineIndex = winningLineIndex,
    })

    VoteAnswers.ApplyWinningLine(instanceId, winningLineIndex)
end

--- Feeds the winning line index back into the vanilla dialogue system so the
--- game proceeds as if that player had simply clicked it.
--- @param instanceId string
--- @param lineIndex number
function VoteAnswers.ApplyWinningLine(instanceId, lineIndex)
    -- TODO: call the real dialogue-advance entry point, e.g. an Osiris event
    -- such as Osiris.DialogSelectAnswer(instanceId, lineIndex) if/when exposed,
    -- or the equivalent Ext.Entity dialogue component call for the current
    -- BG3SE version.
end
