local PUP = {}
local action_state = require('job_helpers.action_state')

local active = false
local settings = nil
local last_engine = 0

local recast_ids = {
    Activate = 205,
    Repair = 206,
    Deploy = 207,
    Cooldown = 114,
    Maintenance = 214,
}

local maneuver_options = {
    { value = -1, label = 'Disabled', ability = nil },
    { value = 0, label = 'Dark', ability = 'Dark Maneuver' },
    { value = 1, label = 'Light', ability = 'Light Maneuver' },
    { value = 2, label = 'Earth', ability = 'Earth Maneuver' },
    { value = 3, label = 'Wind', ability = 'Wind Maneuver' },
    { value = 4, label = 'Fire', ability = 'Fire Maneuver' },
    { value = 5, label = 'Ice', ability = 'Ice Maneuver' },
    { value = 6, label = 'Thunder', ability = 'Thunder Maneuver' },
    { value = 7, label = 'Water', ability = 'Water Maneuver' },
}

local maneuvers = {
    { 'Dark Maneuver', 0 },
    { 'Light Maneuver', 0 },
    { 'Earth Maneuver', 0 },
    { 'Wind Maneuver', 0 },
    { 'Fire Maneuver', 0 },
    { 'Ice Maneuver', 0 },
    { 'Thunder Maneuver', 0 },
    { 'Water Maneuver', 0 },
    { 'Overload', 0 },
}

local state = {
    enabled = false,
    pet_hp_pct = 0,
    pet_mp_pct = 0,
    oils = 0,
    pet_index = 0,
    deploy = false,
    activate = false,
    auto_repair = false,
    auto_maintenance = false,
    maneuvers = { 'Disabled', 'Disabled', 'Disabled' },
}

local function echo(message)
    windower.add_to_chat(207, '[AutoBot:PUP] ' .. tostring(message))
end

local function queue(command)
    AshitaCore:GetChatManager():QueueCommand(1, command)
end

local function get_player() return AshitaCore:GetMemoryManager():GetPlayer() end
local function get_party() return AshitaCore:GetMemoryManager():GetParty() end
local function get_entity() return AshitaCore:GetMemoryManager():GetEntity() end
local function get_target() return AshitaCore:GetMemoryManager():GetTarget() end

local function ensure()
    settings = settings or {}
    settings.maneuvers = settings.maneuvers or { -1, -1, -1 }
    for i = 1, 3 do
        settings.maneuvers[i] = tonumber(settings.maneuvers[i]) or -1
    end
    settings.autodeploy = settings.autodeploy == true
    settings.activate = settings.activate == true
    settings.autorepair = tonumber(settings.autorepair) or 40
    settings.autocooldown = settings.autocooldown ~= false
    settings.automaintenance = settings.automaintenance == true
    settings.autolight_enabled = settings.autolight_enabled == true
    settings.autolight_hp = tonumber(settings.autolight_hp) or 0
end

local function count_item_id(id)
    local total = 0
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    if not inv then return 0 end
    for i = 0, 80 do
        local ok, item = pcall(function()
            return inv:GetContainerItem(0, i)
        end)
        if ok and item and item.Id == id then
            total = total + (item.Count or 0)
        end
    end
    return total
end

local function ability_recast(id)
    local ok, recast = pcall(function()
        return AshitaCore:GetMemoryManager():GetRecast()
    end)
    if ok and recast and recast.GetAbilityTimer then
        local ok_timer, timer = pcall(function()
            return recast:GetAbilityTimer(id)
        end)
        return ok_timer and tonumber(timer) or 0
    end
    return 0
end

local function get_maneuver_recast()
    local recast = AshitaCore:GetMemoryManager():GetRecast()
    local rm = AshitaCore:GetResourceManager()
    if not recast or not rm then return 0 end

    for x = 0, 31 do
        local ok_id, id = pcall(function() return recast:GetAbilityTimerId(x) end)
        local ok_timer, timer = pcall(function() return recast:GetAbilityTimer(x) end)
        if ok_id and ok_timer and (id ~= 0 or x == 0) and tonumber(timer or 0) > 0 then
            local ok_ability, ability = pcall(function()
                return rm:GetAbilityByTimerId(id)
            end)
            if ok_ability and ability and ability.Name and ability.Name[1] and tostring(ability.Name[1]):find('Maneuver') then
                return tonumber(timer) or 0
            end
        end
    end
    return 0
end

