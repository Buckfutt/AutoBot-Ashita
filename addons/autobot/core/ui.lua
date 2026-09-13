local imgui = require('imgui')

local ui = {}

ui.open = true
ui.help_open = false
ui.page = 'main'
ui.new_target = ''
ui.new_whitelist = ''
ui.pull_spell = ''
ui.pull_ability = ''
ui.autows_weaponskill = ''
ui.autows_open_weaponskill = ''
ui.autows_level_priority = ''
ui.autows_chain_priority = ''
ui.autows_close_ws_priority = ''
ui.autows_blacklist = ''
ui.item_food_name = ''
ui.combat_assist_target = ''
ui.brd_set_name = ''
ui.nav_record_name = ''
ui.nav_selected_path = ''
ui.nav_record_zone_name = ''
ui.nav_record_details = ''
ui.nav_detail_zone_name = ''
ui.nav_detail_details = ''
ui.nav_detail_loaded_path = ''
ui.trust_set_name = ''
ui.trust_selected_set = ''
ui.trust_selected_trust = ''
ui.trust_tab = 'sets'
ui.job_tab = 'main'
ui.job_window_open = {}

-- Refresh configuration-backed edit buffers whenever the active character
-- changes. Without this, non-empty text from the previous character remains
-- in ImGui and can overwrite the newly loaded profile on its next save.
ui.set_config = function(config)
    config = config or {}
    local pulling = config.pulling or {}
    local combat = config.combat or {}
    local autows = config.autows or {}
    local food = (config.items or {}).food or {}
    local trusts = config.trusts or {}

    ui.pull_spell = pulling.spell or ''
    ui.pull_ability = pulling.ability or ''
    ui.autows_weaponskill = autows.weaponskill or ''
    ui.autows_open_weaponskill = autows.open_weaponskill or ''
    ui.autows_level_priority = autows.level_priority or '4,3,2,1'
    ui.autows_chain_priority = autows.chain_priority or ''
    ui.autows_close_ws_priority = autows.close_ws_priority or ''
    ui.autows_blacklist = autows.blacklist or ''
    ui.item_food_name = food.name or ''
    ui.combat_assist_target = combat.assist_target or ''
    ui.trust_selected_set = trusts.selected_set or ''
    ui.trust_selected_trust = trusts.selected_trust or ''

    ui.new_target = ''
    ui.new_whitelist = ''
    ui.trust_set_name = ''
    ui.brd_set_name = ''
    ui.job_window_open = {}
end

local module_order = {
    'targeting',
    'pulling',
    'combat',
    'autows',
    'items',
    'casting',
    'follow',
    'general',
    'interaction',
    'navigation',
    'trusts',
    'jobs',
    'uberwarp',
}

local module_labels = {
    targeting = 'Targeting',
    pulling = 'Pulling',
    combat = 'Combat',
    autows = 'AutoWS',
    items = 'Items',
    casting = 'Casting',
    follow = 'Follow',
    general = 'General',
    interaction = 'Interaction',
    navigation = 'Navigation',
    trusts = 'Trusts',
    jobs = 'Job Modules',
    uberwarp = 'UberWarp',
}

local job_names = {
    [1] = 'WAR', [2] = 'MNK', [3] = 'WHM', [4] = 'BLM', [5] = 'RDM', [6] = 'THF',
    [7] = 'PLD', [8] = 'DRK', [9] = 'BST', [10] = 'BRD', [11] = 'RNG', [12] = 'SAM',
    [13] = 'NIN', [14] = 'DRG', [15] = 'SMN', [16] = 'BLU', [17] = 'COR', [18] = 'PUP',
    [19] = 'DNC', [20] = 'SCH', [21] = 'GEO', [22] = 'RUN',
}

local job_abilities = {
    WAR = { 'Berserk', 'Defender', 'Aggressor', 'Warcry', 'Retaliation', 'Blood_Rage' },
    MNK = { 'Focus', 'Dodge', 'Chakra', 'Boost', 'Counterstance', 'Footwork', 'Impetus', 'Mantra', 'Perfect_Counter', 'Formless_Strikes', 'Hundred_Fists', 'Inner_Strength' },
    SAM = { 'Hasso', 'Seigan', 'Meditate', 'Third_Eye', 'Warding_Circle', 'Sekkanoki', 'Sengikori', 'Hamanoha', 'Hagakure', 'Meikyo_Shizui', 'Yaegasumi', 'Konzen_Ittai' },
}

local job_ability_levels = {
    WAR = { Berserk = 15, Defender = 25, Aggressor = 45, Warcry = 35, Retaliation = 60, Blood_Rage = 87 },
    MNK = { Focus = 25, Dodge = 15, Chakra = 35, Boost = 5, Counterstance = 45, Footwork = 65, Impetus = 88, Mantra = 75, Perfect_Counter = 79, Formless_Strikes = 75, Hundred_Fists = 1, Inner_Strength = 96 },
    SAM = { Hasso = 25, Seigan = 35, Meditate = 30, Third_Eye = 15, Warding_Circle = 5, Sekkanoki = 40, Sengikori = 77, Hamanoha = 87, Hagakure = 95, Meikyo_Shizui = 1, Yaegasumi = 96, Konzen_Ittai = 65 },
    RUN = { useSwipe = 25, useLunge = 25, useSwordplay = 20, useVal = 10, usePflug = 50 },
}

local whm_spells = {
    'cure', 'cure2', 'cure3', 'cure4', 'cure5', 'cure6',
    'poisona', 'paralyna', 'silena', 'blindna', 'viruna', 'stona', 'cursna', 'erase', 'esuna',
    'haste', 'haste2', 'protectra', 'shellra', 'auspice',
    'regen', 'regen2', 'regen3', 'regen4', 'regen5',
    'divine_seal', 'afflatus_solace', 'afflatus_misery',
}

local rune_options = { 'ignis', 'gelus', 'flabra', 'tellus', 'sulpor', 'unda', 'lux', 'tenebrae' }

local child_flags_none = ImGuiChildFlags_None or 0
local child_flags_borders = ImGuiChildFlags_Borders or 1

local function b(v)
    return v == true
end

local function trim(s)
    return (s and s:match("^%s*(.-)%s*$")) or ''
end

local function nav_path_name(s)
    s = trim(s)
    s = s:gsub('[\\/:*?"<>|]', '_')
    s = s:gsub('^%.+', '')
    s = s:gsub('%.+$', '')
    return s
end

local function title(s)
    s = tostring(s or '')
    s = s:gsub('_', ' ')
    return (s:gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end))
end

local skillchain_colors = {
    Light = { 1.00, 0.92, 0.48, 1.0 },
    Darkness = { 0.70, 0.52, 1.00, 1.0 },
    Radiance = { 1.00, 0.82, 0.28, 1.0 },
    Umbra = { 0.55, 0.32, 0.92, 1.0 },
    Fusion = { 1.00, 0.42, 0.32, 1.0 },
    Fragmentation = { 0.45, 0.78, 1.00, 1.0 },
    Distortion = { 0.50, 0.58, 1.00, 1.0 },
    Gravitation = { 0.72, 0.52, 0.36, 1.0 },
    Liquefaction = { 1.00, 0.38, 0.25, 1.0 },
    Induration = { 0.55, 0.78, 1.00, 1.0 },
    Detonation = { 0.62, 0.88, 0.42, 1.0 },
    Scission = { 0.78, 0.58, 0.34, 1.0 },
    Impaction = { 0.95, 0.82, 0.36, 1.0 },
    Reverberation = { 0.35, 0.72, 1.00, 1.0 },
    Transfixion = { 0.92, 0.86, 1.00, 1.0 },
    Compression = { 0.72, 0.54, 0.92, 1.0 },
}

local function skillchain_color(name)
    return skillchain_colors[tostring(name or '')] or { 0.86, 0.86, 0.86, 1.0 }
end

local function contains(tbl, val)
    if not tbl or not val then return false end

    for _, v in ipairs(tbl) do
        if type(v) == 'string' and v:lower() == val:lower() then
            return true
        end
    end

    return false
end

local function job_by_id(value)
    if type(value) == 'string' then
        value = value:upper()
        return value ~= '' and value or nil
    end

    return job_names[tonumber(value or 0)]
end

local function current_jobs()
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if not player then
        return {
            main = { job = nil, level = 0 },
            sub = { job = nil, level = 0 },
        }
    end

    local function call(method)
        local ok, value = pcall(function()
            return player[method](player)
        end)

        return ok and value or nil
    end

    return {
        main = {
            job = job_by_id(call('GetMainJob') or call('GetMainJobId')),
            level = tonumber(call('GetMainJobLevel')) or 0,
        },
        sub = {
            job = job_by_id(call('GetSubJob') or call('GetSubJobId')),
            level = tonumber(call('GetSubJobLevel')) or 0,
        },
    }
end

local function ensure_job_settings(config, job)
    if not job then
        return nil
    end

    config.job_modules = config.job_modules or {}
    config.job_modules[job] = config.job_modules[job] or {}

    local settings = config.job_modules[job]
    settings.enabled = b(settings.enabled)

    if job_abilities[job] then
        settings.abilities = settings.abilities or {}
        for _, ability in ipairs(job_abilities[job]) do
            if settings.abilities[ability] == nil then
                settings.abilities[ability] = false
            end
        end
    elseif job == 'WHM' then
        settings.spells = settings.spells or {}
        settings.enable_cure = settings.enable_cure ~= false
        settings.enable_status = settings.enable_status ~= false
        settings.enable_buffs = settings.enable_buffs ~= false
        settings.protectra_tier = settings.protectra_tier or 'protectra5'
        settings.shellra_tier = settings.shellra_tier or 'shellra5'
        for _, spell in ipairs(whm_spells) do
            if settings.spells[spell] == nil then
                settings.spells[spell] = false
            end
        end
    elseif job == 'RUN' then
        settings.desiredSlots = settings.desiredSlots or {}
        settings.useSwipe = b(settings.useSwipe)
        settings.useLunge = b(settings.useLunge)
        settings.useSwordplay = b(settings.useSwordplay)
        settings.useVal = b(settings.useVal)
        settings.usePflug = b(settings.usePflug)
    elseif job == 'BRD' then
        settings.savedSets = settings.savedSets or {}
        settings.default = settings.default or {}
        settings.songDelay = tonumber(settings.songDelay) or 15
    end

    return settings
