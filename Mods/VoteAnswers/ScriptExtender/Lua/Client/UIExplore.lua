-- Diagnostic tool: dumps the client-side Noesis UI visual tree so we can
-- find the real element/viewmodel names behind dialogue reply buttons.
--
-- Confirmed real API (bg3se, client-side only):
--   Ext.UI.GetRoot() -> root UIObject
--   uiObject:Find(name) -> child UIObject by name
--   uiObject:VisualChild(index) -> walk the visual tree
--
-- What is NOT yet confirmed is the specific element name(s) for the
-- dialogue reply list/buttons, or the property names on whatever
-- viewmodel is bound to them (DataContext). This has to be found by
-- running the dump below while a real dialogue with multiple player
-- lines is open, then reading the console output.
--
-- Usage (from the in-game Script Extender console, or bound to a
-- console command -- see VoteAnswers.RegisterDumpCommand below):
--   VoteAnswers.DumpUITree()            -- dumps from the UI root
--   VoteAnswers.DumpUITree("Dialog")    -- dumps starting at Find("Dialog"), if that name exists

VoteAnswers = VoteAnswers or {}

local DEFAULT_MAX_DEPTH = 6

local function safeGetType(node)
    local ok, t = pcall(function() return node:GetTypeName() end)
    return ok and t or "?"
end

local function safeGetName(node)
    local ok, n = pcall(function() return node.Name end)
    return ok and n or nil
end

local function dumpNode(node, depth, maxDepth, out)
    if node == nil or depth > maxDepth then
        return
    end
    local indent = string.rep("  ", depth)
    local name = safeGetName(node)
    table.insert(out, string.format("%s- %s%s", indent, safeGetType(node), name and (" (" .. name .. ")") or ""))

    -- Walk visual children; VisualChild(i) throws/returns nil past the end,
    -- so stop at the first failure instead of requiring a known count.
    local i = 0
    while true do
        local ok, child = pcall(function() return node:VisualChild(i) end)
        if not ok or child == nil then
            break
        end
        dumpNode(child, depth + 1, maxDepth, out)
        i = i + 1
    end
end

--- Dumps the UI visual tree to the SE console/log. Run this while the
--- dialogue window you care about is open on screen.
--- @param findName string|nil optional Find() name to start from instead of the root
--- @param maxDepth number|nil how many levels deep to walk (default 6)
function VoteAnswers.DumpUITree(findName, maxDepth)
    maxDepth = maxDepth or DEFAULT_MAX_DEPTH
    local root = Ext.UI.GetRoot()
    if not root then
        Ext.Utils.Print("[VoteAnswers] Ext.UI.GetRoot() returned nothing")
        return
    end

    local startNode = root
    if findName then
        local ok, found = pcall(function() return root:Find(findName) end)
        if not ok or found == nil then
            Ext.Utils.Print("[VoteAnswers] Find(\"" .. findName .. "\") did not match anything")
            return
        end
        startNode = found
    end

    local out = {}
    dumpNode(startNode, 0, maxDepth, out)
    Ext.Utils.Print("[VoteAnswers] UI tree dump (" .. #out .. " nodes):")
    for _, line in ipairs(out) do
        Ext.Utils.Print(line)
    end
end

-- Convenience console command: `!votedump [findName] [maxDepth]`
-- TODO: verify Ext.RegisterConsoleCommand's exact signature against the
-- bg3se version in use; this is the documented pattern but the exact
-- argument types/behavior should be checked once testing in-game.
if Ext.RegisterConsoleCommand then
    Ext.RegisterConsoleCommand("votedump", function(_, findName, maxDepth)
        VoteAnswers.DumpUITree(findName, maxDepth and tonumber(maxDepth) or nil)
    end)
end
