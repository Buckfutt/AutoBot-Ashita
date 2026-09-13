local autows = {}
local shared_state = require('modules.state')
local skillchains_ok, skillchains = pcall(require, 'modules.skillchains')

if not skillchains_ok then
    skillchains = nil
end

local settings = nil
local last_ws_time = 0
local last_status_echo = 0
local last_block_reason = 'Idle'
local last_skillchain_error = ''
local MELEE_WS_RANGE = 4.7
-- Wait until the reliable skillchain window opens. Each newly observed WS
-- updates last_action, so overlapping players naturally restart this delay.
local SKILLCHAIN_STABILIZE_SECONDS = 3.2

local ranged_weaponskills = {
    ['flaming arrow'] = true, ['piercing arrow'] = true,
    ['dulling arrow'] = true, ['sidewinder'] = true,
    ['blast arrow'] = true, ['arching arrow'] = true,
    ['empyreal arrow'] = true, ['namas arrow'] = true,
    ['refulgent arrow'] = true, ["jishnu's radiance"] = true,
    ['apex arrow'] = true,
    ['hot shot'] = true, ['split shot'] = true, ['sniper shot'] = true,
    ['slug shot'] = true, ['blast shot'] = true, ['heavy shot'] = true,
    ['detonator'] = true, ['coronach'] = true, ['trueflight'] = true,
    ['leaden salute'] = true, ['numbing shot'] = true,
    ['wildfire'] = true, ['last stand'] = true,
}

local AFTERMATH_LV1 = 270
local AFTERMATH_LV2 = 271
local AFTERMATH_LV3 = 272
local AFTERMATH_GENERIC = 273
local AMNESIA = 16

local function cmd(str)
    AshitaCore:GetChatManager():QueueCommand(1, str)
end

local function now()
    return os.clock()
end

local function trim(value)
    return (tostring(value or ''):match("^%s*(.-)%s*$")) or ''
end

local function split_csv(value)
    local results = {}

    for part in tostring(value or ''):gmatch('[^,]+') do
        local item = trim(part)
        if item ~= '' then
            table.insert(results, item)
        end
    end

    return results
end

local function parse_level_priority(value)
    local results = {}

    for _, item in ipairs(split_csv(value)) do
        local level = tonumber(item)
        if level and level >= 1 and level <= 4 then
            table.insert(results, math.floor(level))
        end
    end

    if #results == 0 then
        results = { 4, 3, 2, 1 }
    end

    return results
end

local function parse_blacklist(value)
    local results = {}

    for _, item in ipairs(split_csv(value)) do
        results[item:lower()] = true
    end

    return results
end

local function echo_throttled(message)
    if shared_state.debug ~= true then
        return
    end

    if (now() - last_status_echo) < 3 then
        return
    end

    last_status_echo = now()
    cmd('/echo [AutoBot] AutoWS: ' .. tostring(message))
end

local function note_skillchain_error(err)
    last_skillchain_error = tostring(err or 'unknown')
    echo_throttled('Skillchain helper paused: ' .. last_skillchain_error)
end

local function get_player_index()
    local party = AshitaCore:GetMemoryManager():GetParty()
    if not party then
        return -1
    end

    local ok, index = pcall(function()
        return party:GetMemberTargetIndex(0)
    end)

    return ok and index or -1
end

local function get_player_status()
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if player then
        local ok, status = pcall(function()
            return player:GetStatus()
        end)

        if ok and status ~= nil then
            return status
        end
    end

    local entity = AshitaCore:GetMemoryManager():GetEntity()
    local index = get_player_index()
    if entity and index and index > 0 then
        local ok, status = pcall(function()
            return entity:GetStatus(index)
        end)

        if ok and status ~= nil then
            return status
        end
    end

    return 0
end

local function player_is_engaged()
    local status = get_player_status()

    return status == 1
end

local function is_subtarget_active()
    local target = AshitaCore:GetMemoryManager():GetTarget()

    if not target then
        return false
    end

    local ok, active = pcall(function()
        return target:GetIsSubTargetActive()
    end)

    return ok and active == 1
end

