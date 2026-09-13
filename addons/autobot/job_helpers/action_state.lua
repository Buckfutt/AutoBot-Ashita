local action_state = {}

local busy_until = 0
local SETTLE_SECONDS = 1.5

local function now()
    if ashita and ashita.time and ashita.time.get_tick64 then
        return ashita.time.get_tick64() / 1000
    end
    return os.clock()
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

    local ok_percent, percent = pcall(function()
        return castbar:GetPercent()
    end)

    if ok_percent and tonumber(percent) and tonumber(percent) > 0 and tonumber(percent) < 1 then
        return true
    end

    local ok_active, active = pcall(function()
        return castbar:GetActive()
    end)

    return ok_active and (active == true or active == 1)
end

function action_state.is_busy()
    local current_time = now()

    if castbar_is_active() then
        busy_until = current_time + SETTLE_SECONDS
        return true
    end

    return current_time < busy_until
end

action_state.actions_blocked = action_state.is_busy

return action_state
