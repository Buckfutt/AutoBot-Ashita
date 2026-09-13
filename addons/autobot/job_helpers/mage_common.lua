local mage = {}
local action_state = require('job_helpers.action_state')

local function now()
    if ashita and ashita.time and ashita.time.get_tick64 then
        return ashita.time.get_tick64() / 1000
    end
    return os.clock()
end

local function key(value)
    return tostring(value or ''):lower():gsub('[^%w]', '')
end

local function echo(job, message)
    windower.add_to_chat(207, '[AutoBot:' .. job .. '] ' .. tostring(message))
end

local function slider_float(imgui, label, id, value, min_value, max_value)
    imgui.Text(label .. ':')
    return imgui.SliderFloat('##' .. id, value, min_value, max_value)
end

local spell_id_cache = {}
local spell_resource_cache = {}
local job_ids = {
    WAR=1, MNK=2, WHM=3, BLM=4, RDM=5, THF=6, PLD=7, DRK=8,
    BST=9, BRD=10, RNG=11, SAM=12, NIN=13, DRG=14, SMN=15, BLU=16,
    COR=17, PUP=18, DNC=19, SCH=20, GEO=21, RUN=22,
}

local function job_is_active(job)
    local player = windower.ffxi.get_player()
    if not player then
        return false
    end

    local vitals = player.vitals or {}
    if tonumber(vitals.hpp or 0) <= 0 or tonumber(vitals.hp or 0) <= 0 then
        return false
    end

    job = tostring(job or ''):upper()
    return tostring(player.main_job or ''):upper() == job
        or tostring(player.sub_job or ''):upper() == job
end

local function player_is_engaged()
    local player = windower.ffxi.get_player()
    return player and tonumber(player.status) == 1
end

local function has_buff(member, buff_id)
    if not member or not member.buffs or not buff_id then
        return false
    end
    for _, buff in ipairs(member.buffs) do
        if tonumber(buff) == tonumber(buff_id) then
            return true
        end
    end
    return false
end

local function spell_resource(name)
    name = tostring(name or '')
    local lower_name = name:lower()
    if spell_resource_cache[lower_name] ~= nil then
        return spell_resource_cache[lower_name] or nil
    end

    local ok, resource = pcall(function()
        return AshitaCore:GetResourceManager()
    end)
    if not ok or not resource then
        return nil
    end

    for id = 0, 1024 do
        local ok_spell, spell = pcall(function()
            return resource:GetSpellById(id)
        end)
        if ok_spell and spell and spell.Name and spell.Name[1] and tostring(spell.Name[1]):lower() == lower_name then
            spell_id_cache[lower_name] = id
            spell_resource_cache[lower_name] = spell
            return spell
        end
    end
    spell_id_cache[lower_name] = false
    spell_resource_cache[lower_name] = false
    return nil
end

local function spell_id(name)
    local resource = spell_resource(name)
    return resource and tonumber(resource.Id) or nil
end

local function spell_available(name, required_job)
    local resource = spell_resource(name)
    local player = windower.ffxi.get_player()
    if not resource or not player or not resource.LevelRequired then
        return resource ~= nil
    end

    for _, role in ipairs({
        { job = player.main_job, level = player.main_job_level },
        { job = player.sub_job, level = player.sub_job_level },
    }) do
        local role_job = tostring(role.job or ''):upper()
        if not required_job or role_job == tostring(required_job):upper() then
            local job_id = job_ids[role_job]
            local required = nil
            if job_id then
                pcall(function()
                    required = tonumber(resource.LevelRequired[job_id + 1])
                end)
            end
            if required and required > 0 then
                if required <= 99
                and tonumber(role.level or 0) >= required
                then
                    return true
                end

                if required > 99
                and role_job == tostring(player.main_job or ''):upper()
                and tonumber(role.level or 0) >= 99
                then
                    local id = tonumber(resource.Id)
                    local ok_known, known = pcall(function()
                        return id and AshitaCore:GetMemoryManager():GetPlayer():HasSpell(id)
                    end)
                    if ok_known and known == true then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function spell_ready(name)
    local id = spell_id(name)
    if not id then
        return true
    end

    local ok, recast = pcall(function()
        return AshitaCore:GetMemoryManager():GetRecast()
    end)
    if ok and recast and recast.GetSpellTimer then
        local ok_timer, timer = pcall(function()
            return recast:GetSpellTimer(id)
        end)
        return not ok_timer or tonumber(timer or 0) == 0
    end

    return true
