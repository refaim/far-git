local Guids = {
    MenuMacro = "C72C2C5A-44D6-4A3D-B87F-37865FE4700D",
    PlugMenu = "2183BA45-30A6-47F7-95A6-3B916B25C68A",
    BranchesList = win.Uuid("3AED4D7C-A591-4121-8B01-73CB5DAF27A1"),
    DialogNewBranch = win.Uuid("190657CE-902C-499B-8A37-1933C03824E1"),
    DialogDelBranch = win.Uuid("844DF9FC-986F-496B-99A1-239E365F6748"),
}

function table.copyShallow(source)
    local result = {}
    for k, v in pairs(source) do
        result[k] = v
    end
    return result
end

function table.get(source, key, default)
    local result = source[key]
    if result == nil then result = default end
    return result
end

function table.setdefault(source, key, default)
    if source[key] == nil then source[key] = default end
    return source[key]
end

function string.startswith(str, prefix)
     return string.sub(str, 1, string.len(prefix)) == prefix
end

function string.contains(str, substr)
    return str:find(substr) ~= nil
end

function string.strip(str, chars)
    if not chars then chars = {"%s"} end
    local match = string.format("[%s]", string.join(chars, ""))
    local pattern = string.format("^%s*(.*)%s*$", match, match)
    return (str:gsub(pattern, "%1"))
end

function string.padLeft(str, char, len)
    local result = str
    local padLen = len - string.len(str)
    if padLen > 0 then result = string.rep(char, padLen) .. result end
    return result
end

function string.padRight(str, char, len)
    local result = str
    local padLen = len - string.len(str)
    if padLen > 0 then result = result .. string.rep(char, padLen) end
    return result
end

function string.split(str, separator)
    local fields = {}
    local pattern = string.format("([^%s]+)", separator)
    str:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
end

function string.join(data, glue)
    if not glue then glue = "\n" end
    return table.concat(data, glue)
end

function string.extract(str, pattern) -- TODO при наличии регулярок это не нужно
    return (str:gsub(pattern, "%1"))
end

local function runCommand(cmdString, workingDirectory)
    local process = io.popen(string.format('CD /D "%s" && %s 2>&1', workingDirectory, cmdString))
    local result = process:read("*a")
    process:close()
    return result
end

local function branchPropsLessThan(lhs, rhs)
    local lhas = lhs["has_local"]
    local rhas = rhs["has_local"]
    if lhas and rhas then return lhs["branch_id_local"] < rhs["branch_id_local"]
    elseif lhas and not rhas then return true
    elseif not lhas and rhas then return false
    end
    return lhs["branch_id_origin"] < rhs["branch_id_origin"]
end