local function get_target_index()
    local target = AshitaCore:GetMemoryManager():GetTarget()
    local entity = AshitaCore:GetMemoryManager():GetEntity()
    local player_index = get_player_index()

    local function valid(index)
        return index and tonumber(index) and tonumber(index) > 0 and tonumber(index) ~= player_index
    end

    if target then
        local ok_active, active = pcall(function()
            return target:GetIsSubTargetActive()
        end)

        local slots = {}
        if ok_active and active == 1 then
            table.insert(slots, 1)
        end
        table.insert(slots, 0)
        table.insert(slots, 1)

        for _, slot in ipairs(slots) do
            local ok, index = pcall(function()
                return target:GetTargetIndex(slot)
            end)

            if ok and valid(index) then
                return index
            end
        end

        for _, method in ipairs({ 'GetFocusTargetIndex', 'GetLastTargetIndex' }) do
            if target[method] then
                local ok, index = pcall(function()
                    return target[method](target)
                end)

                if ok and valid(index) then
                    return index
                end
            end
        end
    end

    if entity and player_index > 0 then
        local ok, index = pcall(function()
            return entity:GetTargetIndex(player_index)
        end)

        if ok and valid(index) then
            return index
        end
    end

    return -1
end

local function has_valid_target(target_index)
    return target_index and target_index > 0 and target_index ~= get_player_index()
end

local function get_tp()
    local party = AshitaCore:GetMemoryManager():GetParty()
    if not party then
        return 0
    end

    local ok, tp = pcall(function()
        return party:GetMemberTP(0)
    end)

    return ok and tonumber(tp) or 0
end

local function has_buff(buff_id)
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    local party = AshitaCore:GetMemoryManager():GetParty()
    local wanted = tonumber(buff_id)

    local function check_buffs(buffs)
        if not buffs then
            return false
        end

        for i = 0, 63 do
            local ok_buff, buff = pcall(function()
                return buffs[i]
            end)

            if ok_buff and tonumber(buff) == wanted then
                return true
            end
        end

        for i = 1, 64 do
            local ok_buff, buff = pcall(function()
                return buffs[i]
            end)

            if ok_buff and tonumber(buff) == wanted then
                return true
            end
        end

        local found = false
        local ok_pairs = pcall(function()
            for _, buff in pairs(buffs) do
                if tonumber(buff) == wanted then
                    found = true
                    break
                end
            end
        end)

        return ok_pairs and found
    end

    local function check_player_method(method)
        if not player then
            return false
        end

        local ok, buffs = pcall(function()
            if not player[method] then
                return nil
            end

            return player[method](player)
        end)

        return ok and check_buffs(buffs)
    end

    local function check_party_method(method)
        if not party then
            return false
        end

        local ok, buffs = pcall(function()
            if not party[method] then
                return nil
            end

            return party[method](party, 0)
        end)

        return ok and check_buffs(buffs)
    end

    return check_player_method('GetBuffs')
        or check_player_method('GetStatusIcons')
        or check_party_method('GetMemberBuffs')
        or check_party_method('GetMemberStatusIcons')
end

local function has_aftermath_buff(tp_target)
    local required_ids
    tp_target = tonumber(tp_target) or 1000

    if tp_target >= 3000 then
        required_ids = { AFTERMATH_LV3, AFTERMATH_GENERIC }
    elseif tp_target >= 2000 then
        required_ids = { AFTERMATH_LV2, AFTERMATH_LV3, AFTERMATH_GENERIC }
    else
        required_ids = {
            AFTERMATH_LV1,
            AFTERMATH_LV2,
            AFTERMATH_LV3,
            AFTERMATH_GENERIC,
        }
    end

    for _, buff_id in ipairs(required_ids) do
        if has_buff(buff_id) then
            return true, buff_id
        end
    end

    return false, 0
end

local function get_config()
    if not settings then
        return nil
    end

    settings.autows = settings.autows or {}
    local cfg = settings.autows

    cfg.enabled = cfg.enabled == true
    cfg.weaponskill = trim(cfg.weaponskill)
    cfg.tp_amount = tonumber(cfg.tp_amount) or 1000
    cfg.aftermath_tp_amount = tonumber(cfg.aftermath_tp_amount) or 3000
    cfg.cooldown = tonumber(cfg.cooldown) or 3.0
    if cfg.use_aftermath == nil and cfg.use_am3 ~= nil then
        cfg.use_aftermath = cfg.use_am3
    end
    cfg.use_aftermath = cfg.use_aftermath ~= false
    cfg.use_am3 = nil
    cfg.skillchains_enabled = cfg.skillchains_enabled ~= false
    cfg.show_skillchain_window = cfg.show_skillchain_window ~= false
    cfg.open_skillchains = cfg.open_skillchains == true
    cfg.close_skillchains = cfg.close_skillchains == true
    cfg.open_weaponskill = trim(cfg.open_weaponskill)
    cfg.open_tp_amount = tonumber(cfg.open_tp_amount) or 1000
    cfg.close_tp_amount = tonumber(cfg.close_tp_amount) or 1000
    cfg.close_window_minimum = tonumber(cfg.close_window_minimum) or 1.0
    cfg.level_priority = trim(cfg.level_priority)
    if cfg.level_priority == '' then
        cfg.level_priority = '4,3,2,1'
    end
    cfg.chain_priority = trim(cfg.chain_priority)
    cfg.close_ws_priority = trim(cfg.close_ws_priority)
    cfg.blacklist = trim(cfg.blacklist)

    if cfg.tp_amount < 1000 then cfg.tp_amount = 1000 end
    if cfg.tp_amount > 3000 then cfg.tp_amount = 3000 end
    if cfg.aftermath_tp_amount < 1000 then cfg.aftermath_tp_amount = 1000 end
    if cfg.aftermath_tp_amount > 3000 then cfg.aftermath_tp_amount = 3000 end
    if cfg.open_tp_amount < 1000 then cfg.open_tp_amount = 1000 end
    if cfg.open_tp_amount > 3000 then cfg.open_tp_amount = 3000 end
    if cfg.close_tp_amount < 1000 then cfg.close_tp_amount = 1000 end
    if cfg.close_tp_amount > 3000 then cfg.close_tp_amount = 3000 end
    if cfg.close_window_minimum < 0 then cfg.close_window_minimum = 0 end
    if cfg.close_window_minimum > 10 then cfg.close_window_minimum = 10 end
    if cfg.cooldown < 1.5 then cfg.cooldown = 1.5 end
    if cfg.cooldown > 15 then cfg.cooldown = 15 end

    return cfg
