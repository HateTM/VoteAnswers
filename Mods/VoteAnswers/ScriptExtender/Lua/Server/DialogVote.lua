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
-- IMPORTANT / TODO before first in-game test:
--   The exact Osiris/Ext.Events hook names for "a dialogue node opened with
--   candidate lines" and "force-select dialogue line N" change between BG3
--   patches and BG3SE releases. Verify against the current BG3SE docs
--   (https://github.com/Norbyte/bg3se) and Osiris story events, then wire
--   VoteAnswers.OnDialogOptionsAvailable / VoteAnswers.ApplyWinningLine below
--   to the real event names. The vote/roll/broadcast logic itself does not
--   depend on those specifics and can be reused as-is.

VoteAnswers = VoteAnswers or {}

local Config = {
    VoteTimeoutMs = 15000,     -- how long players get to pick a line
    DieSides = 20,
    MinPlayersToVote = 2,      -- below this, skip voting and just apply the pick instantly
}

-- Active vote state, keyed by dialogue instance id.
local activeVotes = {}

local function GetConnectedPlayerUserIds()
    local ids = {}
    for _, player in ipairs(Osiris.DB_IsPlayer:Get(nil)) do
        -- TODO: replace with the real "list connected player peer/user ids" call,
        -- e.g. Ext.Entity.GetAllEntitiesWithComponent("ServerCharacter") filtered
        -- to player-controlled characters, or Osiris' PlayerConnected database.
        table.insert(ids, player[1])
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

    local playerIds = GetConnectedPlayerUserIds()
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

    Ext.Net.BroadcastMessage(VoteAnswers.Channels.DialogOptionsBroadcast, Ext.Json.Stringify({
        instanceId = instanceId,
        speakerName = speakerName,
        lines = lines,
        timeoutMs = Config.VoteTimeoutMs,
    }))

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

Ext.RegisterNetListener(VoteAnswers.Channels.PlayerVoteCast, function(_, payload)
    local data = Ext.Json.Parse(payload)
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

    Ext.Net.BroadcastMessage(VoteAnswers.Channels.VoteResultBroadcast, Ext.Json.Stringify({
        instanceId = instanceId,
        rolls = rolls,
        winningLineIndex = winningLineIndex,
    }))

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
