local follow = {}
local shared_state = require('modules.state')

local following = false
local follow_target = nil
local suspended_for_combat = false
local mounted_last_tick = false

local follow_range = 3
local distance_threshold = follow_range + 2

local last_reissue_time = 0
local reissue_delay = 2

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function cmd(str)
    AshitaCore:GetChatManager():QueueCommand(1, str)
end

local function get_entity()
    return AshitaCore:GetMemoryManager():GetEntity()
end

local function now()
    return os.clock()
end

local function clear_follow_driver()
    cmd('/movement stop')

    pcall(function()
        local auto_follow = AshitaCore:GetMemoryManager():GetAutoFollow()
        if not auto_follow then return end

        auto_follow:SetIsAutoRunning(0)
        auto_follow:SetFollowDeltaX(0.0)
        auto_follow:SetFollowDeltaZ(0.0)
        auto_follow:SetFollowDeltaY(0.0)
        auto_follow:SetFollowDeltaW(1.0)
        auto_follow:SetFollowTargetIndex(0)
        auto_follow:SetFollowTargetServerId(0)
        auto_follow:SetTargetIndex(0)
        auto_follow:SetTargetServerId(0)
        auto_follow:SetIsCameraLocked(0)
        auto_follow:SetIsCameraLockedOn(0)
    end)
end

local function find_entity_index_by_name(name)
    local entity = get_entity()
    local wanted = tostring(name or ''):lower()
    if not entity or wanted == '' then return -1 end

    for index = 0, 2048 do
        local entity_name = entity:GetName(index)
        if entity_name and entity_name:lower() == wanted then
            return index
        end
    end

    return -1
end

-------------------------------------------------
-- START FOLLOW
-------------------------------------------------
function follow.start_follow(name)
    following = true
    follow_target = name
    suspended_for_combat = false
    last_reissue_time = now()

    cmd('/p Following: ' .. name)
    cmd('/follow ' .. name)
end

-------------------------------------------------
-- STOP FOLLOW
-------------------------------------------------
function follow.stop_follow()
    following = false
    follow_target = nil
    suspended_for_combat = false
    clear_follow_driver()

    cmd('/p Stopping Follow!')
end

-------------------------------------------------
-- ZONE EVENT
-------------------------------------------------
ashita.events.register('zone_change', 'follow_zone', function()
    if following and follow_target then
        ashita.tasks.once(0.5, function()
            cmd('/follow ' .. follow_target)
        end)
    end
end)

-------------------------------------------------
-- DISTANCE CHECK LOOP
-------------------------------------------------
ashita.events.register('d3d_present', 'follow_tick', function()
    if shared_state.trust_maintenance == true
    or not following
    or not follow_target
    then
        return
    end

    local mounted_now = shared_state.mounted == true
    if mounted_now and not mounted_last_tick then
        local expected_target = follow_target

        ashita.tasks.once(0.5, function()
            if following
            and follow_target == expected_target
            and shared_state.mounted == true
            then
                last_reissue_time = now()
                cmd('/follow ' .. follow_target)
            end
        end)
    end
    mounted_last_tick = mounted_now

    if shared_state.auto_assist_active == true then
        if not suspended_for_combat then
            suspended_for_combat = true
            clear_follow_driver()
        end
        return
    end

    if suspended_for_combat then
        suspended_for_combat = false
        last_reissue_time = now()
        cmd('/follow ' .. follow_target)
        return
    end

    local entity = get_entity()
    if not entity then return end

    local target_index = find_entity_index_by_name(follow_target)
    if target_index <= 0 then return end

    local distance = math.sqrt(math.max(0, tonumber(entity:GetDistance(target_index)) or 0))

    if distance > distance_threshold then
        local t = now()

        if (t - last_reissue_time) > reissue_delay then
            cmd('/follow ' .. follow_target)
            last_reissue_time = t
        end
    end
end)

-------------------------------------------------
-- DISTANCE CONFIG
-------------------------------------------------
function follow.set_follow_distance(val)
    val = tonumber(val)
    if val then
        follow_range = val
        distance_threshold = follow_range + 5
    end
end

function follow.get_status()
    return {
        following = following,
        target = follow_target,
    }
end

function follow.pause_follow()
    if following then
        clear_follow_driver()
    end
end

function follow.resume_follow()
    if following and follow_target then
        last_reissue_time = now()
        cmd('/follow ' .. follow_target)
    end
end

return follow
