local navigation = {}
local pull_state = require('modules.state')

local recording = false
local current_path = {}
local current_name = nil
local current_record_meta = {}

local playback = false
local paused = false
local playback_index = 1
local direction = 1

local loop_mode = false
local reverse_mode = false
local bounce_mode = false

local last_record = 0
local record_interval = 1.0
local jitter = 1.0
local waypoint_radius = 3.0
local lookahead_distance = 6.0
local closest_scan_points = 12
local last_move_error = 0
local movement_active = false
local last_plugin_target = nil
local last_vector_command = 0
local vector_command_interval = 0.10
local relative_move = false
local relative_move_complete = nil

local path_dir = ('%s\\addons\\autobot\\navpaths\\'):format(AshitaCore:GetInstallPath())
local path_index_file = path_dir .. '_index.lua'
ashita.fs.create_dir(path_dir)

local function queue_command(command)
    AshitaCore:GetChatManager():QueueCommand(1, command)
end

local function echo_throttled(message)
    if pull_state.debug ~= true then
        return
    end

    if (os.clock() - last_move_error) < 3 then
        return
    end

    last_move_error = os.clock()
    AshitaCore:GetChatManager():QueueCommand(1, '/echo [AutoBot] Navigation: ' .. tostring(message))
end

local function stop_moving()
    if not movement_active and not last_plugin_target then
        return
    end

    queue_command('/movement navstop')
    movement_active = false
    last_plugin_target = nil
    last_vector_command = 0
end

local function spell_pull_in_progress()
    return pull_state
        and pull_state.pull_in_progress == true
        and pull_state.pull_completed ~= true
end

-------------------------------------------------
-- ✅ FIXED PLAYER ENTITY ACCESS (FINAL)
-------------------------------------------------
local function get_player_index()
    local mem    = AshitaCore:GetMemoryManager()
    local party  = mem:GetParty()

    if not party then return nil end

    local ok, index = pcall(function()
        return party:GetMemberTargetIndex(0)
    end)

    if ok and index and index > 0 then
        return index
    end

    return nil
end

-------------------------------------------------
-- POSITION
-------------------------------------------------
local function player_pos()
    local mem = AshitaCore:GetMemoryManager()
    local entity = mem and mem:GetEntity()
    if not entity then return nil end

    local index = get_player_index()

    if index then
        local ok_x, x = pcall(function()
            return entity:GetLocalPositionX(index)
        end)

        local ok_z, z = pcall(function()
            return entity:GetLocalPositionZ(index)
        end)

        local ok_y, y = pcall(function()
            return entity:GetLocalPositionY(index)
        end)

        if ok_x and ok_y and x and y then
            return { x = x, y = y, z = ok_z and z or 0 }
        end

        if ok_x and ok_z and x and z then
            return { x = x, y = z, z = 0 }
        end

        local entity_obj = nil
        local ok_get, got = pcall(function()
            return entity:GetEntity(index)
        end)

        if ok_get and got then
            entity_obj = got
        else
            local ok_index, indexed = pcall(function()
                return entity[index]
            end)

            if ok_index and indexed then
                entity_obj = indexed
            end
        end

        if entity_obj and entity_obj.Pos and entity_obj.Pos.X then
            if entity_obj.Pos.Y then
                return { x = entity_obj.Pos.X, y = entity_obj.Pos.Y, z = entity_obj.Pos.Z or 0 }
            elseif entity_obj.Pos.Z then
                return { x = entity_obj.Pos.X, y = entity_obj.Pos.Z, z = 0 }
            end
        end

        if entity_obj and entity_obj.Movement and entity_obj.Movement.LocalPosition then
            local pos = entity_obj.Movement.LocalPosition

            if pos.X and pos.Y then
                return { x = pos.X, y = pos.Y, z = pos.Z or 0 }
            elseif pos.X and pos.Z then
                return { x = pos.X, y = pos.Z, z = 0 }
            end
        end
    end

    local ok_local, local_player = pcall(function()
        return entity:GetLocalPlayer()
    end)

    if ok_local and local_player and local_player.Pos and local_player.Pos.X then
        if local_player.Pos.Y then
            return { x = local_player.Pos.X, y = local_player.Pos.Y, z = local_player.Pos.Z or 0 }
        elseif local_player.Pos.Z then
            return { x = local_player.Pos.X, y = local_player.Pos.Z, z = 0 }
        end
    end

    return nil
