local items = {}
local shared_state = require('modules.state')

local config = nil
local save_settings = nil
local last_use_attempt = 0
local last_echo = 0
local last_status = {
    enabled = false,
    food_name = '',
    has_food = false,
    last_attempt = 0,
    next_attempt = 0,
}

local FOOD_BUFF_ID = 251

local function trim(value)
    return (tostring(value or ''):match('^%s*(.-)%s*$')) or ''
end

local function echo(message)
    AshitaCore:GetChatManager():QueueCommand(1, '/echo [AutoBot] Items: ' .. tostring(message))
end

local function echo_throttled(message)
    if shared_state.debug ~= true then
        return
    end

    if (os.clock() - last_echo) < 3 then
        return
    end

    last_echo = os.clock()
    echo(message)
end

local function queue_item(name)
    name = trim(name):gsub('"', '')
    if name == '' then
        return false
    end

    AshitaCore:GetChatManager():QueueCommand(1, string.format('/item "%s" <me>', name))
    return true
end

local function ensure()
    if not config then
        return nil
    end

    config.items = config.items or {}
    config.items.food = config.items.food or {}

    local food = config.items.food
    food.enabled = food.enabled == true
    food.name = trim(food.name)
    food.retry_delay = tonumber(food.retry_delay) or 15

    if food.retry_delay < 5 then food.retry_delay = 5 end
    if food.retry_delay > 120 then food.retry_delay = 120 end

    return config.items
end

local function get_player()
    local ok, player = pcall(function()
        return AshitaCore:GetMemoryManager():GetPlayer()
    end)

    return ok and player or nil
end

local function is_zoning(player)
    if not player or not player.GetIsZoning then
        return false
    end

    local ok, zoning = pcall(function()
        return player:GetIsZoning()
    end)

    return ok and zoning and zoning ~= 0
end

local function player_hp_percent()
    local ok, party = pcall(function()
        return AshitaCore:GetMemoryManager():GetParty()
    end)

    if not ok or not party or not party.GetMemberHPPercent then
        return 100
    end

    local ok_hp, hp = pcall(function()
        return party:GetMemberHPPercent(0)
    end)

    return ok_hp and tonumber(hp) or 100
end

local function has_buff(buff_id)
    local player = get_player()
    if not player then
        return false
    end

    local function check_list(method)
        if not player[method] then
            return false
        end

        local ok, buffs = pcall(function()
            return player[method](player)
        end)

        if not ok or not buffs then
            return false
        end

        for i = 0, 63 do
            local ok_buff, buff = pcall(function()
                return buffs[i]
            end)

            if ok_buff and tonumber(buff) == tonumber(buff_id) then
                return true
            end
        end

        for _, buff in pairs(buffs) do
            if tonumber(buff) == tonumber(buff_id) then
                return true
            end
        end

        return false
    end

    return check_list('GetBuffs') or check_list('GetStatusIcons')
end

function items.set_config(cfg, save)
    config = cfg
    save_settings = save
    ensure()
end

function items.tick()
    local cfg = ensure()
    if not cfg or not config.modules or config.modules.items ~= true then
        return
    end

    local food = cfg.food
    local has_food = has_buff(FOOD_BUFF_ID)
    local now = os.clock()

    last_status.enabled = food.enabled == true
    last_status.food_name = food.name
    last_status.has_food = has_food
    last_status.last_attempt = last_use_attempt
    last_status.next_attempt = math.max(0, (last_use_attempt + food.retry_delay) - now)

    if not food.enabled then
        return
    end

    if food.name == '' then
        echo_throttled('Set a food item first.')
        return
    end

    if has_food then
        return
    end

    local player = get_player()
    if not player or is_zoning(player) or player_hp_percent() <= 0 then
        return
    end

    if (now - last_use_attempt) < food.retry_delay then
        return
    end

    if queue_item(food.name) then
        last_use_attempt = now
        last_status.last_attempt = last_use_attempt
        last_status.next_attempt = food.retry_delay
    end
end

function items.use_food()
    local cfg = ensure()
    if not cfg or cfg.food.name == '' then
        return false, 'Set a food item first.'
    end

    last_use_attempt = os.clock()
    return queue_item(cfg.food.name), nil
end

function items.command(sub, args)
    local cfg = ensure()
    if not cfg then
        return false, 'Items module is not configured.'
    end

    args = args or {}
    sub = tostring(sub or ''):lower()

    if sub == 'on' or sub == 'start' or sub == 'enable' then
        cfg.food.enabled = true
        if save_settings then save_settings(config) end
        echo('Food: ON')
        return true
    end

    if sub == 'off' or sub == 'stop' or sub == 'disable' then
        cfg.food.enabled = false
        if save_settings then save_settings(config) end
        echo('Food: OFF')
        return true
    end

    if sub == 'toggle' then
        cfg.food.enabled = not cfg.food.enabled
        if save_settings then save_settings(config) end
        echo('Food: ' .. (cfg.food.enabled and 'ON' or 'OFF'))
        return true
    end

    if sub == 'food' or sub == 'set' or sub == 'name' then
        local name = trim(table.concat(args, ' '))
        if name == '' then
            return false, 'Usage: /ab item food <item name>'
        end
        cfg.food.name = name
        if save_settings then save_settings(config) end
        echo('Food item: ' .. name)
        return true
    end

    if sub == 'delay' or sub == 'retry' then
        local seconds = tonumber(args[1])
        if not seconds then
            return false, 'Usage: /ab item delay <seconds>'
        end
        cfg.food.retry_delay = math.max(5, math.min(120, seconds))
        if save_settings then save_settings(config) end
        echo('Food retry delay: ' .. tostring(cfg.food.retry_delay) .. 's')
        return true
    end

    if sub == 'use' or sub == 'eat' then
        local ok, err = items.use_food()
        if not ok and err then
            return false, err
        end
        return true
    end

    return false, 'Usage: /ab item on|off|toggle|food <item>|delay <seconds>|use'
end

function items.get_status()
    local cfg = ensure()
    if cfg then
        last_status.enabled = cfg.food.enabled == true
        last_status.food_name = cfg.food.name
        last_status.has_food = has_buff(FOOD_BUFF_ID)
        last_status.next_attempt = math.max(0, (last_use_attempt + cfg.food.retry_delay) - os.clock())
    end

    return last_status
end

return items
