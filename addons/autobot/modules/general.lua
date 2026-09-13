local general = {}
local warp_ring_sequence_id = 0
local interaction = require('modules.interaction')

-------------------------------------------------
-- HELPER
-------------------------------------------------
local function cmd(str)
    AshitaCore:GetChatManager():QueueCommand(1, str)
end

local function clean_command_name(value)
    value = tostring(value or ''):match('^%s*(.-)%s*$')
    value = value:gsub('%{([^{}]-)%}', '%1')
    value = value:gsub('%(([^()]-)%)', '%1')
    value = value:gsub('^"(.-)"$', '%1')
    return value:match('^%s*(.-)%s*$')
end

local function get_mount_name(resources, mount_id)
    local ok, name = pcall(function()
        return resources:GetString('mounts.names', mount_id)
    end)

    if not ok then
        return nil
    end

    name = clean_command_name(name)
    if name == ''
    or name:match('^%s*%-%-%s*$')
    or name:lower():match('^unknown')
    then
        return nil
    end

    return name
end

-------------------------------------------------
-- BASIC COMMANDS
-------------------------------------------------
function general.rest()        cmd('/heal') end
function general.join()        cmd('/join') end
function general.leave()       cmd('/pcmd leave') end
function general.disband()     cmd('/pcmd breakup') end
function general.mountup()     cmd('/mount "Crawler"') end
function general.mount(n)
    n = clean_command_name(n)
    if n == '' then
        return false
    end

    cmd('/mount "' .. n:gsub('"', '\\"') .. '"')
    return true
end
function general.dismount()    cmd('/dismount') end