end

local function get_player_entity(index)
    local entity = AshitaCore:GetMemoryManager():GetEntity()
    if not entity or not index then return nil end

    local ok_get, got = pcall(function()
        return entity:GetEntity(index)
    end)

    if ok_get and got then
        return got
    end

    local ok_index, indexed = pcall(function()
        return entity[index]
    end)

    if ok_index and indexed then
        return indexed
    end

    return nil
end

local function dist(a, b)
    local dx = a.x - b.x
    local has_plane_y = a.y ~= nil and b.y ~= nil
    local dy = (a.y or a.z or 0) - (b.y or b.z or 0)
    local dz = has_plane_y and ((a.z or 0) - (b.z or 0)) or 0
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function steer_to_target(pos, target)
    local tx = tonumber(target.x) or 0
    local ty = tonumber(target.y or target.z) or 0
    local dx = tx - pos.x
    local dy = ty - (pos.y or pos.z or 0)
    local length = math.sqrt((dx * dx) + (dy * dy))

    if length <= 0.001 then
        return
    end

    local vx = dx / length
    local vy = dy / length
    local target_key = string.format('%.2f:%.2f', vx, vy)
    local now = os.clock()

    if target_key ~= last_plugin_target or (now - last_vector_command) >= vector_command_interval then
        queue_command(string.format('/movement navvec %.3f %.3f', vx, vy))
        movement_active = true
        last_plugin_target = target_key
        last_vector_command = now
    end
end

local function advance_playback_index()
    playback_index = playback_index + direction

    if bounce_mode then
        if playback_index > #current_path then
            direction = -1
            playback_index = #current_path - 1
        elseif playback_index < 1 then
            direction = 1
            playback_index = 2
        end
    elseif reverse_mode then
        if playback_index < 1 then
            navigation.stop_playback()
        end
    elseif loop_mode then
        if playback_index > #current_path then
            playback_index = 1
        end
    elseif playback_index > #current_path then
        navigation.stop_playback()
    end
end

local function is_index_ahead(candidate, current)
    if not candidate or not current then
        return false
    end

    if direction > 0 then
        return candidate > current
    end

    return candidate < current
end

local function next_index(index)
    return index + direction
end

local function find_closest_forward_index(pos)
    local best_index = playback_index
    local best_distance = math.huge
    local index = playback_index
    local scanned = 0

    while index >= 1 and index <= #current_path and scanned < closest_scan_points do
        local point = current_path[index]
        if point then
            local distance = dist(pos, point)
            if distance < best_distance then
                best_distance = distance
                best_index = index
            end
        end

        index = next_index(index)
        scanned = scanned + 1
    end

    if is_index_ahead(best_index, playback_index) then
        return best_index
    end

    return playback_index
end

local function choose_lookahead_index(pos)
    local index = playback_index

    while true do
        local candidate = next_index(index)
        if candidate < 1 or candidate > #current_path then
            return index
        end

        local next_point = current_path[candidate]
        if not next_point or dist(pos, next_point) >= lookahead_distance then
            return index
        end

        index = candidate
    end
end

local function should_advance_waypoint(pos, index)
    local target = current_path[index]
    if not target then
        return false
    end

    local arrival_radius = relative_move and 1.5 or waypoint_radius
    if dist(pos, target) <= arrival_radius then
        return true
    end

    local previous = current_path[index - direction]
    if not previous then
        return false
    end

    local seg_x = target.x - previous.x
    local seg_y = (target.y or target.z or 0) - (previous.y or previous.z or 0)
    local seg_len_sq = (seg_x * seg_x) + (seg_y * seg_y)

    if seg_len_sq <= 0.001 then
        return false
    end

    local pos_x = pos.x - previous.x
    local pos_y = (pos.y or pos.z or 0) - (previous.y or previous.z or 0)
    local projection = ((pos_x * seg_x) + (pos_y * seg_y)) / seg_len_sq

    return projection >= 0.75
