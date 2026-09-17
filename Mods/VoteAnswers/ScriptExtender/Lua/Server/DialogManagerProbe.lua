-- Server-side diagnostic: an alternate route to the current dialogue node,
-- via the DialogManager API confirmed working (read-only) in APID's
-- RollMirror.lua (a different BG3SE mod, "All Players In Dialogue"):
--
--   Ext.Utils.GetDialogManager().Dialogs[dialogId]
--       .ActiveDialog.Nodes[uuid]   -- uuid from inst.CurrentNode.UUID
--
-- APID only reads .Roll off a node (for skill-check flavor text) and never
-- needed to select an answer, so it doesn't answer our open question --
-- but the node object itself may expose an Answers list / Select method
-- that Client/DialogueReader.lua's UI-tree path (Ext.UI.GetRoot()...) does
-- not surface. This dumps that node via pairs(), same idea as
-- VoteAnswers.DumpAnswerKeys() on the client side, to check for a second
-- candidate selection mechanism.

VoteAnswers = VoteAnswers or {}

--- @param dialogId number|nil defaults to the dialogue the local host player is in
function VoteAnswers.DumpDialogManagerNode(dialogId)
    if not dialogId then
        local ok, rows = pcall(function()
            return Osi.DB_DialogPlayers:Get(nil, nil, 1)
        end)
        if ok and rows and rows[1] then
            dialogId = rows[1][1]
        end
    end
    if not dialogId then
        Ext.Utils.Print("[VoteAnswers] DumpDialogManagerNode: no dialogId given and none found via DB_DialogPlayers")
        return
    end

    local dm = Ext.Utils.GetDialogManager and Ext.Utils.GetDialogManager()
    if not dm then
        Ext.Utils.Print("[VoteAnswers] DumpDialogManagerNode: Ext.Utils.GetDialogManager() unavailable")
        return
    end

    local inst = nil
    pcall(function()
        inst = dm.Dialogs[dialogId]
    end)
    if not inst then
        pcall(function()
            for id, di in pairs(dm.Dialogs) do
                if id == dialogId or (di and di.DialogId == dialogId) then
                    inst = di
                    break
                end
            end
        end)
    end
    if not inst then
        Ext.Utils.Print("[VoteAnswers] DumpDialogManagerNode: no DialogInstance for id=" .. tostring(dialogId))
        return
    end

    Ext.Utils.Print("[VoteAnswers] DialogInstance keys (dialogId=" .. tostring(dialogId) .. "):")
    pcall(function()
        for key, value in pairs(inst) do
            Ext.Utils.Print(string.format("  %s : %s", tostring(key), type(value)))
        end
    end)

    local node = nil
    pcall(function()
        local nodeData = inst.CurrentNode
        local uuid = nodeData and (nodeData.UUID or nodeData.Uuid)
        local dialog = inst.ActiveDialog or inst.OverriddenDialog
        local nodes = dialog and dialog.Nodes
        if nodes and uuid then
            node = nodes[uuid] or nodes[tostring(uuid)]
        end
        if not node and inst.NodeSelection and inst.NodeSelection[1] then
            node = inst.NodeSelection[1].Node
        end
    end)
    if not node then
        Ext.Utils.Print("[VoteAnswers] DumpDialogManagerNode: could not resolve the current node (CurrentNode/NodeSelection)")
        return
    end

    Ext.Utils.Print("[VoteAnswers] Current node keys:")
    local ok = pcall(function()
        for key, value in pairs(node) do
            Ext.Utils.Print(string.format("  %s : %s", tostring(key), type(value)))
        end
    end)
    if not ok then
        Ext.Utils.Print("[VoteAnswers]   pairs() failed on the node -- likely a userdata proxy that doesn't support iteration")
    end
end

if Ext.RegisterConsoleCommand then
    Ext.RegisterConsoleCommand("votedmgr", function(_, dialogId)
        VoteAnswers.DumpDialogManagerNode(dialogId and tonumber(dialogId) or nil)
    end)
end