end

local function get_closers(cfg)
    if not cfg or not cfg.skillchains_enabled or not skillchains then
        return {}
    end

    local ok, result = pcall(function()
        return skillchains.GetClosers({
            level_priority = parse_level_priority(cfg.level_priority),
            preferred_chain = cfg.chain_priority,
            preferred_ws = cfg.close_ws_priority,
            blacklist = parse_blacklist(cfg.blacklist),
        })
    end)

    if not ok then
        note_skillchain_error(result)
        return {}
    end

    return result or {}
end

local function get_current_skillchain_window(cfg)
    if not cfg or not cfg.skillchains_enabled or not skillchains then
        return nil
    end

    local ok, result = pcall(function()
        return skillchains.GetCurrentWindow()
    end)

    if not ok then
        note_skillchain_error(result)
        return nil
    end

    return result
end

local function handle_skillchain_packet(e)
    if not skillchains then
        return
    end

    local ok, err = pcall(function()
        skillchains.HandlePacket(e)
    end)

    if not ok then
        note_skillchain_error(err)
    end
end

local function get_closers_for_target(cfg)
    return get_closers(cfg)
end

local function fire_weaponskill(name, target_index)
    if is_subtarget_active() then
        last_block_reason = 'Subtarget active'
        return false
    end

    if not has_valid_target(target_index) then
        last_block_reason = 'No valid WS target'
        return false
    end

    local normalized_name = trim(name):lower()
    if not ranged_weaponskills[normalized_name] then
        local entity = AshitaCore:GetMemoryManager():GetEntity()
        local ok, distance_squared = pcall(function()
            return entity and entity:GetDistance(target_index)
        end)
        local distance = ok and distance_squared and math.sqrt(distance_squared) or nil

        if not distance then
            last_block_reason = 'Could not determine WS range'
            return false
        end

        if distance > MELEE_WS_RANGE then
            last_block_reason = string.format(
                'Melee WS out of range: %.1f/%.1f',
                distance,
                MELEE_WS_RANGE
            )
            return false
        end
    end

    cmd(string.format('/ws "%s" <t>', name))
    last_ws_time = now()
    return true
end

function autows.set_settings(cfg)
    settings = cfg
    get_config()
end

function autows.handle_packet(e)
    if e and e.id == 0x0028 then
        handle_skillchain_packet(e)
    end
end