end

local function normalize_path_name(name)
    name = tostring(name or ''):match("^%s*(.-)%s*$") or ''
    name = name:gsub('[\\/:*?"<>|]', '_')
    name = name:gsub('^%.+', '')
    name = name:gsub('%.+$', '')
    return name
end

local function is_array(tbl)
    if type(tbl) ~= 'table' then
        return false
    end

    local max = 0
    local count = 0
    for k, _ in pairs(tbl) do
        if type(k) ~= 'number' or k < 1 or k % 1 ~= 0 then
            return false
        end
        if k > max then max = k end
        count = count + 1
    end

    return max == count
end

local function current_zone()
    local zone_id = 0

    pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty()
        if party then
            zone_id = party:GetMemberZone(0) or party:GetMemberZone2(0) or 0
        end
    end)

    local zone_name = ''
    if zone_id and zone_id > 0 then
        zone_name = tostring(zone_id)
        pcall(function()
            local res = AshitaCore:GetResourceManager()
            local name = res and res:GetString('zones.names', zone_id)
            if name and name ~= '' then
                zone_name = name
            end
        end)
    end

    return zone_id or 0, zone_name
end

local function serialize(value, indent)
    indent = indent or 0
    local pad = string.rep(' ', indent)
    local child_pad = string.rep(' ', indent + 4)

    if type(value) == 'table' then
        local out = "{\n"
        local max = 0
        local count = 0
        local is_array = true

        for k, _ in pairs(value) do
            if type(k) ~= 'number' or k < 1 or k % 1 ~= 0 then
                is_array = false
                break
            end

            if k > max then max = k end
            count = count + 1
        end

        is_array = is_array and max == count

        if is_array then
            for _, v in ipairs(value) do
                out = out .. child_pad .. serialize(v, indent + 4) .. ',\n'
            end
        else
            local keys = {}
            for k, _ in pairs(value) do
                table.insert(keys, k)
            end
            table.sort(keys, function(a, b)
                return tostring(a) < tostring(b)
            end)

            for _, k in ipairs(keys) do
                local key
                if type(k) == 'number' then
                    key = '[' .. tostring(k) .. ']'
                elseif type(k) == 'string' and k:match('^[%a_][%w_]*$') then
                    key = k
                else
                    key = '[' .. serialize(k, 0) .. ']'
                end

                out = out .. child_pad .. key .. ' = ' .. serialize(value[k], indent + 4) .. ',\n'
            end
        end

        return out .. pad .. '}'
    end

    if type(value) == 'string' then
        return string.format('%q', value)
    end

    if type(value) == 'number' or type(value) == 'boolean' then
        return tostring(value)
    end

    return 'nil'
end

-------------------------------------------------
-- SAVE / LOAD
-------------------------------------------------
local function save(name, path, meta)
    name = normalize_path_name(name)
    if not name or name == '' then return end

    local f = io.open(path_dir .. name .. '.lua', 'w+')
    if not f then return end

    meta = meta or {}
    local data = {
        version = 2,
        name = name,
        zone_id = tonumber(meta.zone_id) or 0,
        zone_name = tostring(meta.zone_name or ''),
        details = tostring(meta.details or ''),
        points = path or {},
    }

    f:write('return ' .. serialize(data))
    f:close()
end

local function load_index()
    local f = io.open(path_index_file, 'r')
    if not f then return {} end

    local data = f:read('*a')
    f:close()

    local ok, res = pcall(loadstring(data))
    if not ok or type(res) ~= 'table' then return {} end

    table.sort(res)
    return res
end

local function save_index(paths)
    local f = io.open(path_index_file, 'w+')
    if not f then return end

    table.sort(paths)
    f:write('return ' .. serialize(paths))
    f:close()
end

local function add_to_index(name)
    name = normalize_path_name(name)
    if not name or name == '' then return end

    local paths = load_index()
    for _, path_name in ipairs(paths) do
        if path_name == name then
            return
        end
    end

    table.insert(paths, name)
    save_index(paths)