local function get_pet()
    local party = get_party()
    local entity = get_entity()
    if not party or not entity then return nil, 0 end
    local ok_index, player_index = pcall(function()
        return party:GetMemberTargetIndex(0)
    end)
    if not ok_index or not player_index then return nil, 0 end
    local ok_pet, pet_index = pcall(function()
        return entity:GetPetTargetIndex(player_index)
    end)
    if not ok_pet or not pet_index or pet_index == 0 then return nil, 0 end
    local ok_raw, pet = pcall(function()
        return entity:GetRawEntity(pet_index)
    end)
    return ok_raw and pet or nil, pet_index
end

local function count_maneuvers()
    for i = 1, #maneuvers do
        maneuvers[i][2] = 0
    end

    local player = get_player()
    if not player or not player.GetBuffs then return end
    local ok_buffs, buffs = pcall(function()
        return player:GetBuffs()
    end)
    if not ok_buffs or not buffs then return end

    for _, buff in pairs(buffs) do
        local ok_name, name = pcall(function()
            return AshitaCore:GetResourceManager():GetString('buffs.names', buff)
        end)
        if ok_name and name then
            for i = 1, #maneuvers do
                if name == maneuvers[i][1] then
                    maneuvers[i][2] = maneuvers[i][2] + 1
                end
            end
        end
    end
end

local function selected_label(value)
    value = tonumber(value) or -1
    for _, option in ipairs(maneuver_options) do
        if option.value == value then
            return option.label
        end
    end
    return 'Disabled'
end

local function run_engine()
    ensure()
    if action_state.is_busy() then
        return
    end

    local oils = count_item_id(19185)
    state.oils = oils

    local player = get_player()
    local party = get_party()
    local entity = get_entity()
    if not player or not party or not entity then
        state.enabled = false
        return
    end

    local main_job = player.GetMainJob and player:GetMainJob() or 0

    if main_job ~= 18 then
        state.enabled = false
        return
    end

    state.enabled = active
    if not active then return end

    local pet, pet_index = get_pet()
    state.pet_index = pet_index

    if settings.activate and (not pet or pet.HP == 0) and ability_recast(recast_ids.Activate) == 0 then
        queue('/ja "Activate" <me>')
        return
    end

    local target = get_target()
    local target_index = target and target:GetTargetIndex(0) or 0

    if pet then
        if target_index ~= 0
            and settings.autodeploy
            and entity:GetStatus(party:GetMemberTargetIndex(0)) == 1
            and entity:GetStatus(pet_index) == 0
            and entity:GetHPPercent(target_index) > 10 then
            queue('/ja "Deploy" <t>')
            return
        end

        state.pet_hp_pct = entity:GetHPPercent(pet_index)
        state.pet_mp_pct = 0
    else
        state.pet_hp_pct = 0
        state.pet_mp_pct = 0
    end

    count_maneuvers()

    if settings.autocooldown and ability_recast(recast_ids.Cooldown) == 0 and maneuvers[9][2] ~= 0 then
        queue('/ja "Cooldown" <me>')
        return
    end

    if settings.automaintenance and pet and ability_recast(recast_ids.Maintenance) == 0 then
        local ok_buffs, pet_buffs = pcall(function()
            return entity:GetBuffs(pet_index)
        end)
        if ok_buffs and pet_buffs then
            for _, b in pairs(pet_buffs) do
                if b == 2 or b == 3 or b == 4 or b == 5 or b == 6 or b == 10 or b == 11 or b == 12 then
                    queue('/ja "Maintenance" <me>')
                    return
                end
            end
        end
    end

    if settings.autolight_enabled and pet and entity:GetHPPercent(pet_index) < settings.autolight_hp then
        settings.maneuvers[1] = 1
    end

    if get_maneuver_recast() == 0 and maneuvers[9][2] == 0 then
        for slot = 1, 3 do
            local holder = tonumber(settings.maneuvers[slot]) or -1
            if holder ~= -1 then
                local idx = holder + 1
                if maneuvers[idx] and maneuvers[idx][2] == 0 then
                    queue('/ja "' .. maneuvers[idx][1] .. '" <me>')
                    return
                end
            end
        end
    end

    if pet and ability_recast(recast_ids.Repair) == 0 and oils > 0 and state.pet_hp_pct < settings.autorepair then
        local ok_distance, distance = pcall(function()
            return entity:GetDistance(pet_index)
        end)
        if ok_distance and tonumber(distance or 999) < 20 then
            queue('/ja "Repair" <me>')
        end
    end
end

function PUP.init(job_settings)
    settings = job_settings or {}
    ensure()
    echo('Module initialized.')
end

function PUP.start()
    ensure()
    active = true
    echo('Module started.')
end

function PUP.stop()
    active = false
    echo('Module stopped.')
end

function PUP.tick()
    if (os.clock() - last_engine) < 0.25 then return end
    last_engine = os.clock()
    run_engine()
