-- Client-side voting overlay, built with BG3SE's Ext.IMGUI.
--
-- Shows every candidate line as a selectable button; once the local player
-- picks one, casts the vote and waits for the server's result broadcast to
-- reveal each player's roll and the winning line (Solasta-style reveal).

VoteAnswers = VoteAnswers or {}

local window = nil
local state = {
    instanceId = nil,
    speakerName = nil,
    lines = {},
    myChoice = nil,
    result = nil, -- filled in once VoteResultBroadcast arrives
}

local function LocalPlayerUserId()
    -- TODO: replace with the real "local client's player user id" accessor,
    -- e.g. Ext.ClientInput / Ext.Entity lookup for the locally controlled
    -- character's UserID component, current as of the BG3SE version in use.
    return Ext.ClientNet.GetLocalUserId and Ext.ClientNet.GetLocalUserId() or 0
end

local function CloseWindow()
    if window then
        window:Destroy()
        window = nil
    end
end

local function RenderVotingPhase()
    window:Text(state.speakerName)
    window:Separator()
    for _, line in ipairs(state.lines) do
        local label = line.text
        if state.myChoice == line.index then
            label = "> " .. label .. " <"
        end
        local btn = window:AddButton(label)
        btn.OnClick = function()
            if state.myChoice ~= nil then
                return -- already voted, one pick per player
            end
            state.myChoice = line.index
            VoteAnswers.Channels.PlayerVote:SendToServer({
                instanceId = state.instanceId,
                playerUserId = LocalPlayerUserId(),
                lineIndex = line.index,
            })
        end
    end
    if state.myChoice ~= nil then
        window:Text("Waiting for the other players to choose...")
    end
end

local function RenderResultPhase()
    window:Text(state.speakerName)
    window:Separator()
    window:Text("Rolls:")
    for _, r in ipairs(state.result.rolls) do
        local line = state.lines[r.lineIndex]
        local lineText = line and line.text or ("line " .. tostring(r.lineIndex))
        window:Text(string.format("  d20 = %d  -> %s", r.roll, lineText))
    end
    window:Separator()
    local winningLine = state.lines[state.result.winningLineIndex]
    window:Text("Winner: " .. (winningLine and winningLine.text or "?"))

    Ext.Timer.WaitFor(3000, function()
        CloseWindow()
        state = { instanceId = nil, speakerName = nil, lines = {}, myChoice = nil, result = nil }
    end)
end

VoteAnswers.Channels.DialogOptions:SetHandler(function(data)
    state.instanceId = data.instanceId
    state.speakerName = data.speakerName
    state.lines = {}
    for _, l in ipairs(data.lines) do
        state.lines[l.index] = l
    end
    state.myChoice = nil
    state.result = nil

    CloseWindow()
    window = Ext.IMGUI.NewWindow("VoteAnswers")
    window.Closeable = false
end)

VoteAnswers.Channels.VoteResult:SetHandler(function(data)
    if data.instanceId ~= state.instanceId then
        return
    end
    state.result = data
end)

Ext.Events.Tick:Subscribe(function()
    if not window then
        return
    end
    -- IMGUI windows in BG3SE are rebuilt from their current children each
    -- frame; clear and redraw based on whether a result has arrived yet.
    window:Clear()
    if state.result then
        RenderResultPhase()
    else
        RenderVotingPhase()
    end
end)