end

local function selected_slots(settings, name)
    settings.targets = settings.targets or {}
    settings.targets[name] = settings.targets[name] or {}
    local slots = settings.targets[name]
    if next(slots) == nil then
        for i = 0, 5 do
            slots[tostring(i)] = true
        end
    end
    return slots
end

local function member_enabled(settings, target_group, slot)
    local slots = selected_slots(settings, target_group)
    return slots[tostring(slot)] == true
end

local function party_members(settings, target_group)
    local party = windower.ffxi.get_party()
    local members = {}
    if not party then
        return members
    end

    for i = 0, 5 do
        local member = party['p' .. tostring(i)]
        if member and member.name and member.hpp and member.hpp > 0 and member_enabled(settings, target_group, i) then
            member.slot = i
            member.target = (i == 0) and '<me>' or member.name
            table.insert(members, member)
        end
    end

    return members
end

local function cast_spell(name, target, required_job)
    if not spell_available(name, required_job) or not spell_ready(name) then
        return false
    end
    windower.send_command('input /ma "' .. name .. '" ' .. target)
    return true
end

local function command_toggle(settings, spell_map, cmd)
    local spell = spell_map[cmd]
    if not spell then
        return false
    end
    settings.spells[cmd] = not settings.spells[cmd]
    return true, spell.name .. ': ' .. (settings.spells[cmd] and 'On' or 'Off')
end

local function render_slot_selector(imgui, settings, group, label, id)
    imgui.Text(label)
    local changed = false
    local slots = selected_slots(settings, group)
    for i = 0, 5 do
        if i > 0 then imgui.SameLine() end
        local value = { slots[tostring(i)] == true }
        local slot_label = (i == 0 and 'Me' or tostring(i)) .. '##' .. group .. '_' .. tostring(i) .. tostring(id or '')
        if imgui.Checkbox(slot_label, value) then
            slots[tostring(i)] = value[1]
            changed = true
        end
    end
    return changed
end

local function render_spell_toggles(imgui, def, settings, ctx, spell_type)
    local changed = false
    for _, spell_key in ipairs(def.order or {}) do
        local spell = def.spells[spell_key]
        if spell
        and spell.type == spell_type
        and spell_available(spell.name, def.job)
        then
            local value = { settings.spells[spell_key] == true }
            if imgui.Checkbox(spell.name .. '##' .. def.job .. '_' .. spell_key .. tostring(ctx.id or ''), value) then
                settings.spells[spell_key] = value[1]
                changed = true
            end
        end
    end
    return changed
end