end

local function small_status(label, on)
    imgui.Text(label .. ':')
    imgui.SameLine(145)
    imgui.Text(on and 'Running' or 'Stopped')
end

local function action_button(label, enabled, size)
    if enabled then
        imgui.PushStyleColor(ImGuiCol_Button, { 0.18, 0.42, 0.24, 1.0 })
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.24, 0.54, 0.31, 1.0 })
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.14, 0.34, 0.2, 1.0 })
    else
        imgui.PushStyleColor(ImGuiCol_Button, { 0.46, 0.18, 0.18, 1.0 })
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.58, 0.24, 0.24, 1.0 })
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.36, 0.12, 0.12, 1.0 })
    end

    local clicked = imgui.Button(label, size or { 120, 30 })
    imgui.PopStyleColor(3)

    return clicked
end

local function nav_button(label, page)
    local selected = ui.page == page

    if selected then
        imgui.PushStyleColor(ImGuiCol_Button, { 0.42, 0.31, 0.12, 0.95 })
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.48, 0.36, 0.15, 1.0 })
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.52, 0.38, 0.16, 1.0 })
    else
        imgui.PushStyleColor(ImGuiCol_Button, { 0, 0, 0, 0 })
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.20, 0.22, 0.25, 1.0 })
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.25, 0.27, 0.30, 1.0 })
    end

    if imgui.Button(label, { 170, 30 }) then
        ui.page = page
    end

    imgui.PopStyleColor(3)
end

local function split_label(label)
    label = tostring(label or '')
    local visible, id = label:match('^(.-)(##.*)$')
    if visible then
        return visible, id
    end

    return label, '##' .. label:gsub('%W', '_')
end

local function combo_string(label, current, options)
    local value = current or options[1]
    local visible, id = split_label(label)

    if visible ~= '' then
        imgui.Text(visible .. ':')
    end

    if imgui.BeginCombo(id, value) then
        for _, option in ipairs(options) do
            if imgui.Selectable(option, option == value) then
                value = option
            end
        end
        imgui.EndCombo()
    end

    return value
end

local function labeled_slider_float(label, id, value, min_value, max_value, format)
    imgui.Text(label .. ':')
    return imgui.SliderFloat('##' .. id, value, min_value, max_value, format or '%.3f')
end

local function labeled_slider_int(label, id, value, min_value, max_value)
    imgui.Text(label .. ':')
    return imgui.SliderInt('##' .. id, value, min_value, max_value)
end

local function labeled_input(label, id, value, max_len)
    imgui.Text(label)
    local buf = { value or '' }
    if imgui.InputText('##' .. id, buf, max_len or 128) then
        return true, buf[1]
    end

    return false, buf[1]
end

local function trust_tab(label, tab, width)
    local selected = ui.trust_tab == tab
    if selected then
        imgui.PushStyleColor(ImGuiCol_Button, { 0.42, 0.31, 0.12, 1.0 })
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.48, 0.36, 0.15, 1.0 })
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.52, 0.38, 0.16, 1.0 })
    end

    if imgui.Button(label, { width, 30 }) then
        ui.trust_tab = tab
    end

    if selected then
        imgui.PopStyleColor(3)
    end
end

local function section_title(text)
    text = tostring(text or '')

    local width = 0
    local text_width = 0
    local cursor_x = 0

    pcall(function()
        width = imgui.GetWindowWidth()
        text_width = imgui.CalcTextSize(text)
        cursor_x = imgui.GetCursorPosX()
    end)

    if type(text_width) == 'table' then
        text_width = text_width[1] or text_width.x or 0
    end

    if width > 0 and text_width > 0 then
        pcall(function()
            imgui.SetCursorPosX(math.max(cursor_x, cursor_x + ((width - text_width) * 0.5) - 12))
        end)
    end

    pcall(function() imgui.SetWindowFontScale(1.15) end)
    imgui.TextColored({ 0.92, 0.76, 0.38, 1.0 }, text)
    pcall(function() imgui.SetWindowFontScale(1.0) end)
    imgui.Separator()
end

local function help_line(command, detail)
    imgui.TextColored({ 0.92, 0.76, 0.38, 1.0 }, command)
    imgui.TextWrapped(detail)
    imgui.Spacing()
end

