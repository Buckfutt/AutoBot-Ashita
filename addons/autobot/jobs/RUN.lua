local common = require('job_helpers.common')
local action_state = require('job_helpers.action_state')

local RUN = common.create_ability_job({
    job = 'RUN',
    cooldown = 5,
    abilities = {
        { key='Swordplay', name='Swordplay', timer=68, buff=531, level=20 },
        { key='Vallation', name='Vallation', timer=23, buff=535, level=10 },
        { key='Pflug', name='Pflug', timer=24, buff=537, level=50 },
        { key='Swipe', name='Swipe', timer=141, level=25, target='<t>' },
        { key='Lunge', name='Lunge', timer=142, level=25, target='<t>' },
        { key='Valiance', name='Valiance', timer=113, buff=535, level=50 },
        { key='Liement', name='Liement', timer=116, buff=537, level=85 },
        { key='One_For_All', name='One for All', timer=118, level=95 },
        { key='Gambit', name='Gambit', timer=119, level=75, target='<t>' },
        { key='Rayke', name='Rayke', timer=120, level=75, target='<t>' },
        { key='Odyllic_Subterfuge', name='Odyllic Subterfuge', timer=0, level=96, target='<t>' },
    },
})

local settings = nil
local run_enabled = false
local last_rune_at = 0
local active_runes = {}
local active_rune_list = {}

local rune_map = {
    [523] = 'ignis', [524] = 'gelus', [525] = 'flabra', [526] = 'tellus',
    [527] = 'sulpor', [528] = 'unda', [529] = 'lux', [530] = 'tenebrae',
}

local rune_options = {
    { value = '', label = 'Disabled' },
    { value = 'tellus', label = 'Tellus = Earth' },
	{ value = 'unda', label = 'Unda = Water' },
	{ value = 'flabra', label = 'Flabra = Wind' },
	{ value = 'ignis', label = 'Ignis = Fire' },
    { value = 'gelus', label = 'Gelus = Ice' },
    { value = 'sulpor', label = 'Sulpor = Lightning' },
    { value = 'lux', label = 'Lux = Light' },
	{ value = 'tenebrae', label = 'Tenebrae = Dark' },
}

local rune_aliases = {
    disabled = '', 
	disable = '', 
	off = '', 
	none = '', 
	empty = '',
    earth = 'tellus', tellus = 'tellus',
	water = 'unda', unda = 'unda',
	wind = 'flabra', air = 'flabra', flabra = 'flabra',
	fire = 'ignis', ignis = 'ignis',
    ice = 'gelus', gelus = 'gelus',
    thunder = 'sulpor', lightning = 'sulpor', sulpor = 'sulpor',
    light = 'lux', lux = 'lux',
	dark = 'tenebrae', darkness = 'tenebrae', tenebrae = 'tenebrae',
}

local function echo(message)
    windower.add_to_chat(207, '[AutoBot:RUN] ' .. tostring(message))
end

local function normalize_rune(value)
    if value == nil then
        return nil
    end

    local key = tostring(value):lower():gsub('%s+', '')
    return rune_aliases[key]
end

local function rune_label(value)
    value = normalize_rune(value) or ''
    for _, option in ipairs(rune_options) do
        if option.value == value then
            return option.label
        end
    end

    return rune_options[1].label
end

local function normalize_slots()
    if not settings or not settings.desiredSlots then
        return
    end

    for i = 1, 3 do
        local key = 'slot' .. tostring(i)
        local normalized = normalize_rune(settings.desiredSlots[key])
        if normalized ~= nil then
            settings.desiredSlots[key] = normalized
        end
    end
end

local base_init = RUN.init
function RUN.init(job_settings)
    settings = job_settings or {}
    settings.desiredSlots = settings.desiredSlots or {}
    normalize_slots()
    base_init(settings)
end

local function update_runes()
    active_runes = {}
    active_rune_list = {}
    local player = windower.ffxi.get_player()
    if not player or not player.buffs then return end
    for _, buff in ipairs(player.buffs) do
        local rune = rune_map[tonumber(buff)]
        if rune then
            table.insert(active_rune_list, rune)
            active_runes[rune] = (active_runes[rune] or 0) + 1
        end
    end
end

local function maintain_runes()
    if not run_enabled then
        return
    end
    if action_state.is_busy() then
        return
    end
    if not settings or not settings.desiredSlots then
        return
    end
    normalize_slots()
    if (os.clock() - last_rune_at) < 5 then
        return
    end
    local recasts = windower.ffxi.get_ability_recasts()
    if tonumber(recasts[10] or 0) ~= 0 then
        return
    end
    for i = 1, 3 do
        local desired = settings.desiredSlots['slot' .. tostring(i)]
        if desired and desired ~= '' and active_rune_list[i] ~= desired then
            windower.send_command(('input /ja "%s" <me>'):format(desired))
            last_rune_at = os.clock()
            return
        end
    end
end

local base_tick = RUN.tick
local base_start = RUN.start
local base_stop = RUN.stop
function RUN.start()
    run_enabled = true
    return base_start()
end

function RUN.stop()
    run_enabled = false
    return base_stop()
end

function RUN.tick()
    update_runes()
    maintain_runes()
    base_tick()
end

function RUN.setRunes(a, b, c)
    settings = settings or {}
    settings.desiredSlots = settings.desiredSlots or {}
    local slot1 = normalize_rune(a)
    local slot2 = normalize_rune(b)
    local slot3 = normalize_rune(c)
    if slot1 ~= nil then
        settings.desiredSlots.slot1 = slot1
    end
    if slot2 ~= nil then
        settings.desiredSlots.slot2 = slot2
    end
    if slot3 ~= nil then
        settings.desiredSlots.slot3 = slot3
    end
    echo('Rune slots updated.')
end

local base_command = RUN.command
function RUN.command(cmd, args)
    cmd = tostring(cmd or ''):lower()
    args = args or {}
    if cmd == 'set' or cmd == 'runes' then
        return RUN.setRunes(args[1], args[2], args[3])
    end
    return base_command(cmd, args)
end

local base_render_ui = RUN.render_ui
function RUN.render_ui(imgui, ui_settings, ctx)
    settings = ui_settings or settings or {}
    settings.desiredSlots = settings.desiredSlots or {}
    normalize_slots()
    ctx = ctx or {}
    local changed = base_render_ui(imgui, settings, ctx)
    imgui.Separator()
    imgui.Text('Elemental Runes')

    for i = 1, 3 do
        local key = 'slot' .. tostring(i)
        local current = normalize_rune(settings.desiredSlots[key]) or ''
        imgui.Text('Rune Slot ' .. tostring(i) .. ':')
        if imgui.BeginCombo('##RUN_rune_' .. tostring(i) .. tostring(ctx.id or ''), rune_label(current)) then
            for _, option in ipairs(rune_options) do
                if imgui.Selectable(option.label, option.value == current) then
                    settings.desiredSlots[key] = option.value
                    changed = true
                end
            end
            imgui.EndCombo()
            if settings.desiredSlots[key] ~= current then
                changed = true
            end
        end
    end
    return changed
end

return RUN