function general.random_mount()
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    local resources = AshitaCore:GetResourceManager()
    local mounts = general.get_available_mounts()

    if not player or not resources then
        return false, 'Player mount data is unavailable.'
    end

    if #mounts == 0 then
        general.mountup()
        return true, 'Crawler'
    end

    local selected = mounts[math.random(1, #mounts)]
    if general.mount(selected) then
        return true, selected
    end

    general.mountup()
    return true, 'Crawler'
end

function general.get_available_mounts()
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    local resources = AshitaCore:GetResourceManager()
    local mounts = {}

    if not player or not resources then
        return mounts
    end

    for mount_id = 0, 38 do
        local name = get_mount_name(resources, mount_id)
        local ok_owned, owned = pcall(function()
            return player:HasKeyItem(3072 + mount_id)
        end)

        if name and ok_owned and (owned == true or owned == 1) then
            table.insert(mounts, name)
        end
    end

    return mounts
end

function general.invite(p)
    if p then cmd('/pcmd add ' .. p) end
end

function general.passleader(p)
    if p then cmd('/pcmd leader ' .. p) end
end

-------------------------------------------------
-- WARP RING
-------------------------------------------------
local function luashitacast_is_loaded()
    local ok_manager, manager = pcall(function()
        return AshitaCore:GetAddonManager()
    end)

    -- Older Ashita builds may not expose the addon manager to Lua. In that
    -- case favor suspending LAC; an unloaded addon will simply ignore it.
    if not ok_manager or not manager then
        return true
    end

    for _, name in ipairs({ 'luashitacast', 'LuAshitacast' }) do
        if type(manager.IsLoaded) == 'function' then
            local ok, loaded = pcall(function()
                return manager:IsLoaded(name)
            end)
            if ok and (loaded == true or loaded == 1) then
                return true
            end
        end

        for _, method in ipairs({ 'GetState', 'GetAddonState' }) do
            if type(manager[method]) == 'function' then
                local ok, state = pcall(function()
                    return manager[method](manager, name)
                end)
                if ok and tonumber(state) and tonumber(state) > 0 then
                    return true
                end
            end
        end
    end

    if type(manager.Count) == 'function' and type(manager.Get) == 'function' then
        local ok_count, count = pcall(function()
            return manager:Count()
        end)
        if ok_count and tonumber(count) then
            for index = 0, tonumber(count) - 1 do
                local ok_name, name = pcall(function()
                    return manager:Get(index)
                end)
                if ok_name and tostring(name or ''):lower() == 'luashitacast' then
                    return true
                end
            end
            return false
        end
    end

    -- Detection API exists but its usable methods differ from this build.
    return true
end

local function castbar_is_active()
    local castbar = nil

    local ok_global, global_castbar = pcall(function()
        if type(GetCastBarSafe) == 'function' then
            return GetCastBarSafe()
        end
    end)

    if ok_global and global_castbar then
        castbar = global_castbar
    end

    if not castbar then
        local ok_manager, manager_castbar = pcall(function()
            local memory = AshitaCore:GetMemoryManager()
            return memory and memory.GetCastBar and memory:GetCastBar() or nil
        end)

        if ok_manager then
            castbar = manager_castbar
        end
    end

    if not castbar then
        return false
    end

    local ok_active, active = pcall(function()
        return castbar:GetActive()
    end)
    if ok_active and (active == true or active == 1) then
        return true
    end

    local ok_percent, percent = pcall(function()
        return castbar:GetPercent()
    end)
    return ok_percent
        and tonumber(percent)
        and tonumber(percent) > 0
        and tonumber(percent) < 1
end

function general.usewarpring()
    warp_ring_sequence_id = warp_ring_sequence_id + 1
    local sequence_id = warp_ring_sequence_id
    local restore_lac = luashitacast_is_loaded()

    if restore_lac then
        cmd('/lac disable')
    end

    ashita.tasks.once(0.5, function()
        if sequence_id ~= warp_ring_sequence_id then
            return
        end

        cmd('/equip ring2 "Warp Ring"')

        ashita.tasks.once(10, function()
            if sequence_id ~= warp_ring_sequence_id then
                return
            end

            cmd('/item "Warp Ring" <me>')

            local used_at = os.clock()
            local activation_started = false
            local restored = false

            local function restore()
                if restored then
                    return
                end
                restored = true

                if restore_lac then
                    cmd('/lac enable')
                end
            end

            local function wait_for_completion()
                if sequence_id ~= warp_ring_sequence_id then
                    return
                end

                local active = castbar_is_active()
                if active then
                    activation_started = true
                elseif activation_started then
                    ashita.tasks.once(0.5, restore)
                    return
                end

                if (os.clock() - used_at) >= 20 then
                    restore()
                    return
                end

                ashita.tasks.once(0.2, wait_for_completion)
            end

            ashita.tasks.once(0.2, wait_for_completion)
        end)
    end)
end

-------------------------------------------------
-- CLEAR MENUS (ESC SPAM)
-------------------------------------------------
function general.clear(cb)
    local presses = 5

    local function press(i)
        if i > presses then
            if cb then cb() end
            return
        end

        interaction.press_key('escape')

        ashita.tasks.once(0.35, function()
            press(i + 1)
        end)
    end

    press(1)
end

-------------------------------------------------
-- TRADE SYSTEM (SAFE PORT)
-------------------------------------------------
function general.trade(name)
    name = clean_command_name(name)
    if name == '' then
        return false
    end

    general.clear(function()
        cmd('/target "' .. name:gsub('"', '\\"') .. '"')

        ashita.tasks.once(0.5, function()
            interaction.press_key('enter')

            ashita.tasks.once(0.4, function()
                interaction.press_key('up')

                ashita.tasks.once(0.25, function()
                    interaction.press_key('up')

                    ashita.tasks.once(0.25, function()
                        interaction.press_key('enter')
                    end)
                end)
            end)
        end)
    end)

    return true
end

function general.accept_trade()
    interaction.press_key('up')

    ashita.tasks.once(0.25, function()
        interaction.press_key('down')

        ashita.tasks.once(0.35, function()
            interaction.press_key('enter')
        end)
    end)

    return true
end

function general.cancel_trade()
    return interaction.press_key('escape')
end

function general.trade_all_gil()
    interaction.press_key('up')

    ashita.tasks.once(0.3, function()
        interaction.press_key('enter')

        ashita.tasks.once(0.3, function()
            local left_presses = 0

            local function press_left()
                if left_presses >= 10 then
                    ashita.tasks.once(0.3, function()
                        interaction.press_key('enter')

                        ashita.tasks.once(0.3, function()
                            interaction.press_key('down')

                            ashita.tasks.once(0.3, function()
                                interaction.press_key('enter')
                            end)
                        end)
                    end)
                    return
                end

                left_presses = left_presses + 1
                interaction.press_key('left')
                ashita.tasks.once(0.2, press_left)
            end

            press_left()
        end)
    end)

    return true
end

return general