local function render_main(config, scripts)
    section_title('Run Controls')

    config.runtime = config.runtime or {}

    small_status('Targeting', config.modules.targeting and config.runtime.targeting)
    if not config.modules.targeting then
        imgui.TextDisabled('Enable Targeting on the Modules page first.')
    elseif action_button(config.runtime.targeting and 'Stop Targeting' or 'Start Targeting', not config.runtime.targeting, { 150, 32 }) then
        config.runtime.targeting = not config.runtime.targeting
        if not config.runtime.targeting and scripts.targeting then
            scripts.targeting.stop()
        end
    end

    imgui.Separator()

    small_status('Pulling', config.modules.pulling and config.runtime.pulling)
    if not config.modules.pulling then
        imgui.TextDisabled('Enable Pulling on the Modules page first.')
    elseif action_button(config.runtime.pulling and 'Stop Pulling' or 'Start Pulling', not config.runtime.pulling, { 150, 32 }) then
        config.runtime.pulling = not config.runtime.pulling
        if not config.runtime.pulling and scripts.pulling then
            scripts.pulling.stop()
        end
    end

    imgui.Separator()
    section_title('Current Setup')
    imgui.Text('Targets: ' .. tostring(#(config.target_list or {})))
    imgui.Text('Pull Method: ' .. (config.pulling.use_spell and ('Spell - ' .. (config.pulling.spell or '')) or config.pulling.use_ability and ('Ability - ' .. (config.pulling.ability or '')) or config.pulling.use_ranged and 'Ranged Attack' or 'Attack'))
end

local function render_modules(config, scripts)
    section_title('Module Enablement')
    imgui.TextDisabled('These toggles decide what AutoBot is allowed to run.')
    imgui.TextDisabled('Targeting and Pulling still start dormant after reload.')

    for _, name in ipairs(module_order) do
        if config.modules[name] ~= nil then
            local value = { b(config.modules[name]) }
            if imgui.Checkbox((module_labels[name] or title(name)) .. '##module_' .. name, value) then
                config.modules[name] = value[1]
                if name == 'targeting' and not value[1] and scripts.targeting then
                    config.runtime = config.runtime or {}
                    config.runtime.targeting = false
                    scripts.targeting.stop()
                elseif name == 'pulling' and not value[1] and scripts.pulling then
                    config.runtime = config.runtime or {}
                    config.runtime.pulling = false
                    scripts.pulling.stop()
                elseif name == 'navigation' and not value[1] and scripts.navigation then
                    if scripts.navigation.stop_record then
                        scripts.navigation.stop_record()
                    end
                    if scripts.navigation.stop_playback then
                        scripts.navigation.stop_playback()
                    end
                elseif name == 'combat' and scripts.combat then
                    if value[1] and scripts.combat.set_settings then
                        scripts.combat.set_settings(config)
                    elseif not value[1] and scripts.combat.shutdown then
                        scripts.combat.shutdown()
                    end
                end
            end
        end
    end

    imgui.Separator()
    if imgui.Button('Save Modules', { 140, 30 }) then
        scripts.save(config)
    end
end

local function render_targeting(config, scripts)
    section_title('Targeting')

    local v = { tonumber(config.targeting.max_distance) or 20 }
    if labeled_slider_float('Max Distance', 'target_max_distance', v, 5, 40, '%.1f') then
        config.targeting.max_distance = math.floor((v[1] * 10) + 0.5) / 10
    end

    v = { b(config.targeting.ignore_claimed) }
    if imgui.Checkbox('Ignore Claimed', v) then
        config.targeting.ignore_claimed = v[1]
    end
    config.targeting.prefer_unclaimed = not b(config.targeting.ignore_claimed)

    imgui.Separator()
    section_title('Target List')

    local changed, target_value = labeled_input('Target Name:', 'target_name', ui.new_target, 128)
    if changed then
        ui.new_target = target_value
    end
    if imgui.Button('Add Target', { 110, 0 }) then
        local new = trim(ui.new_target):lower()
        if new ~= '' and not contains(config.target_list, new) then
            table.insert(config.target_list, new)
            ui.new_target = ''
        end
    end

    imgui.BeginChild('target_list', { 0, 210 }, child_flags_borders)
    for i, target in ipairs(config.target_list) do
        imgui.Text(target)
        imgui.SameLine(260)
        if imgui.Button('Remove##target_' .. i, { 90, 0 }) then
            table.remove(config.target_list, i)
            break
        end
    end
    imgui.EndChild()

    if imgui.Button('Save Targeting', { 140, 30 }) then
        scripts.save(config)
    end
end

local function render_pulling(config, scripts)
    section_title('Pulling')

    local method = 'attack'
    if config.pulling.use_spell then method = 'spell' end
    if config.pulling.use_ability then method = 'ability' end
    if config.pulling.use_ranged then method = 'ranged' end

    if imgui.RadioButton('Spell##pull_method_spell', method == 'spell') then
        method = 'spell'
    end
    if imgui.RadioButton('Ability##pull_method_ability', method == 'ability') then
        method = 'ability'
    end
    if imgui.RadioButton('Ranged##pull_method_ranged', method == 'ranged') then
        method = 'ranged'
    end
    if imgui.RadioButton('Attack##pull_method_attack', method == 'attack') then
        method = 'attack'
    end

    config.pulling.use_spell = method == 'spell'
    config.pulling.use_ability = method == 'ability'
    config.pulling.use_ranged = method == 'ranged'

    local changed, spell_value = labeled_input('Spell:', 'pull_spell_input', ui.pull_spell, 128)
    if changed then
        ui.pull_spell = spell_value
        config.pulling.spell = trim(ui.pull_spell)
    end

    changed, spell_value = labeled_input('Ability:', 'pull_ability_input', ui.pull_ability, 128)
    if changed then
        ui.pull_ability = spell_value
        config.pulling.ability = trim(ui.pull_ability)
    end

    local timeout = { tonumber(config.pulling.timeout) or 8 }
    if labeled_slider_float('Timeout Seconds', 'pull_timeout_seconds', timeout, 2, 20, '%.1f') then
        config.pulling.timeout = math.floor((timeout[1] * 10) + 0.5) / 10
    end

    imgui.Separator()
    if imgui.Button('Save Pulling', { 140, 30 }) then
        config.pulling.spell = trim(ui.pull_spell)
        config.pulling.ability = trim(ui.pull_ability)
        scripts.save(config)
    end
end

local function render_combat(config, scripts)
    section_title('Combat')

    local v = { b(config.combat.auto_engage) }
    if imgui.Checkbox('Auto Engage', v) then
        config.combat.auto_engage = v[1]
    end

    v = { b(config.combat.approach) }
    if imgui.Checkbox('Approach Target', v) then
        config.combat.approach = v[1]
        if scripts.combat and scripts.combat.set_settings then
            scripts.combat.set_settings(config)
        end
    end

    v = { b(config.combat.auto_face) }
    if imgui.Checkbox('Auto Face Target', v) then
        config.combat.auto_face = v[1]
        if scripts.combat and scripts.combat.set_settings then
            scripts.combat.set_settings(config)
        end
        if scripts.combat then
            if v[1] and scripts.combat.start_face_loop then
                scripts.combat.start_face_loop()
            elseif not v[1] and scripts.combat.stop_face_loop then
                scripts.combat.stop_face_loop()
            end
        end
    end

    v = { b(config.combat.auto_assist) }
    if imgui.Checkbox('Auto Assist', v) then
        config.combat.auto_assist = v[1]
        if scripts.combat and scripts.combat.set_settings then
            scripts.combat.set_settings(config)
        end
    end

    local changed, assist_value = labeled_input('Assist Target:', 'combat_assist_target', ui.combat_assist_target ~= '' and ui.combat_assist_target or (config.combat.assist_target or ''), 128)
    if changed then
        ui.combat_assist_target = assist_value
        config.combat.assist_target = trim(ui.combat_assist_target)
        if scripts.combat and scripts.combat.set_settings then
            scripts.combat.set_settings(config)
        end
    end

    imgui.Separator()
    imgui.Text('Resting Thresholds')

    local manage_hp = { b(config.combat.manage_hp) }
    if imgui.Checkbox('Manage HP', manage_hp) then
        config.combat.manage_hp = manage_hp[1]
    end

    local hp_min = { tonumber(config.combat.hp_minimum) or 0 }
    if labeled_slider_int('HP Minimum %', 'combat_hp_minimum', hp_min, 0, 100) then
        config.combat.hp_minimum = math.floor(hp_min[1])
        if config.combat.hp_maximum < config.combat.hp_minimum then
            config.combat.hp_maximum = config.combat.hp_minimum
        end
    end

    local hp_max = { tonumber(config.combat.hp_maximum) or 100 }
    if labeled_slider_int('HP Maximum %', 'combat_hp_maximum', hp_max, 0, 100) then
        config.combat.hp_maximum = math.max(config.combat.hp_minimum, math.floor(hp_max[1]))
    end

    local manage_mp = { b(config.combat.manage_mp) }
    if imgui.Checkbox('Manage MP', manage_mp) then
        config.combat.manage_mp = manage_mp[1]
    end

    local mp_min = { tonumber(config.combat.mp_minimum) or 0 }
    if labeled_slider_int('MP Minimum %', 'combat_mp_minimum', mp_min, 0, 100) then
        config.combat.mp_minimum = math.floor(mp_min[1])
        if config.combat.mp_maximum < config.combat.mp_minimum then
            config.combat.mp_maximum = config.combat.mp_minimum
        end
    end

    local mp_max = { tonumber(config.combat.mp_maximum) or 100 }
    if labeled_slider_int('MP Maximum %', 'combat_mp_maximum', mp_max, 0, 100) then
        config.combat.mp_maximum = math.max(config.combat.mp_minimum, math.floor(mp_max[1]))
    end

    imgui.Separator()
    if imgui.Button('Save Combat', { 140, 30 }) then
        config.combat.assist_target = trim(ui.combat_assist_target ~= '' and ui.combat_assist_target or config.combat.assist_target)
        if scripts.combat and scripts.combat.set_settings then
            scripts.combat.set_settings(config)
        end
        scripts.save(config)
    end
end

local function render_autows(config, scripts)
    section_title('AutoWS')

    config.autows = config.autows or {}

    local v = { b(config.autows.enabled) }
    if imgui.Checkbox('Enable AutoWS', v) then
        config.autows.enabled = v[1]
        if scripts.autows and scripts.autows.set_settings then
            scripts.autows.set_settings(config)
        end
    end

    local changed, ws_value = labeled_input('Weaponskill:', 'autows_weaponskill', ui.autows_weaponskill ~= '' and ui.autows_weaponskill or (config.autows.weaponskill or ''), 128)
    if changed then
        ui.autows_weaponskill = ws_value
        config.autows.weaponskill = trim(ui.autows_weaponskill)
    end

    v = { config.autows.use_aftermath ~= false }
    if imgui.Checkbox('Maintain Aftermath', v) then
        config.autows.use_aftermath = v[1]
    end

    local tp = { tonumber(config.autows.tp_amount) or 1000 }
    if labeled_slider_float('AutoWS TP', 'autows_tp', tp, 1000, 3000, '%.0f') then
        config.autows.tp_amount = math.floor(tp[1] + 0.5)
    end

    local aftermath_tp = { tonumber(config.autows.aftermath_tp_amount) or 3000 }
    if labeled_slider_float('Aftermath TP', 'autows_aftermath_tp', aftermath_tp, 1000, 3000, '%.0f') then
        config.autows.aftermath_tp_amount = math.floor(aftermath_tp[1] + 0.5)
    end

    local cooldown = { tonumber(config.autows.cooldown) or 3.0 }
    if labeled_slider_float('Cooldown Seconds', 'autows_cooldown_seconds', cooldown, 1.5, 15.0, '%.1f') then
        config.autows.cooldown = math.floor((cooldown[1] * 10) + 0.5) / 10
    end

    imgui.Separator()
    section_title('Skillchains')

    v = { config.autows.skillchains_enabled == true }
    if imgui.Checkbox('Enable Skillchain Helper', v) then
        config.autows.skillchains_enabled = v[1]
    end

    v = { config.autows.show_skillchain_window ~= false }
    if imgui.Checkbox('Show Skillchains Window', v) then
        config.autows.show_skillchain_window = v[1]
    end

    v = { config.autows.open_skillchains == true }
    if imgui.Checkbox('Open Skillchains', v) then
        config.autows.open_skillchains = v[1]
    end

    v = { config.autows.close_skillchains == true }
    if imgui.Checkbox('Close Skillchains', v) then
        config.autows.close_skillchains = v[1]
    end

    changed, ws_value = labeled_input('Opener Weaponskill:', 'autows_open_weaponskill', ui.autows_open_weaponskill ~= '' and ui.autows_open_weaponskill or (config.autows.open_weaponskill or ''), 128)
    if changed then
        ui.autows_open_weaponskill = ws_value
        config.autows.open_weaponskill = trim(ui.autows_open_weaponskill)
    end

    changed, ws_value = labeled_input('Allowed Levels (Priority):', 'autows_level_priority', ui.autows_level_priority ~= '' and ui.autows_level_priority or (config.autows.level_priority or '4,3,2,1'), 64)
    if changed then
        ui.autows_level_priority = ws_value
        config.autows.level_priority = trim(ui.autows_level_priority)
    end

    changed, ws_value = labeled_input('Chain Priority:', 'autows_chain_priority', ui.autows_chain_priority ~= '' and ui.autows_chain_priority or (config.autows.chain_priority or ''), 64)
    if changed then
        ui.autows_chain_priority = ws_value
        config.autows.chain_priority = trim(ui.autows_chain_priority)
    end

    changed, ws_value = labeled_input('Close WS Priority:', 'autows_close_ws_priority', ui.autows_close_ws_priority ~= '' and ui.autows_close_ws_priority or (config.autows.close_ws_priority or ''), 128)
    if changed then
        ui.autows_close_ws_priority = ws_value
        config.autows.close_ws_priority = trim(ui.autows_close_ws_priority)
    end

    changed, ws_value = labeled_input('Blacklist:', 'autows_blacklist', ui.autows_blacklist ~= '' and ui.autows_blacklist or (config.autows.blacklist or ''), 512)
    if changed then
        ui.autows_blacklist = ws_value
        config.autows.blacklist = trim(ui.autows_blacklist)
    end

    local open_tp = { tonumber(config.autows.open_tp_amount) or 1000 }
    if labeled_slider_float('Open TP', 'autows_open_tp', open_tp, 1000, 3000, '%.0f') then
        config.autows.open_tp_amount = math.floor(open_tp[1] + 0.5)
    end

    local close_tp = { tonumber(config.autows.close_tp_amount) or 1000 }
    if labeled_slider_float('Close TP', 'autows_close_tp', close_tp, 1000, 3000, '%.0f') then
        config.autows.close_tp_amount = math.floor(close_tp[1] + 0.5)
    end

    local window_minimum = { tonumber(config.autows.close_window_minimum) or 1.0 }
    if labeled_slider_float('Minimum Window Seconds', 'autows_close_window_minimum', window_minimum, 0, 10, '%.1f') then
        config.autows.close_window_minimum = math.floor((window_minimum[1] * 10) + 0.5) / 10
    end

    if scripts.autows and scripts.autows.get_status then
        local status = scripts.autows.get_status() or {}
        imgui.Separator()
        imgui.Text('TP: ' .. tostring(status.tp or 0))
        imgui.Text('Aftermath: ' .. (status.has_aftermath and ('Active (' .. tostring(status.aftermath_buff_id or 0) .. ')') or 'Inactive'))
        imgui.Text('Current Threshold: ' .. tostring(status.threshold or 0))
        imgui.Text('State: ' .. tostring(status.reason or 'Unknown'))
        imgui.Text('Status/Target: ' .. tostring(status.player_status or 0) .. ' / ' .. tostring(status.target_index or -1))
        if status.next_closer then
            imgui.Text('Next Closer: ' .. tostring(status.next_closer.weaponskill) .. ' -> ' .. tostring(status.next_closer.skillchain))
        end
    end

    imgui.Separator()
    if imgui.Button('Save AutoWS', { 140, 30 }) then
        config.autows.weaponskill = trim(ui.autows_weaponskill ~= '' and ui.autows_weaponskill or config.autows.weaponskill)
        config.autows.open_weaponskill = trim(ui.autows_open_weaponskill ~= '' and ui.autows_open_weaponskill or config.autows.open_weaponskill)
        config.autows.level_priority = trim(ui.autows_level_priority ~= '' and ui.autows_level_priority or config.autows.level_priority)
        config.autows.chain_priority = trim(ui.autows_chain_priority ~= '' and ui.autows_chain_priority or config.autows.chain_priority)
        config.autows.close_ws_priority = trim(ui.autows_close_ws_priority ~= '' and ui.autows_close_ws_priority or config.autows.close_ws_priority)
        config.autows.blacklist = trim(ui.autows_blacklist ~= '' and ui.autows_blacklist or config.autows.blacklist)
        if scripts.autows and scripts.autows.set_settings then
            scripts.autows.set_settings(config)
        end
        scripts.save(config)
    end
end

local function render_skillchain_window(config, scripts)
    if not config
    or not config.autows
    or config.autows.skillchains_enabled ~= true
    or config.autows.show_skillchain_window == false
    then
        return
    end

    if not scripts.autows or not scripts.autows.get_status then
        return
    end

    local status = scripts.autows.get_status() or {}
    local window = status.skillchain_window
    local closers = status.closers or {}

    if not window and #closers == 0 then
        return
    end

    imgui.SetNextWindowSize({ 360, 260 }, ImGuiCond_FirstUseEver)
    if not imgui.Begin('AutoBot Skillchains') then
        imgui.End()
        return
    end

    section_title('Skillchain Window')

    if window then
        imgui.Text('Opening WS: ' .. tostring(window.opener_name or 'Unknown'))
        local state = window.open and string.format('Open: %.1fs left', window.time_remaining or 0) or string.format('Opens in: %.1fs', window.opens_in or 0)
        imgui.Text(state)
        imgui.Text('Properties:')
        for _, attribute in ipairs(window.attributes or {}) do
            imgui.SameLine()
            imgui.TextColored(skillchain_color(attribute), tostring(attribute))
        end
    else
        imgui.Text('No active window.')
    end

    imgui.Separator()
    section_title('Closers')

    if #closers == 0 then
        imgui.Text('No known closers for the current target.')
    else
        local limit = math.min(#closers, 12)
        for i = 1, limit do
            local closer = closers[i]
            imgui.Text(string.format('Lv%d %s -> ', closer.level or 0, closer.weaponskill or '?'))
            imgui.SameLine()
            imgui.TextColored(skillchain_color(closer.skillchain), tostring(closer.skillchain or '?'))
        end
    end

    imgui.End()
end

local function render_items(config, scripts)
    section_title('Items')

    config.items = config.items or {}
    config.items.food = config.items.food or {}

    local food = config.items.food
    food.enabled = food.enabled == true
    food.name = food.name or ''
    food.retry_delay = tonumber(food.retry_delay) or 15

    local v = { b(food.enabled) }
    if imgui.Checkbox('Auto Food', v) then
        food.enabled = v[1]
    end

    local changed, food_value = labeled_input('Food Item:', 'item_food_name', ui.item_food_name ~= '' and ui.item_food_name or food.name, 128)
    if changed then
        ui.item_food_name = food_value
        food.name = trim(ui.item_food_name)
    end

    local retry = { food.retry_delay }
    if labeled_slider_float('Retry Delay Seconds', 'item_food_retry_delay', retry, 5, 120, '%.1f') then
        food.retry_delay = math.floor((retry[1] * 10) + 0.5) / 10
    end

    if scripts.items and scripts.items.get_status then
        local status = scripts.items.get_status() or {}
        imgui.Separator()
        imgui.Text('Food Buff: ' .. (status.has_food and 'Active' or 'Missing'))
        imgui.Text('Configured Food: ' .. tostring(status.food_name or food.name or ''))
        imgui.Text('Next Attempt: ' .. string.format('%.1f', tonumber(status.next_attempt) or 0) .. 's')
    end

    imgui.Separator()
    if imgui.Button('Use Food Now##item_use_food', { 130, 28 }) and scripts.items and scripts.items.use_food then
        food.name = trim(ui.item_food_name ~= '' and ui.item_food_name or food.name)
        scripts.items.use_food()
    end

    imgui.SameLine()
    if imgui.Button('Save Items##item_save', { 120, 28 }) then
        food.name = trim(ui.item_food_name ~= '' and ui.item_food_name or food.name)
        if scripts.items and scripts.items.set_config then
            scripts.items.set_config(config, scripts.save)
        end
        scripts.save(config)
    end
end

local function render_whitelist(config, scripts)
    section_title('Whitelist')

    local changed, player_value = labeled_input('Player Name:', 'whitelist_player_name', ui.new_whitelist, 128)
    if changed then
        ui.new_whitelist = player_value
    end
    if imgui.Button('Add Player', { 110, 0 }) then
        local new = trim(ui.new_whitelist):lower()
        if new ~= '' and not contains(config.whitelist, new) then
            table.insert(config.whitelist, new)
            ui.new_whitelist = ''
        end
    end

    imgui.BeginChild('whitelist', { 0, 260 }, child_flags_borders)
    for i, name in ipairs(config.whitelist) do
        imgui.Text(name)
        imgui.SameLine(260)
        if imgui.Button('Remove##whitelist_' .. i, { 90, 0 }) then
            table.remove(config.whitelist, i)
            break
        end
    end
    imgui.EndChild()

    if imgui.Button('Save Whitelist', { 140, 30 }) then
        scripts.save(config)
    end
end

local function render_navigation(config, scripts)
    section_title('Navigation')

    if not config.modules.navigation then
        imgui.TextDisabled('Enable Navigation on the Modules page first.')
        return
    end

    if not scripts.navigation then
        imgui.TextDisabled('Navigation module is not loaded.')
        return
    end

    local status = {}
    if scripts.navigation.get_status then
        status = scripts.navigation.get_status() or {}
    end

    local state = 'Idle'
    if status.recording then
        state = 'Recording'
    elseif status.playback and status.paused then
        state = 'Paused'
    elseif status.playback then
        state = 'Playing'
    end

    local paths = {}
    if scripts.navigation.list_paths then
        paths = scripts.navigation.list_paths() or {}
    end

    if ui.nav_selected_path == '' and #paths > 0 then
        ui.nav_selected_path = paths[1]
    end

    local selected_path = nav_path_name(ui.nav_selected_path)
    local has_selected_path = selected_path ~= ''
    local selected_details = nil
    if has_selected_path and scripts.navigation.get_path_details then
        selected_details = scripts.navigation.get_path_details(selected_path)
    end

    if ui.nav_detail_loaded_path ~= selected_path then
        ui.nav_detail_loaded_path = selected_path
        ui.nav_detail_zone_name = selected_details and selected_details.zone_name or ''
        ui.nav_detail_details = selected_details and selected_details.details or ''
    end

    imgui.Text('Status: ' .. state)
    if status.path_name and status.path_name ~= '' then
        imgui.SameLine()
        imgui.Text('Running: ' .. tostring(status.path_name))
    end
    imgui.Text('Points: ' .. tostring(status.point_count or 0))
    if status.recording and status.record_interval then
        imgui.SameLine()
        imgui.TextDisabled(string.format('Recording every %.1fs', tonumber(status.record_interval) or 0))
    elseif status.playback and status.playback_index then
        imgui.SameLine()
        imgui.TextDisabled('Waypoint: ' .. tostring(status.playback_index))
    end

    imgui.Separator()
    section_title('Playback Controls')

    local can_play = has_selected_path and not status.recording and not (status.playback and not status.paused)
    local can_pause = status.playback and not status.paused
    local can_stop = status.playback or status.recording

    if action_button(status.paused and 'Resume' or 'Play', can_play, { 90, 30 }) and can_play then
        if status.paused and scripts.navigation.resume_playback then
            scripts.navigation.resume_playback()
        elseif scripts.navigation.start_playback then
            scripts.navigation.start_playback(selected_path)
        end
    end
    imgui.SameLine()
    if action_button('Pause', can_pause, { 90, 30 }) and can_pause and scripts.navigation.pause_playback then
        scripts.navigation.pause_playback()
    end
    imgui.SameLine()
    if action_button('Stop', can_stop, { 90, 30 }) and can_stop then
        if status.recording and scripts.navigation.stop_record then
            scripts.navigation.stop_record()
        end
        if scripts.navigation.stop_playback then
            scripts.navigation.stop_playback()
        end
    end

    local v = { b(status.loop) }
    if imgui.Checkbox('Loop##nav_loop', v) and scripts.navigation.set_loop then
        scripts.navigation.set_loop(v[1])
    end
    imgui.SameLine()
    v = { b(status.reverse) }
    if imgui.Checkbox('Reverse##nav_reverse', v) and scripts.navigation.set_reverse then
        scripts.navigation.set_reverse(v[1])
    end
    imgui.SameLine()
    v = { b(status.bounce) }
    if imgui.Checkbox('Bounce (Back/Forth)##nav_bounce', v) and scripts.navigation.set_bounce then
        scripts.navigation.set_bounce(v[1])
    end

    if not has_selected_path then
        imgui.TextDisabled('Record a path first, then select it here for playback.')
    end

    imgui.Separator()
    section_title('Record Path')

    local changed, nav_value = labeled_input('Path Name:', 'nav_record_name', ui.nav_record_name, 128)
    if changed then
        ui.nav_record_name = nav_value
    end

    if ui.nav_record_zone_name == '' and scripts.navigation.get_current_zone then
        local current_zone = scripts.navigation.get_current_zone()
        if current_zone and current_zone.zone_name and current_zone.zone_name ~= '' then
            ui.nav_record_zone_name = current_zone.zone_name
        end
    end

    changed, nav_value = labeled_input('Zone Name:', 'nav_record_zone', ui.nav_record_zone_name, 128)
    if changed then
        ui.nav_record_zone_name = nav_value
    end

    changed, nav_value = labeled_input('Details:', 'nav_record_details', ui.nav_record_details, 512)
    if changed then
        ui.nav_record_details = nav_value
    end

    local record_name = nav_path_name(ui.nav_record_name)
    local can_record = record_name ~= '' and not status.recording and not status.playback
    if action_button('Record', can_record, { 100, 30 }) and can_record and scripts.navigation.start_record then
        scripts.navigation.start_record(record_name, ui.nav_record_zone_name, ui.nav_record_details)
        ui.nav_record_name = record_name
        ui.nav_selected_path = record_name
    end
    imgui.SameLine()
    local can_stop_record = status.recording and scripts.navigation.stop_record
    if action_button('Save & Stop##nav_record_stop', can_stop_record, { 120, 30 }) and can_stop_record then
        scripts.navigation.stop_record()
        ui.nav_detail_loaded_path = ''
    end
    if status.recording then
        imgui.SameLine()
        imgui.Text('Recorded Points: ' .. tostring(status.point_count or 0))
    end

    imgui.Separator()
    section_title('Saved Paths')

    imgui.BeginChild('nav_path_list', { 0, 170 }, child_flags_borders)
    if #paths == 0 then
        imgui.TextDisabled('No saved paths yet.')
    else
        for i, path_name in ipairs(paths) do
            if imgui.Selectable(path_name .. '##nav_path_' .. i, ui.nav_selected_path == path_name) then
                ui.nav_selected_path = path_name
                ui.nav_detail_loaded_path = ''
            end
        end
    end
    imgui.EndChild()

    imgui.Separator()
    section_title('Selected Path Details')

    if selected_details then
        imgui.Text('Path: ' .. selected_path)
        imgui.Text('Points: ' .. tostring(selected_details.point_count or 0))

        local changed, details_value = labeled_input('Zone Name:', 'nav_detail_zone', ui.nav_detail_zone_name, 128)
        if changed then
            ui.nav_detail_zone_name = details_value
        end

        changed, details_value = labeled_input('Details:', 'nav_detail_text', ui.nav_detail_details, 512)
        if changed then
            ui.nav_detail_details = details_value
        end

        if imgui.Button('Save Details##nav_save_details', { 120, 28 }) and scripts.navigation.update_path_details then
            scripts.navigation.update_path_details(selected_path, ui.nav_detail_zone_name, ui.nav_detail_details)
        end
        imgui.SameLine()
        if action_button('Delete Path##nav_delete_path', true, { 120, 28 }) and scripts.navigation.delete_path then
            scripts.navigation.delete_path(selected_path)
            ui.nav_selected_path = ''
            ui.nav_detail_loaded_path = ''
            ui.nav_detail_zone_name = ''
            ui.nav_detail_details = ''
        end
    else
        imgui.TextDisabled('Select a saved path to view details.')
    end
end

local function ability_available(job, ability, level)
    local required = job_ability_levels[job] and job_ability_levels[job][ability] or 1
    return (tonumber(level) or 0) >= required
end

local function render_ability_grid(job, settings, list, level)
    settings.abilities = settings.abilities or {}
    for _, ability in ipairs(list) do
        if ability_available(job, ability, level) then
            local v = { b(settings.abilities[ability]) }
            if imgui.Checkbox(title(ability) .. '##ability_' .. ability, v) then
                settings.abilities[ability] = v[1]
            end
        end
    end
end

local function render_whm(settings)
    local v = { b(settings.enable_cure) }
    if imgui.Checkbox('Cure Logic', v) then settings.enable_cure = v[1] end
    imgui.SameLine()
    v = { b(settings.enable_status) }
    if imgui.Checkbox('Status Removal', v) then settings.enable_status = v[1] end
    imgui.SameLine()
    v = { b(settings.enable_buffs) }
    if imgui.Checkbox('Buff Logic', v) then settings.enable_buffs = v[1] end

    imgui.Separator()
    settings.protectra_tier = combo_string('Protectra Tier', settings.protectra_tier, {
        'protectra1', 'protectra2', 'protectra3', 'protectra4', 'protectra5',
    })
    settings.shellra_tier = combo_string('Shellra Tier', settings.shellra_tier, {
        'shellra1', 'shellra2', 'shellra3', 'shellra4', 'shellra5',
    })

    imgui.Separator()
    settings.spells = settings.spells or {}
    for _, spell in ipairs(whm_spells) do
        local v2 = { b(settings.spells[spell]) }
        if imgui.Checkbox(title(spell) .. '##spell_' .. spell, v2) then
            settings.spells[spell] = v2[1]
        end
    end
end

local function render_run(settings, level)
    local levels = job_ability_levels.RUN
    local v = { b(settings.useSwipe) }
    if (tonumber(level) or 0) >= levels.useSwipe and imgui.Checkbox('Swipe', v) then settings.useSwipe = v[1] end
    v = { b(settings.useLunge) }
    if (tonumber(level) or 0) >= levels.useLunge and imgui.Checkbox('Lunge', v) then settings.useLunge = v[1] end
    v = { b(settings.useSwordplay) }
    if (tonumber(level) or 0) >= levels.useSwordplay and imgui.Checkbox('Swordplay', v) then settings.useSwordplay = v[1] end

    v = { b(settings.useVal) }
    if (tonumber(level) or 0) >= levels.useVal and imgui.Checkbox('Vallation', v) then settings.useVal = v[1] end
    v = { b(settings.usePflug) }
    if (tonumber(level) or 0) >= levels.usePflug and imgui.Checkbox('Pflug', v) then settings.usePflug = v[1] end

    imgui.Separator()
    settings.desiredSlots = settings.desiredSlots or {}
    settings.desiredSlots.slot1 = combo_string('Rune Slot 1', settings.desiredSlots.slot1 or 'ignis', rune_options)
    settings.desiredSlots.slot2 = combo_string('Rune Slot 2', settings.desiredSlots.slot2 or 'ignis', rune_options)
    settings.desiredSlots.slot3 = combo_string('Rune Slot 3', settings.desiredSlots.slot3 or 'ignis', rune_options)
end

local function render_brd(settings)
    local delay = { tonumber(settings.songDelay) or 15 }
    if labeled_slider_float('Song Delay', 'brd_song_delay', delay, 5, 30) then
        settings.songDelay = math.floor(delay[1] + 0.5)
    end

    settings.default = settings.default or {}
    for i = 1, 5 do
        local changed, song_value = labeled_input('Song ' .. tostring(i) .. ':', 'brd_song_' .. tostring(i), settings.default[i] or '', 128)
        if changed then
            settings.default[i] = trim(song_value)
        end
    end
end

local function job_status_for(scripts, role)
    if scripts.jobs and scripts.jobs.get_status then
        local status = scripts.jobs.get_status() or {}
        return status[role] or {}
    end

    return {}
end

local function render_job_panel(config, scripts, role, info, id_suffix)
    info = info or {}
    local job = info.job
    local level = tonumber(info.level) or 0
    id_suffix = id_suffix or role

    section_title((role == 'main' and 'MainJob' or 'SubJob') .. (job and (' - ' .. job .. ' ' .. tostring(level)) or ''))

    if not job then
        imgui.TextDisabled('No Job Script Found...')
        return
    end

    local module = nil
    if scripts.jobs and type(scripts.jobs.get_module) == 'function' then
        module = scripts.jobs.get_module(job)
    end

    local status = job_status_for(scripts, role)
    if module then
        status.loaded = true
        if not status.message or status.message == 'No Job Script Found...' then
            status.message = 'Loaded'
        end
    end

    imgui.Text('Script: ' .. tostring(status.message or (module and 'Loaded' or 'Pending load')))

    if status.loaded == false and not module then
        imgui.TextDisabled('No Job Script Found...')
    end

    local settings = ensure_job_settings(config, job)
    if not settings then
        imgui.TextDisabled('No Job Script Found...')
        return
    end

    local enabled = { b(settings.enabled) }
    if imgui.Checkbox('Enable ' .. job .. ' Module##job_enable_' .. id_suffix, enabled) then
        settings.enabled = enabled[1]
        if scripts.save then
            scripts.save()
        end
    end

    if status.running then
        imgui.TextDisabled('Runtime: Running')
    else
        imgui.TextDisabled('Runtime: Stopped')
    end

    imgui.Separator()

    if level <= 0 then
        imgui.TextDisabled('No job level detected yet.')
    else
        if module and type(module.render_ui) == 'function' then
            local changed = module.render_ui(imgui, settings, {
                id = id_suffix,
                level = level,
                combo = combo_string,
                save = function()
                    if scripts.save then
                        scripts.save()
                    end
                end,
            })
            if changed and scripts.save then
                scripts.save()
            end
            return
        end
    end

    if level > 0 and job_abilities[job] then
        render_ability_grid(job, settings, job_abilities[job], level)
    elseif job == 'WHM' then
        render_whm(settings)
    elseif job == 'RUN' then
        render_run(settings, level)
    elseif job == 'BRD' then
        render_brd(settings)
    else
        imgui.TextDisabled('No configurable options are defined for this job yet.')
    end
end

local function render_job_tabs()
    pcall(function()
        imgui.SetCursorPosX(math.max(imgui.GetCursorPosX(), (imgui.GetWindowWidth() - 206) * 0.5))
    end)

    local selected = ui.job_tab == 'main'
    if selected then imgui.PushStyleColor(ImGuiCol_Button, { 0.42, 0.31, 0.12, 1.0 }) end
    if imgui.Button('MainJob##job_tab_main', { 98, 30 }) then ui.job_tab = 'main' end
    if selected then imgui.PopStyleColor(1) end

    imgui.SameLine()

    selected = ui.job_tab == 'sub'
    if selected then imgui.PushStyleColor(ImGuiCol_Button, { 0.42, 0.31, 0.12, 1.0 }) end
    if imgui.Button('SubJob##job_tab_sub', { 98, 30 }) then ui.job_tab = 'sub' end
    if selected then imgui.PopStyleColor(1) end
end

local function get_render_job_info(scripts)
    if scripts.jobs and scripts.jobs.get_job_info then
        return scripts.jobs.get_job_info()
    end

    return current_jobs()
end

local function render_job_modules(config, scripts)
    section_title('Job Modules')
    imgui.TextDisabled('Job modules always load disabled and must be enabled each session.')

    local info = get_render_job_info(scripts)
    render_job_tabs()

    local show_windows = { config.ui.show_job_windows == true }
    if imgui.Checkbox('Show Individual Job Windows', show_windows) then
        config.ui.show_job_windows = show_windows[1]
        scripts.save(config)
    end

    local main_open = {
        ui.job_window_open.main == nil
            and config.ui.main_job_window_open ~= false
            or ui.job_window_open.main == true
    }
    if imgui.Checkbox('Open MainJob Window', main_open) then
        ui.job_window_open.main = main_open[1]
        config.ui.main_job_window_open = main_open[1]
        if main_open[1] then
            config.ui.show_job_windows = true
        end
        scripts.save(config)
    end

    local sub_open = {
        ui.job_window_open.sub == nil
            and config.ui.sub_job_window_open ~= false
            or ui.job_window_open.sub == true
    }
    if imgui.Checkbox('Open SubJob Window', sub_open) then
        ui.job_window_open.sub = sub_open[1]
        config.ui.sub_job_window_open = sub_open[1]
        if sub_open[1] then
            config.ui.show_job_windows = true
        end
        scripts.save(config)
    end

    imgui.Separator()

    local role = ui.job_tab == 'sub' and 'sub' or 'main'
    render_job_panel(config, scripts, role, info[role], 'embedded_' .. role)

    imgui.Separator()
    if imgui.Button('Save Job Modules', { 160, 30 }) then
        scripts.save(config)
    end
end

local function render_help_window()
    if not ui.help_open then
        return
    end

    imgui.SetNextWindowSize({ 620, 500 }, ImGuiCond_FirstUseEver)

    local help_open = { ui.help_open }
    if not imgui.Begin('AutoBot Help', help_open) then
        ui.help_open = help_open[1] == true
        imgui.End()
        return
    end
    ui.help_open = help_open[1] == true

    section_title('AutoBot Help')
    imgui.Separator()
    imgui.TextWrapped('Local commands use /ab or /autobot. Remote commands use party chat or direct tells from whitelisted players only. Remote forms are "bot <command>" or "!<command>".')

    imgui.Separator()
    section_title('Core')
    help_line('/ab ui', 'Toggle the AutoBot window.')
    help_line('/ab save', 'Save all current settings to the active character profile. Remote form: !save')
    help_line('/ab load', 'Reload the active character profile and discard unsaved changes. Remote form: !load')
    help_line('/ab reload', 'Alias for /ab load. Remote form: !reload')
    help_line('/ab debug on|off', 'Toggle diagnostic chat globally. Command-only setting.')
    help_line('/ab stop', 'Safety-pause all automation while preserving resumable runtime state.')
    help_line('/ab resume', 'Resume automation after a death pause or full stop.')
    help_line('/ab module <name> on|off|toggle', 'Enable, disable, or toggle a module.')
    help_line('/ab settings', 'Print enabled module states.')
    help_line('/ab whitelist add|remove|list <name>', 'Manage remote-command users.')
    help_line('!command <raw command>', 'Remote only: execute everything after !command directly, such as !command /ja "Spectral Jig".')

    imgui.Separator()
    section_title('Combat')
    help_line('/ab attack', 'Engage current target.')
    help_line('/ab disengage', 'Disengage from combat.')
    help_line('/ab assist <name>', 'Assist a player and attack their target.')
    help_line('/ab combat autoengage on|off', 'Toggle automatic engagement.')
    help_line('/ab combat approach on|off', 'Toggle automatic melee approach.')
    help_line('/ab combat autoassist on|off', 'Toggle Auto-Assist.')
    help_line('/ab combat assisttarget <name>', 'Set the Auto-Assist target.')
    help_line('/ab combat autoface on|off', 'Toggle combat auto-facing.')
    help_line('/ab face <degrees>', 'Set the player rotation directly.')
    help_line('/ab facecheck', 'Print auto-face diagnostics.')

    imgui.Separator()
    section_title('AutoWS And Skillchains')
    help_line('/ab autows on|off', 'Toggle AutoWS.')
    help_line('/ab autows ws <name>', 'Set the weapon skill.')
    help_line('/ab autows tp <1000-3000>', 'Set normal TP threshold.')
    help_line('/ab autows cooldown <seconds>', 'Set the delay between weapon skills.')
    help_line('/ab autows aftermath on|off', 'Toggle Aftermath maintenance.')
    help_line('/ab autows aftermathtp <1000-3000>', 'Set the TP threshold used to maintain Aftermath.')
    help_line('/ab autows sc on|off', 'Toggle the skillchain helper display and logic.')
    help_line('/ab autows open on|off', 'Toggle automatic skillchain opening.')
    help_line('/ab autows close on|off', 'Toggle automatic skillchain closing.')
    help_line('/ab autows opener <name>', 'Set the opening weapon skill.')
    help_line('/ab autows opentp <1000-3000>', 'Set the opening weapon skill TP threshold.')
    help_line('/ab autows closetp <1000-3000>', 'Set the closing weapon skill TP threshold.')
    help_line('/ab autows priority 4,3,2,1', 'Set allowed skillchain levels and their priority.')
    help_line('/ab autows chain Light|Darkness', 'Prefer a specific skillchain result.')
    help_line('/ab autows closews <name>', 'Set the WS AutoWS may use to close chains.')
    help_line('/ab autows blacklist <names>', 'Set comma-separated weapon skills AutoWS must not use as closers.')
    help_line('/ab autows status', 'Print current AutoWS state.')
    help_line('Show Skillchains Window', 'AutoWS-page checkbox; hides only the standalone display.')

    imgui.Separator()
    section_title('Items')
    help_line('/ab item on|off|toggle', 'Toggle automatic food usage.')
    help_line('/ab item food <name>', 'Set the food item used when no food buff is active.')
    help_line('/ab item delay <seconds>', 'Set retry delay between food-use attempts.')
    help_line('/ab item use', 'Use the configured food immediately.')
    help_line('/ab food <name>', 'Shortcut for setting the food item.')

    imgui.Separator()
    section_title('Targeting And Pulling')
    help_line('/ab target start|stop', 'Start or stop targeting.')
    help_line('/ab target add|remove|list <name>', 'Manage target names.')
    help_line('/ab pull start|stop', 'Start or stop pulling.')
    help_line('/ab pull method spell|ability|ranged <action>', 'Set pull method.')
    help_line('/ab pull timeout <seconds>', 'Set pull timeout.')

    imgui.Separator()
    section_title('Navigation')
    help_line('/ab nav record <path>', 'Start recording a path.')
    help_line('/ab nav stop', 'Stop playback, or save and stop the active recording.')
    help_line('/ab nav start <path>', 'Play a saved path.')
    help_line('/ab nav pause|resume', 'Control playback.')
    help_line('/ab nav loop|reverse|bounce on|off', 'Toggle playback modes.')
    help_line('/ab nav list|details|delete <path>', 'Manage saved paths.')
    help_line('/ab nav setdetails <path> <zone> <text>', 'Update saved path metadata.')

    imgui.Separator()
    section_title('Trusts')
    help_line('/ab trust <set>', 'Summon a saved set. Example: /ab trust default')
    help_line('/ab trust save <set>', 'Save currently summoned trusts as a set.')
    help_line('/ab trust create <set> <trusts...>', 'Create a set from supplied trust names.')
    help_line('/ab trust add <set> <trust>', 'Add a validated trust to a set.')
    help_line('/ab trust remove <set> <index>', 'Remove a trust by position.')
    help_line('/ab trust delete <set>', 'Delete a saved trust set.')
    help_line('/ab trust release <trust>', 'Release one trust.')
    help_line('/ab trust releaseall', 'Release all trusts.')
    help_line('/ab trust random', 'Summon a random set.')
    help_line('/ab trust list', 'Print all saved trust sets.')

    imgui.Separator()
    section_title('Job Modules')
    help_line('Startup behavior', 'All job modules load disabled and require explicit session enablement.')
    help_line('/ab job main|sub|<job> status', 'Show job-module status.')
    help_line('/ab job main|sub|<job> start|stop|toggle', 'Control the selected job module.')
    help_line('/ab job <job> enable|disable', 'Persistently enable or disable a job module.')

    imgui.Separator()
    section_title('Utility')
    help_line('/ab follow <name>', 'Follow a player.')
    help_line('/ab followme', 'Remote shortcut: follow the sender.')
    help_line('/ab stopfollow', 'Stop following.')
    help_line('/ab cast <spell> [target]', 'Cast a spell.')
    help_line('/ab ability|abil <name> [target]', 'Use a job ability; target defaults to <me>.')
    help_line('/ab move <yalms> <direction>', 'Distance and direction may be in either order. Supports N, NE, E, SE, S, SW, W, NW.')
    help_line('/ab stopcasting', 'Cancel the active casting helper.')
    help_line('/ab rest', 'Rest or heal.')
    help_line('/ab join|leave|disband', 'Control party membership.')
    help_line('/ab invite <name>', 'Invite a player.')
    help_line('/ab leader <name>', 'Pass party leadership.')
    help_line('!inviteme', 'Remote only: invite the issuing player.')
    help_line('!passleader [name]', 'Remote only: pass leadership to the issuer when no name is supplied.')
    help_line('!assist [name]', 'Remote only: assist the issuer when no name is supplied.')
    help_line('!fullstop', 'Remote only: safety-pause all automation until /ab resume.')
    help_line('!resume', 'Remote only: resume automation after a death pause or full stop.')
    help_line('!mountup', 'Remote only: select a random currently available mount.')
    help_line('!mountlist', 'Remote only: list mounts AutoBot detects as available.')
    help_line('!ability|!abil <name> [target]', 'Remote only: use a job ability; target defaults to <me>.')
    help_line('!move <yalms> <direction>', 'Remote only: distance and direction may be in either order; shorthand and full names work.')
    help_line('!tnpc <NPC name>', 'Remote only: quickly cycle nearby targets until the named NPC is selected.')
    help_line('Remote format', 'Whitelisted party/tell users may run any command as !<command> or bot <command>.')
    help_line('/ab mount <name>', 'Mount up.')
    help_line('/ab mountlist', 'List mounts AutoBot detects as available.')
    help_line('/ab dismount', 'Dismount.')
    help_line('/ab warpring', 'Use the configured warp ring behavior.')
    help_line('/ab trade <name> | !trademe', 'Clear open menus and initiate a trade with the named player or remote-command sender.')
    help_line('/ab accepttrade | !accepttrade', 'Select and confirm acceptance in an open trade window.')
    help_line('/ab canceltrade | !canceltrade', 'Cancel or close the active trade window.')
    help_line('/ab tnpc|npc <NPC name>', 'Quickly cycle nearby targets until the named NPC is selected.')
    help_line('/ab key <name>', 'Press a supported interaction key.')
    help_line('/ab warp <type> <location> [index]', "Forward to UberWarp. Example: /ab warp hp Southern San d'Oria 2.")

    imgui.End()
end

local function render_job_windows(config, scripts)
    if not config or not config.ui or config.ui.show_job_windows ~= true then
        return
    end

    local info = get_render_job_info(scripts)

    for _, role in ipairs({ 'main', 'sub' }) do
        if ui.job_window_open[role] == nil then
            local config_key = role == 'main'
                and 'main_job_window_open'
                or 'sub_job_window_open'
            ui.job_window_open[role] = config.ui[config_key] ~= false
        end

        if ui.job_window_open[role] then
            local open = { true }
            local label = role == 'main' and 'AutoBot MainJob' or 'AutoBot SubJob'
            local job = info[role] and info[role].job or nil
            imgui.SetNextWindowSize({ 420, 430 }, ImGuiCond_FirstUseEver)

            if imgui.Begin(label .. (job and (' - ' .. job) or ''), open) then
                render_job_panel(config, scripts, role, info[role], 'window_' .. role)
                imgui.Separator()
                if imgui.Button('Save Job Modules##job_window_save_' .. role, { 160, 30 }) then
                    scripts.save(config)
                end
            end
            imgui.End()

            local still_open = open[1] == true
            if ui.job_window_open[role] ~= still_open then
                local config_key = role == 'main'
                    and 'main_job_window_open'
                    or 'sub_job_window_open'
                config.ui[config_key] = still_open
                scripts.save(config)
            end
            ui.job_window_open[role] = still_open
        end
    end
end

local function render_trusts(config, scripts)
    section_title('Trusts')

    if not config.modules.trusts then
        imgui.TextDisabled('Enable Trusts on the Modules page first.')
        return
    end

    if not scripts.trusts then
        imgui.TextDisabled('Trust module is not loaded.')
        return
    end

    config.trusts = config.trusts or {}
    config.trusts.monitor = config.trusts.monitor or {}
    config.trusts.monitor.watched = config.trusts.monitor.watched or {}

    pcall(function()
        imgui.SetCursorPosX(math.max(imgui.GetCursorPosX(), (imgui.GetWindowWidth() - 206) * 0.5))
    end)
    trust_tab('Sets##trust_tab_sets', 'sets', 98)
    imgui.SameLine()
    trust_tab('Monitor##trust_tab_monitor', 'monitor', 108)
    imgui.Separator()

    if ui.trust_tab == 'monitor' then
        section_title('Trust Monitoring')

        local enabled = { config.trusts.monitor.enabled == true }
        if imgui.Checkbox('Enable Monitoring', enabled) then
            config.trusts.monitor.enabled = enabled[1]
        end

        local resummon_dead = { config.trusts.monitor.resummon_dead == true }
        if imgui.Checkbox('Re-Summon Dead Trusts', resummon_dead) then
            config.trusts.monitor.resummon_dead = resummon_dead[1]
        end

        local hp_threshold = { math.floor((tonumber(config.trusts.monitor.hp_threshold) or 30) + 0.5) }
        if labeled_slider_int('HP Threshold', 'trust_monitor_hp_threshold', hp_threshold, 0, 100) then
            config.trusts.monitor.hp_threshold = hp_threshold[1]
        end

        local mp_threshold = { math.floor((tonumber(config.trusts.monitor.mp_threshold) or 10) + 0.5) }
        if labeled_slider_int('MP Threshold', 'trust_monitor_mp_threshold', mp_threshold, 0, 100) then
            config.trusts.monitor.mp_threshold = mp_threshold[1]
        end

        imgui.Separator()
        section_title('Currently Summoned')

        local active_details = {}
        if scripts.trusts.get_active_details then
            active_details = scripts.trusts.get_active_details() or {}
        end

        if #active_details == 0 then
            imgui.TextDisabled('No summoned trusts detected.')
        else
            imgui.BeginChild('trust_monitor_active_list', { 0, 260 }, child_flags_borders)
            for i, detail in ipairs(active_details) do
                local key = detail.key or tostring(i)
                local watched = { config.trusts.monitor.watched[key] == true }
                if imgui.Checkbox('##trust_watch_' .. key, watched) then
                    config.trusts.monitor.watched[key] = watched[1]
                    if scripts.trusts.set_monitor_watched then
                        scripts.trusts.set_monitor_watched(detail.name, watched[1])
                    end
                end
                imgui.SameLine()
                imgui.Text(detail.name)
                imgui.SameLine(230)
                imgui.Text('HP: ' .. (detail.hp and tostring(math.floor(detail.hp + 0.5)) .. '%' or 'n/a'))
                imgui.SameLine(320)
                imgui.Text('MP: ' .. (detail.mp and tostring(math.floor(detail.mp + 0.5)) .. '%' or 'n/a'))
            end
            imgui.EndChild()
        end

        imgui.Separator()
        if imgui.Button('Save Trust Monitoring', { 170, 30 }) then
            scripts.save(config)
        end
        return
    end

    local sets = {}
    if scripts.trusts.list_sets then
        sets = scripts.trusts.list_sets() or {}
    end

    if ui.trust_selected_set == '' then
        ui.trust_selected_set = config.trusts.selected_set or sets[1] or 'default'
    end

    if #sets > 0 then
        imgui.Text('Saved Sets:')
        ui.trust_selected_set = combo_string('##trust_saved_sets', ui.trust_selected_set, sets)
        config.trusts.selected_set = ui.trust_selected_set
    else
        imgui.TextDisabled('No saved trust sets.')
    end

    local selected_set = ui.trust_selected_set
    local current_set = {}
    if selected_set ~= '' and scripts.trusts.get_set then
        current_set = scripts.trusts.get_set(selected_set) or {}
    end

    if imgui.Button('Summon Set##trust_summon', { 110, 28 }) and selected_set ~= '' and scripts.trusts.summon_set then
        scripts.trusts.summon_set(selected_set)
    end
    imgui.SameLine()
    if imgui.Button('Release All##trust_release_all', { 135, 28 }) and scripts.trusts.release_all then
        scripts.trusts.release_all()
    end
    imgui.SameLine()
    if imgui.Button('Random##trust_random', { 80, 28 }) and scripts.trusts.summon_random then
        scripts.trusts.summon_random()
    end

    local auto = { config.trusts.auto ~= false }
    if imgui.Checkbox('Auto Continue Summoning', auto) then
        config.trusts.auto = auto[1]
    end

    imgui.Separator()
    section_title('Selected Set')
    imgui.BeginChild('trust_selected_set_members', { 0, 125 }, child_flags_borders)
    if #current_set == 0 then
        imgui.TextDisabled('This set is empty.')
    else
        for i, trust in ipairs(current_set) do
            imgui.Text(tostring(i) .. '. ' .. trust)
            imgui.SameLine(260)
            if imgui.Button('Remove##trust_remove_' .. i, { 90, 0 }) and scripts.trusts.remove_from_set then
                scripts.trusts.remove_from_set(selected_set, i)
                break
            end
        end
    end
    imgui.EndChild()

    local trust_options = {}
    if scripts.trusts.get_trust_options then
        trust_options = scripts.trusts.get_trust_options() or {}
    end

    if ui.trust_selected_trust == '' then
        ui.trust_selected_trust = config.trusts.selected_trust or trust_options[1] or ''
    end

    if #trust_options > 0 then
        ui.trust_selected_trust = combo_string('Trust', ui.trust_selected_trust, trust_options)
        config.trusts.selected_trust = ui.trust_selected_trust
        local can_add = selected_set ~= '' and #current_set < 5
        if imgui.Button('Add To Set##trust_add_to_set', { 110, 28 }) and can_add and scripts.trusts.add_to_set then
            scripts.trusts.add_to_set(selected_set, ui.trust_selected_trust)
        end
        if #current_set >= 5 then
            imgui.TextDisabled('Set is full.')
        end
    end

    imgui.Separator()
    section_title('Save Current Trusts')

    local changed, set_value = labeled_input('Set Name:', 'trust_set_name', ui.trust_set_name, 128)
    if changed then
        ui.trust_set_name = set_value
    end

    local set_name = trim(ui.trust_set_name)
    local can_create = set_name ~= ''
    if imgui.Button('Save Current Trusts##trust_save_current', { 190, 28 }) and can_create and scripts.trusts.save_set then
        if scripts.trusts.save_set(set_name) then
            ui.trust_selected_set = set_name
            config.trusts.selected_set = set_name
        end
    end
    imgui.SameLine()
    if imgui.Button('Delete Set##trust_delete_set', { 100, 28 }) and selected_set ~= '' and scripts.trusts.delete_set then
        scripts.trusts.delete_set(selected_set)
        ui.trust_selected_set = ''
    end

    imgui.Separator()
    section_title('Currently Summoned')
    local active = {}
    if scripts.trusts.get_active then
        active = scripts.trusts.get_active() or {}
    end

    if #active == 0 then
        imgui.TextDisabled('No summoned trusts detected.')
    else
        imgui.BeginChild('trust_active_list', { 0, 90 }, child_flags_borders)
        for _, trust in ipairs(active) do
            imgui.Text(trust)
            imgui.SameLine(260)
            if imgui.Button('Release##trust_release_' .. trust, { 90, 0 }) and scripts.trusts.release then
                scripts.trusts.release(trust)
            end
        end
        imgui.EndChild()
    end

    imgui.Separator()
    if imgui.Button('Save Trusts', { 140, 30 }) then
        scripts.save(config)
    end
end

local function push_style()
    imgui.PushStyleColor(ImGuiCol_WindowBg, { 0.08, 0.09, 0.10, 0.96 })
    imgui.PushStyleColor(ImGuiCol_ChildBg, { 0.11, 0.12, 0.13, 0.92 })
    imgui.PushStyleColor(ImGuiCol_Border, { 0.28, 0.25, 0.18, 1.0 })
    imgui.PushStyleColor(ImGuiCol_FrameBg, { 0.16, 0.17, 0.18, 1.0 })
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, { 0.22, 0.23, 0.25, 1.0 })
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, { 0.24, 0.25, 0.27, 1.0 })
    imgui.PushStyleColor(ImGuiCol_Button, { 0.17, 0.18, 0.20, 1.0 })
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.25, 0.26, 0.29, 1.0 })
    imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.30, 0.28, 0.22, 1.0 })
    imgui.PushStyleColor(ImGuiCol_CheckMark, { 0.86, 0.68, 0.32, 1.0 })
    imgui.PushStyleColor(ImGuiCol_Header, { 0.24, 0.25, 0.27, 1.0 })
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, { 0.31, 0.32, 0.35, 1.0 })
    imgui.PushStyleColor(ImGuiCol_HeaderActive, { 0.42, 0.31, 0.12, 1.0 })
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 12, 12 })
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 7, 5 })
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 8, 7 })
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4.0)
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6.0)
    imgui.PushStyleVar(ImGuiStyleVar_ChildRounding, 4.0)