end

local function command_key(value)
    return tostring(value or ''):lower():gsub('[^%w]', '')
end

function PUP.command(cmd, args)
    ensure()
    args = args or {}
    cmd = command_key(cmd)
    if cmd == 'start' or cmd == 'on' or cmd == 'toggle' then
        if cmd == 'toggle' then active = not active else active = true end
        echo('Automation: ' .. (active and 'On' or 'Off'))
        return
    end
    if cmd == 'stop' or cmd == 'off' then active = false; echo('Automation: Off'); return end
    if cmd == 'deploy' then settings.autodeploy = not settings.autodeploy; echo('Auto Deploy: ' .. tostring(settings.autodeploy)); return end
    if cmd == 'activate' then settings.activate = not settings.activate; echo('Auto Activate: ' .. tostring(settings.activate)); return end
    if cmd == 'maintenance' then settings.automaintenance = not settings.automaintenance; echo('Auto Maintenance: ' .. tostring(settings.automaintenance)); return end
    if cmd == 'repair' and args[1] then settings.autorepair = tonumber(args[1]) or settings.autorepair; echo('Repair HP: ' .. tostring(settings.autorepair)); return end
    if cmd == 'set' then
        local aliases = { dark = 0, light = 1, earth = 2, wind = 3, fire = 4, ice = 5, thunder = 6, water = 7, disabled = -1, none = -1, off = -1 }
        for i = 1, 3 do
            local value = aliases[command_key(args[i])]
            if value ~= nil then settings.maneuvers[i] = value end
        end
        echo('Maneuvers updated.')
    end
end

function PUP.render_ui(imgui, ui_settings, ctx)
    settings = ui_settings or settings or {}
    ensure()
    ctx = ctx or {}
    local changed = false

    imgui.Text('Status: ' .. (active and 'Enabled' or 'Disabled'))
    imgui.Text('Pet HP: ' .. tostring(state.pet_hp_pct or 0) .. '%')
    imgui.Text('Oils: ' .. tostring(state.oils or 0))
    imgui.Text('Maneuvers: ' .. selected_label(settings.maneuvers[1]) .. ' / ' .. selected_label(settings.maneuvers[2]) .. ' / ' .. selected_label(settings.maneuvers[3]))
    imgui.Separator()

    local deploy = { settings.autodeploy == true }
    if imgui.Checkbox('Auto Deploy##PUP_deploy' .. tostring(ctx.id or ''), deploy) then settings.autodeploy = deploy[1]; changed = true end
    local activate = { settings.activate == true }
    if imgui.Checkbox('Auto Activate##PUP_activate' .. tostring(ctx.id or ''), activate) then settings.activate = activate[1]; changed = true end
    local cooldown = { settings.autocooldown == true }
    if imgui.Checkbox('Auto Cooldown Overload##PUP_cooldown' .. tostring(ctx.id or ''), cooldown) then settings.autocooldown = cooldown[1]; changed = true end
    local maintenance = { settings.automaintenance == true }
    if imgui.Checkbox('Auto Maintenance##PUP_maintenance' .. tostring(ctx.id or ''), maintenance) then settings.automaintenance = maintenance[1]; changed = true end

    imgui.Text('Repair Below HP%:')
    local repair = { tonumber(settings.autorepair) or 40 }
    if imgui.SliderFloat('##PUP_repair' .. tostring(ctx.id or ''), repair, 0, 100) then settings.autorepair = math.floor(repair[1] + 0.5); changed = true end

    for slot = 1, 3 do
        imgui.Text('Maneuver Slot ' .. tostring(slot) .. ':')
        if imgui.BeginCombo('##PUP_maneuver_' .. tostring(slot) .. tostring(ctx.id or ''), selected_label(settings.maneuvers[slot])) then
            for _, option in ipairs(maneuver_options) do
                if imgui.Selectable(option.label, option.value == settings.maneuvers[slot]) then
                    settings.maneuvers[slot] = option.value
                    changed = true
                end
            end
            imgui.EndCombo()
        end
    end

    local autolight = { settings.autolight_enabled == true }
    if imgui.Checkbox('Auto Light Maneuver At Pet HP##PUP_autolight' .. tostring(ctx.id or ''), autolight) then settings.autolight_enabled = autolight[1]; changed = true end
    imgui.Text('Auto Light HP%:')
    local light_hp = { tonumber(settings.autolight_hp) or 0 }
    if imgui.SliderFloat('##PUP_light_hp' .. tostring(ctx.id or ''), light_hp, 0, 100) then settings.autolight_hp = math.floor(light_hp[1] + 0.5); changed = true end

    return changed
end

return PUP