end

local function load(name)
    name = normalize_path_name(name)
    if not name or name == '' then return nil end

    local f = io.open(path_dir .. name .. '.lua', 'r')
    if not f then return nil end

    local data = f:read('*a')
    f:close()

    local ok, res = pcall(loadstring(data))
    if not ok then return nil end

    return res
end

local function load_path_data(name)
    local loaded = load(name)
    if type(loaded) ~= 'table' then
        return nil
    end

    if type(loaded.points) == 'table' then
        return {
            name = normalize_path_name(loaded.name or name),
            zone_id = tonumber(loaded.zone_id) or 0,
            zone_name = tostring(loaded.zone_name or ''),
            details = tostring(loaded.details or ''),
            points = loaded.points,
        }
    end

    if is_array(loaded) then
        return {
            name = normalize_path_name(name),
            zone_id = 0,
            zone_name = '',
            details = '',
            points = loaded,
        }
    end

    return nil
end

-------------------------------------------------
-- RECORDING
-------------------------------------------------
function navigation.start_record(name, zone_name, details)
    name = normalize_path_name(name)
    if not name or name == '' then return end

    playback = false
    paused = false
    pull_state.navigation_playback = false
    pull_state.navigation_paused = false
    stop_moving()

    local zone_id, detected_zone = current_zone()
    recording = true
    current_path = {}
    current_name = name
    current_record_meta = {
        zone_id = zone_id,
        zone_name = zone_name ~= nil and tostring(zone_name) or detected_zone,
        details = details ~= nil and tostring(details) or '',
    }
    last_record = os.clock()
end

function navigation.stop_record()
    if not recording then return end

    recording = false
    save(current_name, current_path, current_record_meta)
    add_to_index(current_name)
end

function navigation.is_recording()
    return recording
end

function navigation.get_recorded_point_count()
    return #current_path
end

-------------------------------------------------
-- PLAYBACK
-------------------------------------------------
function navigation.start_playback(name)
    name = normalize_path_name(name)
    if not name or name == '' then return end

    if relative_move then
        navigation.stop_playback()
    end

    recording = false
    relative_move = false

    local data = load_path_data(name)
    if not data or type(data.points) ~= 'table' or #data.points == 0 then return end

    current_path = data.points
    current_name = name
    playback = true
    paused = false
    pull_state.navigation_playback = true
    pull_state.navigation_paused = false
    movement_active = false
    last_plugin_target = nil

    if reverse_mode then
        direction = -1
        playback_index = #current_path
    else
        direction = 1
        playback_index = 1
    end
end

function navigation.stop_playback()
    local completed = relative_move_complete

    playback = false
    paused = false
    pull_state.navigation_playback = false
    pull_state.navigation_paused = false
    relative_move = false
    relative_move_complete = nil
    stop_moving()

    if completed then
        pcall(completed)
    end
end

function navigation.move_relative(distance, direction_name, on_complete)
    distance = tonumber(distance)
    direction_name = tostring(direction_name or ''):lower()

    local directions = {
        north = { 0, 1 }, n = { 0, 1 },
        northeast = { 1, 1 }, ne = { 1, 1 },
        east = { 1, 0 }, e = { 1, 0 },
        southeast = { 1, -1 }, se = { 1, -1 },
        south = { 0, -1 }, s = { 0, -1 },
        southwest = { -1, -1 }, sw = { -1, -1 },
        west = { -1, 0 }, w = { -1, 0 },
        northwest = { -1, 1 }, nw = { -1, 1 },
    }

    local vector = directions[direction_name]
    local pos = player_pos()
    if not distance or distance <= 0 or not vector or not pos then
        return false
    end

    if playback then
        navigation.stop_playback()
    end

    distance = math.min(distance, 100)
    local length = math.sqrt((vector[1] * vector[1]) + (vector[2] * vector[2]))

    recording = false
    current_name = nil
    current_path = {
        {
            x = pos.x + ((vector[1] / length) * distance),
            y = pos.y + ((vector[2] / length) * distance),
            z = pos.z,
        },
    }
    playback = true
    paused = false
    playback_index = 1
    direction = 1
    relative_move = true
    relative_move_complete = type(on_complete) == 'function' and on_complete or nil
    pull_state.navigation_playback = true
    pull_state.navigation_paused = false
    movement_active = false
    last_plugin_target = nil
    return true