function autows.tick()
    local cfg = get_config()
    if not cfg or not cfg.enabled then
        last_block_reason = 'Disabled'
        return
    end

    if shared_state.pull_in_progress == true
    or shared_state.pull_completed == true
    then
        last_block_reason = shared_state.pull_completed
            and 'Waiting for post-pull engagement'
            or 'Pull in progress'
        return
    end

    if not settings.modules or settings.modules.autows ~= true then
        last_block_reason = 'Module disabled'
        return
    end

    if not player_is_engaged() then
        last_block_reason = 'Not engaged: ' .. tostring(get_player_status())
        return
    end

    if is_subtarget_active() then
        last_block_reason = 'Subtarget active'
        return
    end

    if has_buff(AMNESIA) then
        last_block_reason = 'Amnesia'
        return
    end

    local target_index = get_target_index()
    local target_valid = has_valid_target(target_index)

    local current_time = now()
    if (current_time - last_ws_time) < cfg.cooldown then
        last_block_reason = 'Cooldown'
        return
    end

    local tp = get_tp()
    local detected_aftermath = has_aftermath_buff(cfg.aftermath_tp_amount)
    local has_aftermath = cfg.use_aftermath and detected_aftermath
    local threshold = (cfg.use_aftermath and not has_aftermath) and cfg.aftermath_tp_amount or cfg.tp_amount

    if cfg.use_aftermath and not has_aftermath then
        if cfg.weaponskill == '' then
            last_block_reason = 'No weaponskill'
            echo_throttled('Set a weaponskill first.')
            return
        end

        if tp >= threshold then
            last_block_reason = target_valid and 'Firing Aftermath WS' or 'Firing Aftermath WS with <t>'
            fire_weaponskill(cfg.weaponskill, target_index)
        else
            last_block_reason = 'Waiting aftermath TP: ' .. tostring(tp) .. '/' .. tostring(threshold)
        end

        return
    end

    if target_valid and cfg.skillchains_enabled and cfg.close_skillchains then
        local active_window = get_current_skillchain_window(cfg)

        -- Multiple players can weaponskill nearly simultaneously. The
        -- skillchain helper updates to the newest packet, but firing in the
        -- small gap between packets can close against the superseded opener.
        -- Require a brief quiet period, then recalculate from the latest WS.
        if active_window
        and active_window.last_action
        and active_window.last_action.targetIndex == active_window.target_index
        then
            local action_age = current_time - (tonumber(active_window.last_action.time) or 0)
            if action_age < SKILLCHAIN_STABILIZE_SECONDS then
                last_block_reason = string.format(
                    'Waiting for WS sequence to settle: %.2fs',
                    math.max(0, SKILLCHAIN_STABILIZE_SECONDS - action_age)
                )
                return
            end
        end

        local closers = get_closers_for_target(cfg)
        local closer = nil

        for _, option in ipairs(closers) do
            if option.open
            and option.time_remaining > cfg.close_window_minimum
            and tp >= cfg.close_tp_amount
            then
                closer = option
                break
            end
        end

        if closer then
            last_block_reason = 'Firing closer: ' .. tostring(closer.weaponskill)
                .. ' -> ' .. tostring(closer.skillchain)
            fire_weaponskill(closer.weaponskill, target_index)
            return
        end

        -- Do not fall through to the normal AutoWS while a chain window is
        -- active. That weaponskill may create a level excluded by the user's
        -- level allow-list.
        if active_window then
            last_block_reason = 'Waiting for an allowed skillchain closer'
            return
        end
    end

    if target_valid and cfg.skillchains_enabled and cfg.open_skillchains then
        local window = get_current_skillchain_window(cfg)
        local opener = cfg.open_weaponskill ~= '' and cfg.open_weaponskill or cfg.weaponskill

        if not window and opener ~= '' and tp >= cfg.open_tp_amount then
            last_block_reason = 'Firing opener'
            fire_weaponskill(opener, target_index)
            return
        end
    end

    if cfg.weaponskill == '' then
        last_block_reason = 'No weaponskill'
        echo_throttled('Set a weaponskill first.')
        return
    end

    if tp >= threshold then
        last_block_reason = target_valid and 'Firing normal WS' or 'Firing normal WS with <t>'
        fire_weaponskill(cfg.weaponskill, target_index)
    else
        last_block_reason = 'Waiting TP: ' .. tostring(tp) .. '/' .. tostring(threshold)
    end
end

function autows.get_status()
    local cfg = get_config() or {}
    local has_aftermath, aftermath_buff_id = has_aftermath_buff(cfg.aftermath_tp_amount)
    has_aftermath = cfg.use_aftermath and has_aftermath

    local closers = get_closers(cfg)
    local window = get_current_skillchain_window(cfg)

    return {
        enabled = cfg.enabled == true,
        weaponskill = cfg.weaponskill or '',
        tp = get_tp(),
        has_aftermath = has_aftermath,
        aftermath_buff_id = aftermath_buff_id,
        threshold = (cfg.use_aftermath and not has_aftermath) and (cfg.aftermath_tp_amount or 3000) or (cfg.tp_amount or 1000),
        cooldown = cfg.cooldown or 3.0,
        reason = last_block_reason,
        skillchain_error = last_skillchain_error,
        player_status = get_player_status(),
        target_index = get_target_index(),
        skillchains_enabled = cfg.skillchains_enabled == true,
        open_skillchains = cfg.open_skillchains == true,
        close_skillchains = cfg.close_skillchains == true,
        skillchain_window = window,
        closers = closers,
        next_closer = closers[1],
    }
end

return autows