function mage.create(def)
    local M = {}
    local settings = nil
    local enabled = false
    local last_cast = 0
    local cast_delay = def.cast_delay or 2.0
    local buff_history = {}
    local pending_buffs = {}
    local enfeeble_history = {}
    local raise_history = {}
    local last_history_prune = 0

    local function ensure()
        settings = settings or {}
        settings.spells = settings.spells or {}
        settings.targets = settings.targets or {}
        settings.enable_cure = settings.enable_cure ~= false
        settings.enable_status = settings.enable_status ~= false
        settings.enable_buffs = settings.enable_buffs ~= false
        settings.enable_enfeebles = settings.enable_enfeebles ~= false
        settings.enable_raise = settings.enable_raise == true
        settings.cast_delay = tonumber(settings.cast_delay) or cast_delay
        settings.cure_percent = tonumber(settings.cure_percent) or 75
        settings.protectra_tier = settings.protectra_tier or 'protectra5'
        settings.shellra_tier = settings.shellra_tier or 'shellra5'
        local defined_tiers = {}
        for _, tier in ipairs(def.tier_options or {}) do
            defined_tiers[tier.setting] = true
        end
        if not defined_tiers.protect_tier then
            settings.protect_tier = settings.protect_tier or 'protect5'
        end
        if not defined_tiers.shell_tier then
            settings.shell_tier = settings.shell_tier or 'shell5'
        end
        for _, tier in ipairs(def.tier_options or {}) do
            if settings[tier.setting] == nil then
                for _, option in ipairs(tier.options or {}) do
                    if option.key ~= 'disabled'
                    and settings.spells[option.key] == true
                    then
                        settings[tier.setting] = option.key
                        break
                    end
                end
                settings[tier.setting] = settings[tier.setting]
                    or tier.default
                    or 'disabled'
            end
        end
        for spell_key, _ in pairs(def.spells or {}) do
            if settings.spells[spell_key] == nil then
                settings.spells[spell_key] = false
            end
        end
        settings.cure_thresholds = settings.cure_thresholds or {}
        for _, spell_key in ipairs(def.cure_order or {}) do
            local spell = def.spells[spell_key]
            if spell and settings.cure_thresholds[spell_key] == nil then
                settings.cure_thresholds[spell_key] = spell.missing or 0
            end
        end
        selected_slots(settings, 'cures')
        selected_slots(settings, 'status')
        selected_slots(settings, 'haste')
        selected_slots(settings, 'refresh')
        selected_slots(settings, 'regen')
        for _, target_group in ipairs(def.target_groups or {}) do
            selected_slots(settings, target_group.group)
        end
    end

    local function cast(name, target)
        if action_state.is_busy() then
            return false
        end
        if (now() - last_cast) < settings.cast_delay then
            return false
        end
        if cast_spell(name, target, def.job) then
            last_cast = now()
            return true
        end
        return false
    end

    local function prune_histories()
        local current_time = now()
        if (current_time - last_history_prune) < 60 then return end
        last_history_prune = current_time

        for target_id, effects in pairs(enfeeble_history) do
            for effect, expires_at in pairs(effects) do
                if tonumber(expires_at or 0) < (current_time - 300) then
                    effects[effect] = nil
                end
            end
            if next(effects) == nil then
                enfeeble_history[target_id] = nil
            end
        end

        for member_name, attempted_at in pairs(raise_history) do
            if tonumber(attempted_at or 0) < (current_time - 300) then
                raise_history[member_name] = nil
            end
        end
    end

    local function best_cure()
        if not settings.enable_cure then return nil end
        local best = nil
        for _, member in ipairs(party_members(settings, 'cures')) do
            if member.hpp < settings.cure_percent then
                local missing = (member.max_hp or 0) - (member.hp or 0)
                if missing > 0 and (not best or missing > best.missing) then
                    best = { member = member, missing = missing }
                end
            end
        end
        if not best then return nil end

        for _, spell_key in ipairs(def.cure_order or {}) do
            local spell = def.spells[spell_key]
            local threshold = settings.cure_thresholds and tonumber(settings.cure_thresholds[spell_key]) or (spell and spell.missing) or 0
            if spell and settings.spells[spell_key] and best.missing >= threshold then
                return spell.name, best.member.target
            end
        end
        return nil
    end

    local function dead_human_members()
        local memory = AshitaCore:GetMemoryManager()
        local party = memory and memory:GetParty()
        local entity = memory and memory:GetEntity()
        local members = {}
        if not party or not entity then return members end

        for slot = 1, 5 do
            local ok_active, active = pcall(function()
                return party:GetMemberIsActive(slot)
            end)
            if ok_active and (active == true or tonumber(active) == 1) then
                local ok_name, name = pcall(function()
                    return party:GetMemberName(slot)
                end)
                local ok_hp, hp = pcall(function()
                    return party:GetMemberHPPercent(slot)
                end)
                local ok_index, index = pcall(function()
                    return party:GetMemberTargetIndex(slot)
                end)

                local spawn_type = nil
                local trust_owner = 0
                if ok_index and tonumber(index or 0) > 0 then
                    pcall(function()
                        local raw = entity:GetEntity(index)
                        spawn_type = raw and (raw.SpawnType or raw.spawn_type)
                    end)
                    pcall(function()
                        if entity.GetTrustOwnerTargetIndex then
                            trust_owner = tonumber(entity:GetTrustOwnerTargetIndex(index)) or 0
                        end
                    end)
                end

                if ok_name
                and name
                and name ~= ''
                and ok_hp
                and tonumber(hp) == 0
                and tonumber(spawn_type) ~= 14
                and trust_owner == 0
                then
                    table.insert(members, {
                        name = name,
                        target = name,
                    })
                end
            end
        end

        return members
    end

    local function raise_spell()
        if not def.raise_order or not settings.enable_raise then return nil end

        local current_time = now()
        for _, member in ipairs(dead_human_members()) do
            if not raise_history[member.name]
            or (current_time - raise_history[member.name]) >= 30
            then
                for _, spell_key in ipairs(def.raise_order) do
                    local spell = def.spells[spell_key]
                    if spell and spell_available(spell.name, def.job) then
                        return spell.name, member.target, member.name
                    end
                end
            end
        end

        return nil
    end

    local function status_spell()
        if not settings.enable_status then return nil end
        for _, member in ipairs(party_members(settings, 'status')) do
            for _, buff in ipairs(member.buffs or {}) do
                local spell_key = def.debuff_map[tonumber(buff)]
                local spell = spell_key and def.spells[spell_key]
                if spell and settings.spells[spell_key] then
                    return spell.name, member.target
                end
            end
        end
        return nil
    end

    local function buff_spell()
        if not settings.enable_buffs then return nil end

        for _, buff in ipairs(def.buffs or {}) do
            local enabled = settings.spells[buff.key] == true
            if buff.tiers then
                enabled = settings[buff.tier_setting] ~= nil
                    and settings[buff.tier_setting] ~= 'disabled'
            end

            if enabled then
                local members
                if buff.target == 'self' then
                    local player = windower.ffxi.get_player()
                    members = {
                        {
                            slot = 0,
                            target = '<me>',
                            buffs = player and player.buffs or {},
                        },
                    }
                else
                    members = party_members(settings, buff.group)
                end

                for _, member in ipairs(members) do
                    local history_key = buff.key .. ':' .. tostring(member.slot or member.target or '')
                    local interval = tonumber(buff.interval) or 120
                    local buff_active = buff.buff_id and has_buff(member, buff.buff_id)
                    local pending_at = pending_buffs[history_key]
                    local waiting_for_verification = pending_at
                        and (now() - pending_at) < 8

                    if buff_active then
                        pending_buffs[history_key] = nil
                    elseif pending_at and not waiting_for_verification then
                        -- The cast window elapsed without the expected status
                        -- icon. Treat the attempt as interrupted or failed.
                        pending_buffs[history_key] = nil
                    end

                    local recently_cast = not buff.buff_id
                        and buff_history[history_key]
                        and (now() - buff_history[history_key]) < interval

                    if not buff_active
                    and not waiting_for_verification
                    and not recently_cast
                    then
                        local name = buff.name
                        if buff.tiers then
                            name = buff.tiers[settings[buff.tier_setting]]
                        end
                        if name and spell_available(name, def.job) then
                            return name,
                                buff.target == 'self' and '<me>' or member.target,
                                history_key,
                                buff.buff_id
                        end
                    end
                end
            end
        end

        return nil
    end

    local function current_target()
        local ok, memory = pcall(function()
            return AshitaCore:GetMemoryManager()
        end)
        if not ok or not memory then return nil end

        local target = memory:GetTarget()
        local entity = memory:GetEntity()
        if not target or not entity then return nil end

        local ok_index, index = pcall(function()
            return target:GetTargetIndex(0)
        end)
        index = ok_index and tonumber(index) or 0
        if index <= 0 then return nil end

        local ok_id, server_id = pcall(function()
            return entity:GetServerId(index)
        end)
        local ok_hp, hp = pcall(function()
            return entity:GetHPPercent(index)
        end)
        server_id = ok_id and tonumber(server_id) or 0
        hp = ok_hp and tonumber(hp) or 0
        if server_id <= 0 or hp <= 0 then return nil end

        return server_id
    end

    local function enfeeble_spell()
        if not def.enfeebles
        or not settings.enable_enfeebles
        or not player_is_engaged()
        then
            return nil
        end

        local target_id = current_target()
        if not target_id then return nil end

        enfeeble_history[target_id] = enfeeble_history[target_id] or {}
        local target_history = enfeeble_history[target_id]
        local current_time = now()

        for _, effect in ipairs(def.enfeebles) do
            local active_until = tonumber(target_history[effect.effect] or 0)
            if active_until <= current_time then
                for _, spell_key in ipairs(effect.spells or {}) do
                    local spell = def.spells[spell_key]
                    if spell
                    and settings.spells[spell_key]
                    and spell_available(spell.name, def.job)
                    then
                        return spell.name, '<t>', target_id, effect
                    end
                end
            end
        end

        return nil
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
        echo(def.job, 'Module stopped.')
    end

    function M.tick()
        if not enabled then return end
        ensure()
        prune_histories()
        if not job_is_active(def.job) then return end
        if action_state.is_busy() then return end
        if (now() - last_cast) < settings.cast_delay then return end

        local name, target, raised_name = raise_spell()
        if name and cast(name, target) then
            raise_history[raised_name] = now()
            return
        end
        name, target = status_spell()
        if name and cast(name, target) then return end
        name, target = best_cure()
        if name and cast(name, target) then return end
        local history_key, expected_buff_id
        name, target, history_key, expected_buff_id = buff_spell()
        if name and cast(name, target) then
            if history_key then
                if expected_buff_id then
                    pending_buffs[history_key] = now()
                else
                    buff_history[history_key] = now()
                end
            end
            return
        end
        local target_id, effect
        name, target, target_id, effect = enfeeble_spell()
        if name and cast(name, target) then
            enfeeble_history[target_id][effect.effect] =
                now() + (tonumber(effect.duration) or 120)
            return
        end
    end

    function M.command(cmd, args)
        ensure()
        args = args or {}
        cmd = key(cmd)
        if cmd == 'start' or cmd == 'on' then return M.start() end
        if cmd == 'stop' or cmd == 'off' then return M.stop() end
        if cmd == 'cure' then settings.enable_cure = not settings.enable_cure; echo(def.job, 'Cures: ' .. tostring(settings.enable_cure)); return end
        if cmd == 'raise' then settings.enable_raise = not settings.enable_raise; echo(def.job, 'Raise: ' .. tostring(settings.enable_raise)); return end
        if cmd == 'status' then settings.enable_status = not settings.enable_status; echo(def.job, 'Status removal: ' .. tostring(settings.enable_status)); return end
        if cmd == 'enfeebles' or cmd == 'debuffs' then settings.enable_enfeebles = not settings.enable_enfeebles; echo(def.job, 'Enfeebles: ' .. tostring(settings.enable_enfeebles)); return end
        if cmd == 'buffs' then settings.enable_buffs = not settings.enable_buffs; echo(def.job, 'Buffs: ' .. tostring(settings.enable_buffs)); return end

        local toggled, message = command_toggle(settings, def.spells, cmd)
        if toggled then echo(def.job, message); return end
        echo(def.job, 'Unknown command: ' .. tostring(cmd))
    end

    function M.render_ui(imgui, ui_settings, ctx)
        settings = ui_settings or settings or {}
        ensure()
        ctx = ctx or {}
        local changed = false

        local suffix = def.job .. tostring(ctx.id or '')
        local delay = { settings.cast_delay }
        if slider_float(imgui, 'Cast Delay', 'cast_delay_' .. suffix, delay, 0.5, 10) then
            settings.cast_delay = delay[1]
            changed = true
        end

        local cure_pct = { settings.cure_percent }
        if slider_float(imgui, 'Cure Below HP%', 'cure_percent_' .. suffix, cure_pct, 1, 99) then
            settings.cure_percent = math.floor(cure_pct[1] + 0.5)
            changed = true
        end

        local cure = { settings.enable_cure == true }
        if imgui.Checkbox('Enable Cures##' .. def.job .. tostring(ctx.id or ''), cure) then settings.enable_cure = cure[1]; changed = true end
        if def.raise_order then
            local raise = { settings.enable_raise == true }
            if imgui.Checkbox('Enable Raise##' .. def.job .. tostring(ctx.id or ''), raise) then settings.enable_raise = raise[1]; changed = true end
        end
        if def.debuff_map then
            local status = { settings.enable_status == true }
            if imgui.Checkbox('Enable Debuff Removal##' .. def.job .. tostring(ctx.id or ''), status) then settings.enable_status = status[1]; changed = true end
        end
        if def.enfeebles then
            local enfeebles = { settings.enable_enfeebles == true }
            if imgui.Checkbox('Enable Enfeebles##' .. def.job .. tostring(ctx.id or ''), enfeebles) then settings.enable_enfeebles = enfeebles[1]; changed = true end
        end
        local buffs = { settings.enable_buffs == true }
        if imgui.Checkbox('Enable Buffs##' .. def.job .. tostring(ctx.id or ''), buffs) then settings.enable_buffs = buffs[1]; changed = true end

        imgui.Separator()
        imgui.Text('Cures')
        changed = render_spell_toggles(imgui, def, settings, ctx, 'cure') or changed
        for _, spell_key in ipairs(def.cure_order or {}) do
            local spell = def.spells[spell_key]
            if spell then
                local threshold = { tonumber(settings.cure_thresholds[spell_key]) or spell.missing or 0 }
                if slider_float(imgui, spell.name .. ' Missing HP', def.job .. '_threshold_' .. spell_key .. tostring(ctx.id or ''), threshold, 0, 3000) then
                    settings.cure_thresholds[spell_key] = math.floor(threshold[1] + 0.5)
                    changed = true
                end
            end
        end
        changed = render_slot_selector(imgui, settings, 'cures', 'Cure party slots', ctx.id) or changed

        if def.debuff_map then
            imgui.Separator()
            imgui.Text('Debuff Removal')
            changed = render_spell_toggles(imgui, def, settings, ctx, 'status') or changed
            changed = render_slot_selector(imgui, settings, 'status', 'Remove debuffs from slots', ctx.id) or changed
        end

        if def.enfeebles then
            imgui.Separator()
            imgui.Text('Enfeebles')
            changed = render_spell_toggles(imgui, def, settings, ctx, 'enfeeble') or changed
        end

        imgui.Separator()
        imgui.Text('Buffs')
        changed = render_spell_toggles(imgui, def, settings, ctx, 'buff') or changed

        if def.tier_options and ctx.combo then
            for _, tier in ipairs(def.tier_options) do
                local options = { 'disabled' }
                local labels = { disabled = 'Disabled' }
                for _, option in ipairs(tier.options or {}) do
                    if option.key == 'disabled'
                    or spell_available(option.name, def.job)
                    then
                        if option.key ~= 'disabled' then
                            table.insert(options, option.key)
                        end
                        labels[option.key] = option.name
                    end
                end

                local current = settings[tier.setting] or tier.default or 'disabled'
                local current_label = labels[current] or labels.disabled
                local label_options = {}
                local key_by_label = {}
                for _, option_key in ipairs(options) do
                    local option_label = labels[option_key] or option_key
                    table.insert(label_options, option_label)
                    key_by_label[option_label] = option_key
                end

                local next_label = ctx.combo(
                    tier.label .. '##' .. def.job .. '_' .. tier.setting .. tostring(ctx.id or ''),
                    current_label,
                    label_options
                )
                local next_value = key_by_label[next_label] or current
                if next_value ~= current then
                    settings[tier.setting] = next_value
                    changed = true
                end
                if tier.target_group then
                    changed = render_slot_selector(
                        imgui,
                        settings,
                        tier.target_group,
                        tier.target_label,
                        ctx.id
                    ) or changed
                end
            end
        end

        local inline_groups = {}
        for _, tier in ipairs(def.tier_options or {}) do
            if tier.target_group then
                inline_groups[tier.target_group] = true
            end
        end
        if not inline_groups.haste then
            changed = render_slot_selector(imgui, settings, 'haste', 'Haste target slots', ctx.id) or changed
        end
        if not inline_groups.refresh then
            changed = render_slot_selector(imgui, settings, 'refresh', 'Refresh target slots', ctx.id) or changed
        end
        if not inline_groups.regen then
            changed = render_slot_selector(imgui, settings, 'regen', 'Regen target slots', ctx.id) or changed
        end
        for _, target_group in ipairs(def.target_groups or {}) do
            if not inline_groups[target_group.group] then
                changed = render_slot_selector(
                    imgui,
                    settings,
                    target_group.group,
                    target_group.label,
                    ctx.id
                ) or changed
            end
        end

        return changed
    end

    return M
end

return mage
