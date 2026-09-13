local BRD = {}

local settings = nil
local enabled = false
local next_song_at = 0
local song_index = 1

local function echo(message)
    windower.add_to_chat(207, '[AutoBot:BRD] ' .. tostring(message))
end

local function ensure()
    settings = settings or {}
    settings.default = settings.default or {}
    settings.songDelay = tonumber(settings.songDelay) or 15
end

local function can_act()
    local player = windower.ffxi.get_player()
    if not player then
        return false
    end

    local vitals = player.vitals or {}
    if tonumber(vitals.hpp or 0) <= 0 or tonumber(vitals.hp or 0) <= 0 then
        return false
    end

    return tostring(player.main_job or ''):upper() == 'BRD'
        or tostring(player.sub_job or ''):upper() == 'BRD'
end

function BRD.init(job_settings)
    settings = job_settings or {}
    ensure()
    echo('Module initialized.')
end

function BRD.start()
    ensure()
    enabled = true
    next_song_at = 0
    song_index = 1
    echo('Module started.')
end

function BRD.stop()
    enabled = false
    echo('Module stopped.')
end

function BRD.tick()
    if not enabled then
        return
    end
    ensure()
    if not can_act() then
        return
    end
    if os.clock() < next_song_at then
        return
    end

    local songs = settings.default or {}
    local attempts = 0
    while attempts < 5 do
        local song = songs[song_index]
        song_index = song_index + 1
        if song_index > 5 then
            song_index = 1
        end
        attempts = attempts + 1

        if song and tostring(song) ~= '' then
            windower.send_command('input /song "' .. tostring(song) .. '" <me>')
            next_song_at = os.clock() + settings.songDelay
            return
        end
    end

    next_song_at = os.clock() + 5
end

function BRD.command(cmd, args)
    ensure()
    cmd = tostring(cmd or ''):lower()
    args = args or {}
    if cmd == 'start' or cmd == 'on' then return BRD.start() end
    if cmd == 'stop' or cmd == 'off' then return BRD.stop() end
    if cmd == 'delay' and args[1] then
        settings.songDelay = tonumber(args[1]) or settings.songDelay
        echo('Song delay: ' .. tostring(settings.songDelay))
        return
    end
    if cmd == 'set' then
        for i = 1, 5 do
            settings.default[i] = args[i] or settings.default[i] or ''
        end
        echo('Default songs updated.')
    end
end

function BRD.render_ui(imgui, ui_settings, ctx)
    settings = ui_settings or settings or {}
    ensure()
    ctx = ctx or {}
    local changed = false
    local delay = { settings.songDelay }
    imgui.Text('Song Delay:')
    if imgui.SliderFloat('##BRD_song_delay' .. tostring(ctx.id or ''), delay, 5, 30) then
        settings.songDelay = math.floor(delay[1] + 0.5)
        changed = true
    end
    for i = 1, 5 do
        local buffer = { tostring(settings.default[i] or '') }
        imgui.Text('Song ' .. tostring(i) .. ':')
        if imgui.InputText('##BRD_song_' .. tostring(i) .. tostring(ctx.id or ''), buffer, 128) then
            settings.default[i] = buffer[1]
            changed = true
        end
    end
    return changed
end

return BRD