local function listBranches()
    local curdir = panel.GetPanelDirectory(nil, 1).Name
    local menuItems = {}
    local activeIdx = 1
    local listObsolete = true
    repeat
        if listObsolete then
            local output = runCommand("git branch --list --all -vv", curdir)
            if string.contains(output, "Not a git repository") then return end

            local branchesPropsDict = {}
            for _, line in ipairs(string.split(output, "\n")) do
                if not string.contains(line, "HEAD") then -- TODO ZALEPA
                    -- TODO убрать всю эту унылую поеботу с паттернами и заменить на regex.* из luafar
                    line = string.strip(line)
                    local isCurrent = string.startswith(line, "*")
                    line = string.strip(line, {"%s", "%*"})

                    local localBranchId = nil
                    local originId = nil
                    local hasLocal = false
                    local hasRemote = true
                    if string.startswith(line, "remotes/") then
                        localBranchId = string.extract(line, "^remotes/[^/]+/(%S+).*$")
                        originId = string.extract(line, "^remotes/([^/]+)/.*$")
                    else
                        localBranchId = string.extract(line, "^(%S+).*$")
                        local commitId = string.extract(line, "^%S+%s+([%a%d]+).*$")
                        local textBlock = string.strip(string.sub(line, string.find(line, commitId) + string.len(commitId)))
                        -- TODO тут пишется информация о ahead/behind, неплохо бы её выводить
                        -- TODO а ещё тут бывает gone, когда на remote ветки уже нет
                        if string.startswith(textBlock, "[") then
                            originId = string.extract(textBlock, "^%[([^/]+)[^%]]+%].*")
                        else
                            hasRemote = false
                        end
                        hasLocal = true
                    end
                    if originId == nil then originId = "origin" end
                    -- TODO тут баг, если локальная ветка foo трекает origin/bar, то у меня в списке отобразится origin/foo
                    -- TODO а ещё, если локальная ветка ничего не трекает, но совпадает именем с удаленной веткой, то отобразится, как будто трекает
                    local originBranchId = string.format("%s/%s", originId, localBranchId)
                    local remoteBranchId = string.format("remotes/%s", originBranchId)

                    local storage = table.setdefault(branchesPropsDict, originBranchId, {})
                    table.setdefault(storage, "origin_id", originId)
                    table.setdefault(storage, "branch_id_local", localBranchId)
                    table.setdefault(storage, "branch_id_remote", remoteBranchId)
                    table.setdefault(storage, "branch_id_origin", originBranchId)
                    storage["current"] = isCurrent or table.get(storage, "current", false)
                    storage["has_local"] = hasLocal or table.get(storage, "has_local", false)
                    storage["has_remote"] = hasRemote and table.get(storage, "has_remote", true) -- TODO кривизна :(
                    branchesPropsDict[originBranchId] = storage
                end
            end

            local branchesPropsList = {}
            for _, props in pairs(branchesPropsDict) do
                table.insert(branchesPropsList, props)
            end
            table.sort(branchesPropsList, branchPropsLessThan)

            local columnsInfo = {}
            table.insert(columnsInfo, function(props) if props["has_local"] then return props["branch_id_local"] else return "" end end)
            table.insert(columnsInfo, function(props) if props["has_remote"] then return props["branch_id_origin"] else return "" end end)

            local columnsWidths = {}
            for _, props in pairs(branchesPropsList) do
                for col, lambda in ipairs(columnsInfo) do
                    columnsWidths[col] = math.max(table.get(columnsWidths, col, 0), string.len(lambda(props)))
                end
            end

            menuItems = {}
            for i, props in ipairs(branchesPropsList) do
                local itemText = ""
                for col, lambda in ipairs(columnsInfo) do
                    if col > 1 then itemText = itemText .. " │ " end
                    itemText = itemText .. string.padRight(lambda(props), " ", columnsWidths[col])
                end
                if props["current"] then activeIdx = i end

                local itemProps = {}
                itemProps["origin_id"] = props["origin_id"]
                itemProps["branch_id_local"] = props["branch_id_local"]
                itemProps["branch_id_origin"] = props["branch_id_origin"]
                itemProps["text"] = itemText
                itemProps["checked"] = props["current"]
                table.insert(menuItems, itemProps)
            end

            listObsolete = false
        end

        local breakKeys = {
            {BreakKey="INSERT"},
            {BreakKey="F8"}, {BreakKey="DELETE"},
            {BreakKey="T"},
            {BreakKey="P"},
        }
        -- TODO Help
        local menuParams = {Title="Branches", Bottom="Enter, Delete, Insert, P, T", SelectIndex=activeIdx, Id=Guids.BranchesList, Flags=bit64.bor(far.Flags.FMENU_SHOWAMPERSAND, far.Flags.FMENU_WRAPMODE)}
        local result, pos = far.Menu(menuParams, menuItems, breakKeys)
        if not result then break end

        local selItem = result
        local output = nil
        local success = false
        if result.BreakKey ~= nil then
            selItem = menuItems[pos]
            if result.BreakKey == "F8" or result.BreakKey == "DELETE" then
                output = runCommand(string.format("git branch -d %s", selItem.branch_id_local), curdir)
                success = string.contains(output, "Deleted branch")
                if not success and string.contains(output, "is not fully merged") then
                    output = nil
                    local expDelString = "DELETE"
                    local gotDelString = far.InputBox(Guids.DialogDelBranch, string.format("Delete branch %s", selItem.branch_id_local), string.format("Branch is not fully merged. Type %s to delete it.", expDelString))
                    if expDelString == gotDelString then
                        output = runCommand(string.format("git branch -D %s", selItem.branch_id_local), curdir)
                        success = string.contains(output, "Deleted branch")
                    end
                end
                listObsolete = true
            elseif result.BreakKey == "INSERT" then
                local branchId = far.InputBox(Guids.DialogNewBranch, "Create branch", "Enter branch name")
                if branchId ~= nil and string.len(branchId) > 0 then
                    output = runCommand(string.format("git checkout -b %s", branchId), curdir)
                    success = string.contains(output, "Switched to")
                    listObsolete = true
                end
            elseif result.BreakKey == "T" then
                output = runCommand(string.format("git branch -u %s %s", selItem["branch_id_origin"], selItem["branch_id_local"]), curdir)
                success = string.contains(output, "set up to track")
                listObsolete = true
            elseif result.BreakKey == "P" then
                -- TODO если уже есть remote, то тут мы его перетрём типа
                output = runCommand(string.format("git push -u %s %s", selItem["origin_id"], selItem["branch_id_local"]), curdir)
                success = false
                listObsolete = true
            end
        elseif selItem.branch_id_local then
            output = runCommand(string.format("git checkout %s", selItem.branch_id_local), curdir)
            success = string.contains(output, "Switched to") or string.contains(output, "Already on")
            listObsolete = true
        end

        if output and not success then
            far.Message(string.strip(output), "Output", ";Ok", "l")
        end
    until false
end

Macro {
    action=listBranches;
    area="Common";
    key="CtrlM";
    description="Git Branch Manager";
    uid=Guids.MenuMacro;
}

MenuItem {
    action=listBranches;
    menu="Plugins";
    area="Shell Editor Viewer Dialog Menu";
    description="Git Branch Manager";
    guid=Guids.PlugMenu;
    text="Git Branch Manager";
}
