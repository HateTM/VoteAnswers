-- Shared net channels + die roll helper, executed on both the server and
-- every client so the channel objects exist identically on each side.
--
-- Uses the modern NetChannel API (Ext.Net.CreateChannel /
-- channel:Broadcast / channel:SendToServer / channel:SetHandler), which
-- replaced the older Ext.RegisterNetListener approach. Confirmed against
-- the bg3se API docs (https://github.com/Norbyte/bg3se/blob/main/Docs/API.md).

VoteAnswers = VoteAnswers or {}

-- Must match meta.lsx's ModuleInfo UUID.
local MOD_UUID = "a1b2c3d4-e5f6-4a5b-9c8d-000000000001"

VoteAnswers.Channels = {
    -- Server -> all clients: a new dialogue node opened with N selectable lines.
    -- Payload: { instanceId, speakerName, lines = { {index, text}, ... }, timeoutMs }
    DialogOptions = Ext.Net.CreateChannel(MOD_UUID, "VoteAnswers_DialogOptions"),

    -- Client -> server: the local player picked a line.
    -- Payload: { instanceId, playerUserId, lineIndex }
    PlayerVote = Ext.Net.CreateChannel(MOD_UUID, "VoteAnswers_PlayerVote"),

    -- Server -> all clients: voting closed, dice rolled, winner decided.
    -- Payload: { instanceId, rolls = { {playerUserId, lineIndex, roll}, ... }, winningLineIndex }
    VoteResult = Ext.Net.CreateChannel(MOD_UUID, "VoteAnswers_VoteResult"),
}

-- d20 roll, matching the "highest die wins" rule from Solasta's shared dialogue.
function VoteAnswers.RollDie(sides)
    sides = sides or 20
    return Ext.Utils.Random(1, sides)
end

-- Osiris' player-facing functions expect userId = peerId + 1.
-- (Confirmed in bg3se docs: "the userId in these examples is actually a
-- peerId... Osiris functions usually expect peerId + 1".)
function VoteAnswers.PeerIdToOsirisUserId(peerId)
    return peerId + 1
end
