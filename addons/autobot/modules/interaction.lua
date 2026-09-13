local interaction = {}

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local ffi_ok, ffi = pcall(require, 'ffi')
local injected_keys = {}

ashita.events.register('key_state', 'autobot_interaction_key_state_cb', function(e)
    if not ffi_ok or not e.data_raw then
        return
    end

    local now = os.clock()
    local state = ffi.cast('uint8_t*', e.data_raw)

    for scan_code, expires_at in pairs(injected_keys) do
        if now < expires_at then
            state[scan_code] = 0x80
        else
            injected_keys[scan_code] = nil
        end
    end
end)

local function hold_key(scan_code, seconds)
    if not ffi_ok then
        return false
    end

    injected_keys[scan_code] = os.clock() + (seconds or 0.15)
    return true
end

-------------------------------------------------
-- TARGET NPC
-------------------------------------------------
function interaction.target_npc(name)
    name = tostring(name or ''):lower():match('^%s*(.-)%s*$')
    if name == '' then
        return false
    end

    local memory = AshitaCore:GetMemoryManager()
    local entity = memory and memory:GetEntity()
    local target = memory and memory:GetTarget()

    if not entity or not target then
        return false
    end

    local best_index = -1
    local best_exact = false
    local best_distance = math.huge

    for index = 0, 2048 do
        local ok, entity_name = pcall(function()
            return entity:GetName(index)
        end)

        local normalized = ok and tostring(entity_name or ''):lower() or ''
        local exact = normalized == name
        local partial = normalized ~= '' and normalized:find(name, 1, true) ~= nil

        if exact or partial then
            local server_id = entity:GetServerId(index)
            local distance = tonumber(entity:GetDistance(index))

            if server_id and server_id ~= 0 and distance
            and (best_index < 0
                or (exact and not best_exact)
                or (exact == best_exact and distance < best_distance))
            then
                best_index = index
                best_exact = exact
                best_distance = distance
            end
        end
    end

    if best_index < 0 then
        print('[Interaction] Could not find NPC: ' .. name)
        return false
    end

    local ok = pcall(function()
        target:SetTarget(best_index, true)
    end)

    if not ok then
        local server_id = entity:GetServerId(best_index)
        ok = pcall(function()
            target:SetTarget(server_id, best_index, true)
        end)
    end

    if not ok then
        print('[Interaction] Could not target NPC: ' .. name)
        return false
    end

    print('[Interaction] Targeted: ' .. tostring(entity:GetName(best_index) or name))
    return true
end

-------------------------------------------------
-- KEY PRESS
-------------------------------------------------
function interaction.press_key(key)
    key = tostring(key or ''):lower()

    local keys = {
        enter = 0x1C,
        up = 0xC8,
        down = 0xD0,
        left = 0xCB,
        right = 0xCD,
        tab = 0x0F,
        f1 = 0x3B,
        f8 = 0x42,
        esc = 0x01,
        escape = 0x01,
    }

    if key ~= 'stab' and key ~= 'shifttab' and not keys[key] then
        print('[Interaction] Invalid key: ' .. key)
        return false
    end

    if key == 'stab' or key == 'shifttab' then
        if not hold_key(0x2A, 0.15) or not hold_key(0x0F, 0.15) then
            print('[Interaction] Could not inject key press.')
            return false
        end
    else
        if not hold_key(keys[key], 0.15) then
            print('[Interaction] Could not inject key press.')
            return false
        end
    end

    return true
end

return interaction