end

function navigation.pause_playback()
    if not playback then return end

    paused = true
    pull_state.navigation_paused = true
    stop_moving()
end

function navigation.resume_playback()
    if not playback then return end

    paused = false
    pull_state.navigation_playback = true
    pull_state.navigation_paused = false
end

function navigation.is_playing()
    return playback
end

function navigation.is_paused()
    return paused
end

function navigation.list_paths()
    return load_index()
end

function navigation.get_current_zone()
    local zone_id, zone_name = current_zone()
    return {
        zone_id = zone_id,
        zone_name = zone_name,
    }
end

function navigation.get_path_details(name)
    name = normalize_path_name(name)
    if not name or name == '' then return nil end

    local data = load_path_data(name)
    if not data then return nil end

    return {
        name = name,
        zone_id = data.zone_id or 0,
        zone_name = data.zone_name or '',
        details = data.details or '',
        point_count = #(data.points or {}),
    }
end

function navigation.update_path_details(name, zone_name, details)
    name = normalize_path_name(name)
    if not name or name == '' then return false end

    local data = load_path_data(name)
    if not data then return false end

    data.zone_name = tostring(zone_name or '')
    data.details = tostring(details or '')
    save(name, data.points, data)
    add_to_index(name)
    return true
end

function navigation.delete_path(name)
    name = normalize_path_name(name)
    if not name or name == '' then return false end

    if current_name == name then
        if recording then recording = false end
        if playback then navigation.stop_playback() end
    end

    os.remove(path_dir .. name .. '.lua')

    local paths = load_index()
    local filtered = {}
    for _, path_name in ipairs(paths) do
        if path_name ~= name then
            table.insert(filtered, path_name)
        end
    end
    save_index(filtered)
    return true
end

function navigation.get_status()
    return {
        recording = recording,
        playback = playback,
        paused = paused,
        path_name = current_name,
        point_count = #current_path,
        record_interval = record_interval,
        playback_index = playback_index,
        movement_driver = 'Movement AutoFollow',
        loop = loop_mode,
        reverse = reverse_mode,
        bounce = bounce_mode,
    }
end

-------------------------------------------------
-- TOGGLES
-------------------------------------------------
function navigation.toggle_loop() loop_mode = not loop_mode end
function navigation.toggle_reverse() reverse_mode = not reverse_mode end
function navigation.toggle_bounce() bounce_mode = not bounce_mode end
function navigation.set_loop(value) loop_mode = value == true end
function navigation.set_reverse(value) reverse_mode = value == true end
function navigation.set_bounce(value) bounce_mode = value == true end

-------------------------------------------------
-- MAIN LOOP
-------------------------------------------------
function navigation.tick()
    local pos = player_pos()
    if not pos then
        if recording then
            echo_throttled('Could not read player position.')
        end
        return
    end

    if playback and paused then
        stop_moving()
        return
    end

    if playback and spell_pull_in_progress() then
        stop_moving()
        return
    end

    -- RECORD
    if recording then
        if (os.clock() - last_record) >= record_interval then
            last_record = os.clock()

            local last = current_path[#current_path]
            if not last or dist(last, pos) >= jitter then
                table.insert(current_path, pos)
            end
        end
    end

    -- PLAYBACK
    if playback and #current_path > 0 then
        playback_index = find_closest_forward_index(pos)

        while playback do
            local target = current_path[playback_index]
            if not target then return end
            if not should_advance_waypoint(pos, playback_index) then
                break
            end

            advance_playback_index()
        end

        if playback then
            local target = current_path[choose_lookahead_index(pos)]
            if target then
                steer_to_target(pos, target)
            end
        end
    end
end

return navigation
