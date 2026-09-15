-- Shared constants: message channel names used between server and clients.
-- Keep this file identical on both sides so the strings never drift.

VoteAnswers = VoteAnswers or {}

VoteAnswers.Channels = {
    -- Server -> all clients: a new dialogue node opened with N selectable lines.
    -- Payload: { instanceId, speakerName, lines = { {index, text}, ... }, timeoutMs }
    DialogOptionsBroadcast = "VoteAnswers_DialogOptions",

    -- Client -> server: the local player picked a line.
    -- Payload: { instanceId, playerUserId, lineIndex }
    PlayerVoteCast = "VoteAnswers_PlayerVote",

    -- Server -> all clients: voting closed, dice rolled, winner decided.
    -- Payload: { instanceId, rolls = { {playerUserId, lineIndex, roll}, ... }, winningLineIndex }
    VoteResultBroadcast = "VoteAnswers_VoteResult",
}

-- d20 roll, matching the "highest die wins" rule from Solasta's shared dialogue.
function VoteAnswers.RollDie(sides)
    sides = sides or 20
    return Ext.Utils.Random(1, sides)
end
