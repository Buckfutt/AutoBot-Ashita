local common = {}
local action_state = require('job_helpers.action_state')

local function echo(job, message)
    windower.add_to_chat(207, '[AutoBot:' .. job .. '] ' .. tostring(message))
end

local function command_key(value)
    return tostring(value or ''):lower():gsub('[^%w]', '')
end

local function has_buff(player, buff_id)
    if not buff_id or not player or not player.buffs then
        return false
    end

    for _, buff in ipairs(player.buffs) do
        if tonumber(buff) == tonumber(buff_id) then
            return true
        end
    end

    return false
end

local function has_any_buff(player, buff_ids)
    for _, buff_id in ipairs(buff_ids or {}) do
        if has_buff(player, buff_id) then
            return true
        end
    end
    return false
end

local function ready(recasts, timer)
    if timer == nil or tonumber(timer) == nil or tonumber(timer) < 0 then
        return false
    end

    return tonumber(recasts[timer] or 0) == 0
end

local function title(value)
    value = tostring(value or ''):gsub('_', ' ')
    return (value:gsub('(%a)([%w_]*)', function(a, b)
        return a:upper() .. b:lower()
    end))
end

local ability_resource_cache = {}

local function resolve_ability_resource(name)
    local cache_key = tostring(name or ''):lower()
    if ability_resource_cache[cache_key] ~= nil then
        return ability_resource_cache[cache_key] or nil
    end

    local ok_manager, manager = pcall(function()
        return AshitaCore:GetResourceManager()
    end)
    if not ok_manager or not manager then
        return nil
    end

    for id = 0, 2048 do
        local ok_ability, resource = pcall(function()
            return manager:GetAbilityById(id)
        end)
        local resource_name = ok_ability
            and resource
            and resource.Name
            and resource.Name[1]

        if resource_name and tostring(resource_name):lower() == cache_key then
            ability_resource_cache[cache_key] = resource
            return resource
        end
    end

    ability_resource_cache[cache_key] = false
    return nil
end

local function slider_float(imgui, label, id, value, min_value, max_value)
    imgui.Text(label .. ':')
    return imgui.SliderFloat('##' .. id, value, min_value, max_value)
end