end

local function pop_style()
    imgui.PopStyleVar(6)
    imgui.PopStyleColor(13)
end

ui.render = function(config, scripts)
    if not config or not scripts then return end

    -- Standalone combat windows must render independently of the main
    -- configuration window. Otherwise closing AutoBot also hides them.
    render_skillchain_window(config, scripts)
    render_job_windows(config, scripts)

    if not ui.open or not scripts.save then return end

    config.modules = config.modules or {}
    config.target_list = config.target_list or {}
    config.whitelist = config.whitelist or {}
    config.targeting = config.targeting or {}
    config.pulling = config.pulling or {}
    config.combat = config.combat or {}
    config.autows = config.autows or {}
    config.items = config.items or {}
    config.items.food = config.items.food or {}
    config.trusts = config.trusts or {}
    config.job_modules = config.job_modules or {}
    config.ui = config.ui or {}

    if ui.pull_spell == '' then ui.pull_spell = config.pulling.spell or '' end
    if ui.pull_ability == '' then ui.pull_ability = config.pulling.ability or '' end
    if ui.autows_weaponskill == '' then ui.autows_weaponskill = config.autows.weaponskill or '' end
    if ui.autows_open_weaponskill == '' then ui.autows_open_weaponskill = config.autows.open_weaponskill or '' end
    if ui.autows_level_priority == '' then ui.autows_level_priority = config.autows.level_priority or '4,3,2,1' end
    if ui.autows_chain_priority == '' then ui.autows_chain_priority = config.autows.chain_priority or '' end
    if ui.autows_close_ws_priority == '' then ui.autows_close_ws_priority = config.autows.close_ws_priority or '' end
    if ui.autows_blacklist == '' then ui.autows_blacklist = config.autows.blacklist or '' end
    if ui.item_food_name == '' then ui.item_food_name = config.items.food.name or '' end
    if ui.combat_assist_target == '' then ui.combat_assist_target = config.combat.assist_target or '' end
    if ui.trust_selected_set == '' then ui.trust_selected_set = config.trusts.selected_set or '' end
    if ui.trust_selected_trust == '' then ui.trust_selected_trust = config.trusts.selected_trust or '' end

    imgui.SetNextWindowSize({ 680, 500 }, ImGuiCond_FirstUseEver)
    push_style()

    local main_open = { ui.open }
    if not imgui.Begin('AutoBot', main_open) then
        ui.open = main_open[1] == true
        imgui.End()
        pop_style()
        return
    end
    ui.open = main_open[1] == true

    imgui.BeginChild('AutoBotNav', { 190, 0 }, child_flags_borders)
    section_title('AutoBot')
    nav_button('Main', 'main')
    nav_button('Modules', 'modules')
    nav_button('Job Modules', 'job_modules')
    nav_button('Targeting', 'targeting')
    nav_button('Pulling', 'pulling')
    nav_button('Combat', 'combat')
    nav_button('AutoWS', 'autows')
    nav_button('Items', 'items')
    nav_button('Navigation', 'navigation')
    nav_button('Trusts', 'trusts')
    nav_button('Whitelist', 'whitelist')

    pcall(function()
        local nav_height = imgui.GetWindowHeight()
        imgui.SetCursorPosY(math.max(imgui.GetCursorPosY(), nav_height - 48))
    end)
    if imgui.Button('Help', { 170, 30 }) then
        ui.help_open = true
    end
    imgui.EndChild()

    imgui.SameLine()

    imgui.BeginChild('AutoBotContent', { 0, 0 }, child_flags_borders)
    if ui.page == 'main' then
        render_main(config, scripts)
    elseif ui.page == 'modules' then
        render_modules(config, scripts)
    elseif ui.page == 'job_modules' then
        render_job_modules(config, scripts)
    elseif ui.page == 'targeting' then
        render_targeting(config, scripts)
    elseif ui.page == 'pulling' then
        render_pulling(config, scripts)
    elseif ui.page == 'combat' then
        render_combat(config, scripts)
    elseif ui.page == 'autows' then
        render_autows(config, scripts)
    elseif ui.page == 'items' then
        render_items(config, scripts)
    elseif ui.page == 'navigation' then
        render_navigation(config, scripts)
    elseif ui.page == 'trusts' then
        render_trusts(config, scripts)
    elseif ui.page == 'whitelist' then
        render_whitelist(config, scripts)
    end
    imgui.EndChild()

    imgui.End()
    pop_style()

    render_help_window()
end

function ui.toggle()
    ui.open = not ui.open
end

function ui.show()
    ui.open = true
end

return ui