function common.create_ability_job(def)
    local M = {}
    local settings = nil
    local enabled = false
    local acting = false
    local last_used = 0
    local cooldown = def.cooldown or 3
    local aliases = {}
    local auto_ra = {
        active = false,
        next_shot = 0,
    }

    for _, ability in ipairs(def.abilities or {}) do
        aliases[command_key(ability.key or ability.name)] = ability
        aliases[command_key(ability.name)] = ability
        for _, alias in ipairs(ability.aliases or {}) do
            aliases[command_key(alias)] = ability
        end
    end

    local function ensure()
        settings = settings or {}
        settings.abilities = settings.abilities or {}
        settings.cooldown = tonumber(settings.cooldown) or cooldown
        if def.auto_ra then
            settings.autoRA = settings.autoRA or {}
            settings.autoRA.enabled = settings.autoRA.enabled == true
            settings.autoRA.delay = tonumber(settings.autoRA.delay) or 1.5
            settings.autoRA.haltOnTp = settings.autoRA.haltOnTp ~= false
            settings.autoRA.haltTp = tonumber(settings.autoRA.haltTp) or 1000
        end
        for _, ability in ipairs(def.abilities or {}) do
            local key = ability.key or ability.name
            if settings.abilities[key] == nil then
                settings.abilities[key] = false
            end

            if ability._resource_checked ~= true then
                local resource = resolve_ability_resource(ability.name)
                ability._resource_checked = true
                ability._resource_valid = resource ~= nil
                if resource and tonumber(resource.RecastTimerId) then
                    ability._timer = tonumber(resource.RecastTimerId)
                else
                    ability._timer = tonumber(ability.timer)
                end
            end
        end
    end

    local function shoot()
        windower.send_command('input /shoot <t>')
        auto_ra.next_shot = os.clock() + settings.autoRA.delay
    end

    local function tick_auto_ra(player)
        if not def.auto_ra or not settings.autoRA.enabled then
            return false
        end

        if settings.autoRA.haltOnTp and ((player.vitals and player.vitals.tp) or 0) >= settings.autoRA.haltTp then
            settings.autoRA.enabled = false
            auto_ra.active = false
            echo(def.job, 'Auto-RA halted at ' .. tostring(settings.autoRA.haltTp) .. ' TP.')
            return false
        end

        if player.status ~= 1 then
            return false
        end

        if os.clock() >= auto_ra.next_shot then
            shoot()
            return true
        end

        return false
    end

    local function use_ability(ability)
        acting = true
        last_used = os.clock()
        local target = ability.target or '<me>'
        windower.send_command(('input /ja "%s" %s'):format(ability.name, target))
        coroutine.schedule(function()
            acting = false
        end, settings.cooldown)
    end

    local function should_use(ability, player, recasts)
        if not settings.abilities[ability.key or ability.name] then
            return false
        end
        if ability.condition and not ability.condition(player, settings) then
            return false
        end
        if ability.engaged ~= false and player.status ~= 1 then
            return false
        end
        local job_level = player.main_job == def.job
            and (player.main_job_level or 0)
            or (player.sub_job == def.job and (player.sub_job_level or 0) or 0)
        if ability.level and job_level < ability.level then
            return false
        end
        if ability.min_hp_under and ((player.vitals and player.vitals.hpp) or 100) > ability.min_hp_under then
            return false
        end
        if ability.min_mp_under and ((player.vitals and player.vitals.mpp) or 100) > ability.min_mp_under then
            return false
        end
        if ability.min_tp and ((player.vitals and player.vitals.tp) or 0) < ability.min_tp then
            return false
        end
        if ability.buff and has_buff(player, ability.buff) then
            return false
        end
        if ability.blocks_buffs and has_any_buff(player, ability.blocks_buffs) then
            return false
        end
        if ability.requires_buff and not has_buff(player, ability.requires_buff) then
            return false
        end
        if ability.requires_any_buff
        and not has_any_buff(player, ability.requires_any_buff)
        then
            return false
        end
        if ability._resource_checked and ability._resource_valid == false then
            return false
        end
        local timer = ability._timer
        if timer == nil then
            timer = tonumber(ability.timer)
        end
        if timer ~= nil and not ready(recasts, timer) then
            return false
        end
        if timer == nil or timer < 0 then
            return false
        end
        return true
    end

    function M.init(job_settings)
        settings = job_settings or {}
        ensure()
        echo(def.job, 'Module initialized.')
    end

    function M.start()
        ensure()
        enabled = true
        echo(def.job, 'Module started.')
    end

    function M.stop()
        enabled = false
        acting = false
        auto_ra.active = false
        echo(def.job, 'Module stopped.')
    end

    function M.tick()
        if not enabled then
            return
        end
        ensure()
        if action_state.is_busy() then
            return
        end
        if acting or (os.clock() - last_used) < settings.cooldown then
            return
        end

        local player = windower.ffxi.get_player()
        if not player then
            return
        end

        if tick_auto_ra(player) then
            return
        end

        local recasts = windower.ffxi.get_ability_recasts()
        for _, ability in ipairs(def.abilities or {}) do
            if should_use(ability, player, recasts) then
                use_ability(ability)
                return
            end
        end
    end

    function M.command(cmd, args)
        ensure()
        args = args or {}
        cmd = command_key(cmd)
        if cmd == 'start' or cmd == 'on' then
            return M.start()
        end
        if cmd == 'stop' or cmd == 'off' then
            return M.stop()
        end

        if def.auto_ra and (cmd == 'autora' or cmd == 'ra') then
            local subcmd = command_key(args[1])
            if subcmd == 'start' or subcmd == 'on' then
                settings.autoRA.enabled = true
                auto_ra.next_shot = 0
                echo(def.job, 'Auto-RA: On')
                return
            end
            if subcmd == 'stop' or subcmd == 'off' then
                settings.autoRA.enabled = false
                auto_ra.active = false
                echo(def.job, 'Auto-RA: Off')
                return
            end
            if subcmd == 'delay' and args[2] then
                settings.autoRA.delay = tonumber(args[2]) or settings.autoRA.delay
                echo(def.job, 'Auto-RA delay: ' .. tostring(settings.autoRA.delay))
                return
            end
            if (subcmd == 'tp' or subcmd == 'halttp') and args[2] then
                settings.autoRA.haltTp = tonumber(args[2]) or settings.autoRA.haltTp
                echo(def.job, 'Auto-RA halt TP: ' .. tostring(settings.autoRA.haltTp))
                return
            end
            if subcmd == 'halt' or subcmd == 'haltontp' then
                settings.autoRA.haltOnTp = not settings.autoRA.haltOnTp
                echo(def.job, 'Auto-RA halt on TP: ' .. (settings.autoRA.haltOnTp and 'On' or 'Off'))
                return
            end

            settings.autoRA.enabled = not settings.autoRA.enabled
            auto_ra.next_shot = 0
            echo(def.job, 'Auto-RA: ' .. (settings.autoRA.enabled and 'On' or 'Off'))
            return
        end

        if def.auto_ra and (cmd == 'rastart' or cmd == 'startra') then
            settings.autoRA.enabled = true
            auto_ra.next_shot = 0
            echo(def.job, 'Auto-RA: On')
            return
        end

        if def.auto_ra and (cmd == 'rastop' or cmd == 'stopra') then
            settings.autoRA.enabled = false
            auto_ra.active = false
            echo(def.job, 'Auto-RA: Off')
            return
        end

        if def.auto_ra and cmd == 'shoot' then
            shoot()
            return
        end

        if def.auto_ra and (cmd == 'haltontp' or cmd == 'rahalt') then
            settings.autoRA.haltOnTp = not settings.autoRA.haltOnTp
            echo(def.job, 'Auto-RA halt on TP: ' .. (settings.autoRA.haltOnTp and 'On' or 'Off'))
            return
        end

        local ability = aliases[cmd]
        if ability then
            local key = ability.key or ability.name
            settings.abilities[key] = not settings.abilities[key]
            echo(def.job, ability.name .. ': ' .. (settings.abilities[key] and 'On' or 'Off'))
            return
        end

        echo(def.job, 'Unknown command: ' .. tostring(cmd))
    end

    function M.is_ability_ready(value)
        ensure()

        local ability = aliases[command_key(value)]
        if not ability then
            return false
        end

        local key = ability.key or ability.name
        if settings.abilities[key] ~= true then
            return false
        end

        local player = windower.ffxi.get_player()
        if not player or (ability.buff and has_buff(player, ability.buff)) then
            return false
        end

        local job_level = player.main_job == def.job
            and (player.main_job_level or 0)
            or (player.sub_job == def.job and (player.sub_job_level or 0) or 0)
        if ability.level and job_level < ability.level then
            return false
        end

        if ability._resource_checked and ability._resource_valid == false then
            return false
        end

        local timer = ability._timer
        if timer == nil then
            timer = tonumber(ability.timer)
        end

        return timer ~= nil
            and timer >= 0
            and ready(windower.ffxi.get_ability_recasts(), timer)
    end

    function M.render_ui(imgui, ui_settings, ctx)
        settings = ui_settings or settings or {}
        ensure()
        local changed = false
        ctx = ctx or {}

        local suffix = def.job .. tostring(ctx.id or '')
        local delay = { tonumber(settings.cooldown) or cooldown }
        if slider_float(imgui, 'Ability Delay', 'ability_delay_' .. suffix, delay, 1, 10) then
            settings.cooldown = delay[1]
            changed = true
        end

        for _, ability in ipairs(def.abilities or {}) do
            local key = ability.key or ability.name
            local available = not ability.level or (tonumber(ctx.level) or 0) >= ability.level
            if available then
                local value = { settings.abilities[key] == true }
                local label = ability.label or ability.name
                if ability.timer == nil or tonumber(ability.timer) == nil or tonumber(ability.timer) < 0 then
                    label = label .. ' (needs timer)'
                end
                if imgui.Checkbox(label .. '##' .. def.job .. '_' .. key .. tostring(ctx.id or ''), value) then
                    settings.abilities[key] = value[1]
                    changed = true
                end
            end
        end

        if def.auto_ra then
            imgui.Separator()
            imgui.Text('Auto-RA')
            imgui.TextDisabled('Runs while this job module is enabled and you are engaged.')

            local ra_enabled = { settings.autoRA.enabled == true }
            if imgui.Checkbox('Enable Auto-RA##' .. def.job .. tostring(ctx.id or ''), ra_enabled) then
                settings.autoRA.enabled = ra_enabled[1]
                auto_ra.next_shot = 0
                changed = true
            end

            local halt = { settings.autoRA.haltOnTp == true }
            if imgui.Checkbox('Auto-Stop At TP##' .. def.job .. tostring(ctx.id or ''), halt) then
                settings.autoRA.haltOnTp = halt[1]
                changed = true
            end

            local halt_tp = { tonumber(settings.autoRA.haltTp) or 1000 }
            if slider_float(imgui, 'Auto-Stop TP', 'autora_stop_tp_' .. suffix, halt_tp, 1000, 3000) then
                settings.autoRA.haltTp = math.floor(halt_tp[1] + 0.5)
                changed = true
            end

            local ra_delay = { tonumber(settings.autoRA.delay) or 1.5 }
            if slider_float(imgui, 'Ranged Delay', 'autora_delay_' .. suffix, ra_delay, 0.5, 10.0) then
                settings.autoRA.delay = ra_delay[1]
                changed = true
            end
        end

        return changed
    end

    M.definition = def
    M.title = title
    return M
end

return common
