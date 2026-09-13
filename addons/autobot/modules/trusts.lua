local trusts = {}
local shared_state = require('modules.state')

local trust_data = require('modules.trust_data')

local pulling = nil
local targeting = nil
local maintenance_controller = nil

local config = nil
local save = nil

local DEFAULT_WAIT_AFTERCAST = 3
local DEFAULT_WAIT_RETR = 1.25
local DEFAULT_WAIT_RETRALL = 3
local CAST_START_WINDOW = 1.5
local CAST_WAIT_TIMEOUT = 12
local CAST_POLL_INTERVAL = 0.2
local MAX_TRUSTS = 5
local MONITOR_INTERVAL = 1.0
local MONITOR_RETRY = 15.0

math.randomseed(os.clock())
local queue_active = false
local stopped = false
local monitor_pending = {}
local last_monitor_tick = 0
local loaded_sets_character = nil
local maintenance_requested = false
local maintenance_active = false

local function current_character()
    local ok, name = pcall(function()
        local player = AshitaCore:GetMemoryManager():GetPlayer()
        if player and type(player.GetName) == 'function' then
            return player:GetName()
        end

        local party = AshitaCore:GetMemoryManager():GetParty()
        return party and party:GetMemberName(0) or nil
    end)

    if not ok or not name or name == '' then
        return nil
    end

    return tostring(name):gsub('[^%w_%-]', '')
end

local function trust_sets_path(character)
    return string.format(
        '%sconfig/addons/AutoBot/trust_sets_%s.lua',
        AshitaCore:GetInstallPath(),
        character
    )
end

local function load_character_sets()
    local character = current_character()
    if not character or loaded_sets_character == character then
        return
    end

    loaded_sets_character = character
    local path = trust_sets_path(character)
    local file = io.open(path, 'r')
    if not file then
        return
    end
    file:close()

    local ok, sets = pcall(dofile, path)
    if ok and type(sets) == 'table' then
        for name, members in pairs(sets) do
            if type(name) == 'string' and type(members) == 'table' then
                config.trusts.trust_sets[name] = members
            end
        end
    end
end

local function save_character_sets()
    local character = current_character()
    if not character then
        return false, 'character name is not available'
    end

    local path = trust_sets_path(character)
    local file, open_error = io.open(path, 'w+')
    if not file then
        return false, tostring(open_error)
    end

    local names = {}
    for name, _ in pairs(config.trusts.trust_sets or {}) do
        table.insert(names, name)
    end
    table.sort(names)

    file:write('return {\n')
    for _, name in ipairs(names) do
        file:write('    [', string.format('%q', tostring(name)), '] = {\n')
        for index = 1, math.min(#config.trusts.trust_sets[name], MAX_TRUSTS) do
            file:write('        ', string.format('%q', tostring(config.trusts.trust_sets[name][index])), ',\n')
        end
        file:write('    },\n')
    end
    file:write('}\n')
    file:close()

    loaded_sets_character = character
    return true
end

local function persist_sets()
    local stored, store_error = save_character_sets()
    if not stored then
        return false, store_error
    end

    if save then
        return save()
    end

    return true
end

-------------------------------------------------
-- MODULE INJECTION
-------------------------------------------------
function trusts.set_modules(pull, targ)
    pulling = pull
    targeting = targ
end

function trusts.set_maintenance_controller(controller)
    maintenance_controller = controller
end

local function ensure_config()
    if not config then
        return
    end

    config.trusts = config.trusts or {}
    config.trusts.auto = config.trusts.auto ~= false
    config.trusts.selected_set = config.trusts.selected_set or 'default'
    config.trusts.selected_trust = config.trusts.selected_trust or trust_data.names[1]
    config.trusts.trust_sets = config.trusts.trust_sets or {}
    config.trusts.trust_cooldowns = config.trusts.trust_cooldowns or {}
    config.trusts.monitor = config.trusts.monitor or {}
    config.trusts.monitor.enabled = config.trusts.monitor.enabled == true
    config.trusts.monitor.resummon_dead = config.trusts.monitor.resummon_dead == true
    config.trusts.monitor.hp_threshold = tonumber(config.trusts.monitor.hp_threshold) or 30
    config.trusts.monitor.mp_threshold = tonumber(config.trusts.monitor.mp_threshold) or 10
    config.trusts.monitor.watched = config.trusts.monitor.watched or {}
    config.trusts.wait = config.trusts.wait or {}
    config.trusts.wait.aftercast = tonumber(config.trusts.wait.aftercast) or DEFAULT_WAIT_AFTERCAST
    config.trusts.wait.retr = tonumber(config.trusts.wait.retr) or DEFAULT_WAIT_RETR
    config.trusts.wait.retrall = tonumber(config.trusts.wait.retrall) or DEFAULT_WAIT_RETRALL

    if not config.trusts.trust_sets.default then
        config.trusts.trust_sets.default = {
            'Valaineral',
            'Mihli Aliapoh',
            'Tenzen',
            'Adelheid',
            'Joachim',
        }
    end

    load_character_sets()
end

function trusts.set_config(cfg, save_func)
    config = cfg
    save = save_func
    loaded_sets_character = nil
    ensure_config()
end

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function cmd(str)
    AshitaCore:GetChatManager():QueueCommand(1, str)
end

local function echo(message)
    cmd('/echo [AutoBot] Trusts: ' .. tostring(message))
end

local function now()
    return os.time()
end

local function normalize(value)
    return tostring(value or ''):lower():gsub('[%s%p]', '')
end

local function trust_entry(name)
    if not name then
        return nil
    end

    return trust_data.by_key[normalize(name)]
end

local function trust_display_name(name)
    local entry = trust_entry(name)

    return entry and entry.english or nil
end

local function valid_set_trusts(set)
    local result = {}

    for _, name in ipairs(set or {}) do
        local display = trust_display_name(name)

        if display then
            table.insert(result, display)
        end
    end

    return result
end

local function get_party()
    local ok, party = pcall(function()
        return AshitaCore:GetMemoryManager():GetParty()
    end)

    return ok and party or nil
end

local function get_entity()
    local ok, entity = pcall(function()
        return AshitaCore:GetMemoryManager():GetEntity()
    end)

    return ok and entity or nil
end

local function spell_is_learned(id)
    local ok_player, player = pcall(function()
        return AshitaCore:GetMemoryManager():GetPlayer()
    end)

    if not ok_player or not player or not id then
        return true
    end

    local checks = {
        function() return player:HasSpell(id) end,
        function() return player:GetSpell(id) end,
        function() return player:GetSpellLearned(id) end,
    }

    for _, check in ipairs(checks) do
        local ok, value = pcall(check)

        if ok and value ~= nil then
            if type(value) == 'boolean' then
                return value
            end

            if type(value) == 'number' then
                return value ~= 0
            end

            return true
        end
    end

    return true
end

local function spell_recast_ready(id)
    local ok_recast, recast = pcall(function()
        return AshitaCore:GetMemoryManager():GetRecast()
    end)

    if not ok_recast or not recast or not id then
        return true
    end

    local checks = {
        function() return recast:GetSpellTimer(id) end,
        function() return recast:GetSpellRecast(id) end,
    }

    for _, check in ipairs(checks) do
        local ok, value = pcall(check)

        if ok and value ~= nil then
            local n = tonumber(value)

            if not n then
                return true
            end

            return n <= 0
        end
    end

    return true
end

local function get_player_index()
    local party = get_party()

    if not party then
        return -1
    end

    local ok, index = pcall(function()
        return party:GetMemberTargetIndex(0)
    end)

    if ok and index then
        return index
    end

    return -1
end

local function get_player_status()
    local entity = get_entity()
    local player_index = get_player_index()

    if entity and player_index > 0 then
        local ok, status = pcall(function()
            return entity:GetStatus(player_index)
        end)

        if ok and status then
            return status
        end
    end

    local ok_player, player = pcall(function()
        return AshitaCore:GetMemoryManager():GetPlayer()
    end)

    if ok_player and player then
        local ok_status, status = pcall(function()
            return player:GetStatus()
        end)

        if ok_status and status then
            return status
        end
    end

    return 0
end

local function castbar_is_active()
    local castbar = nil

    local ok_global, global_castbar = pcall(function()
        if type(GetCastBarSafe) == 'function' then
            return GetCastBarSafe()
        end

        return nil
    end)

    if ok_global and global_castbar then
        castbar = global_castbar
    end

    if not castbar then
        local ok_manager, manager_castbar = pcall(function()
            local mem = AshitaCore:GetMemoryManager()

            if mem and mem.GetCastBar then
                return mem:GetCastBar()
            end

            return nil
        end)

        if ok_manager and manager_castbar then
            castbar = manager_castbar
        end
    end

    if not castbar then
        return false
    end

    local ok_percent, percent = pcall(function()
        return castbar:GetPercent()
    end)

    if ok_percent and percent and percent > 0 and percent < 1 then
        return true
    end

    local ok_active, active = pcall(function()
        return castbar:GetActive()
    end)

    if ok_active and (active == true or active == 1) then
        return true
    end

    return false
end

local function player_is_casting()
    return get_player_status() == 4 or castbar_is_active()
end

local function get_party_composition()
    local party = get_party()
    local entity = get_entity()
    local humans = 1
    local trusts_count = 0

    if not party then
        return {
            humans = humans,
            trusts = trusts_count,
            trust_slots = MAX_TRUSTS,
        }
    end

    humans = 0

    for i = 0, 5 do
        local active_ok, active = pcall(function()
            return party:GetMemberIsActive(i)
        end)

        if active_ok and active == 1 then
            local name_ok, name = pcall(function()
                return party:GetMemberName(i)
            end)

            local index_ok, index = pcall(function()
                return party:GetMemberTargetIndex(i)
            end)

            local spawn_type = nil
            local is_owned_trust = false
            if entity and index_ok and index and index > 0 then
                pcall(function()
                    local e = entity:GetEntity(index)
                    spawn_type = e and (e.SpawnType or e.spawn_type)
                end)
                pcall(function()
                    if entity.GetTrustOwnerTargetIndex then
                        is_owned_trust = (entity:GetTrustOwnerTargetIndex(index) or 0) ~= 0
                    end
                end)
            end

            local is_trust = name_ok
                and name
                and name ~= ''
                and (spawn_type == 14 or is_owned_trust or trust_display_name(name) ~= nil)

            if is_trust then
                trusts_count = trusts_count + 1
            else
                humans = humans + 1
            end
        end
    end

    if humans < 1 then
        humans = 1
    end

    local trust_slots = 6 - humans
    if trust_slots < 0 then trust_slots = 0 end
    if trust_slots > MAX_TRUSTS then trust_slots = MAX_TRUSTS end

    return {
        humans = humans,
        trusts = trusts_count,
        trust_slots = trust_slots,
    }
end

local function append_trust_detail(result, by_key, detail)
    if not detail or not detail.name or detail.name == '' then
        return
    end

    local display = trust_display_name(detail.name) or detail.name
    local key = normalize(display)

    if by_key[key] then
        return
    end

    by_key[key] = true
    detail.name = display
    detail.key = key
    table.insert(result, detail)
end

local function get_party_trust_details()
    local party = get_party()
    local entity = get_entity()
    local result = {}
    local by_key = {}

    if party and entity then
        for i = 1, 17 do
            local active_ok, active = pcall(function()
                return party:GetMemberIsActive(i)
            end)

            if active_ok and active == 1 then
                local name_ok, name = pcall(function()
                    return party:GetMemberName(i)
                end)

                local index_ok, index = pcall(function()
                    return party:GetMemberTargetIndex(i)
                end)

                local spawn_type = nil
                local is_owned_trust = false
                if index_ok and index and index > 0 then
                    pcall(function()
                        local e = entity:GetEntity(index)
                        spawn_type = e and (e.SpawnType or e.spawn_type)
                    end)
                    pcall(function()
                        if entity.GetTrustOwnerTargetIndex then
                            is_owned_trust = (entity:GetTrustOwnerTargetIndex(index) or 0) ~= 0
                        end
                    end)
                end

                if name_ok and name and name ~= '' and (spawn_type == 14 or is_owned_trust or trust_display_name(name)) then
                    local hp_ok, hp = pcall(function()
                        return party:GetMemberHPPercent(i)
                    end)
                    local mp_ok, mp = pcall(function()
                        return party:GetMemberMPPercent(i)
                    end)
                    local status_ok, status = pcall(function()
                        return entity:GetStatus(index)
                    end)
                    local entity_hp_ok, entity_hp = pcall(function()
                        return entity:GetHPPercent(index)
                    end)

                    append_trust_detail(result, by_key, {
                        name = name,
                        slot = i,
                        index = index_ok and index or 0,
                        hp = hp_ok and tonumber(hp) or (entity_hp_ok and tonumber(entity_hp) or nil),
                        mp = mp_ok and tonumber(mp) or nil,
                        status = status_ok and tonumber(status) or nil,
                    })
                end
            end
        end
    end

    if #result > 0 then
        return result
    end

    if entity then
        for i = 0, 2048 do
            local ok, e = pcall(function()
                return entity:GetEntity(i)
            end)

            if ok and e then
                local spawn_type = e.SpawnType or e.spawn_type
                local name = e.Name or e.name
                local is_owned_trust = false

                pcall(function()
                    if entity.GetTrustOwnerTargetIndex then
                        is_owned_trust = (entity:GetTrustOwnerTargetIndex(i) or 0) ~= 0
                    end
                end)

                if (spawn_type == 14 or is_owned_trust) and name and name ~= '' then
                    local hp_ok, hp = pcall(function()
                        return entity:GetHPPercent(i)
                    end)
                    local status_ok, status = pcall(function()
                        return entity:GetStatus(i)
                    end)

                    append_trust_detail(result, by_key, {
                        name = name,
                        slot = nil,
                        index = i,
                        hp = hp_ok and tonumber(hp) or nil,
                        status = status_ok and tonumber(status) or nil,
                    })
                end
            end
        end
    end

    return result
end

local function get_party_trusts()
    local result = {}

    for _, detail in ipairs(get_party_trust_details()) do
        table.insert(result, detail.name)
    end

    return result
end

local summon_queue

local function release_trust(name, delay)
    ashita.tasks.once(delay or 0, function()
        cmd('/retr "' .. name .. '"')
    end)
end

local function clear_monitor_pending_later(key)
    ashita.tasks.once(MONITOR_RETRY, function()
        monitor_pending[key] = nil
    end)
end

local function summon_single_when_ready(entry, reason, release_first)
    if not entry then
        return false
    end

    local key = normalize(entry.english)
    if monitor_pending[key] then
        return false
    end

    if not spell_recast_ready(entry.id) then
        monitor_pending[key] = true
        clear_monitor_pending_later(key)
        return false
    end

    monitor_pending[key] = true
    echo((reason or 'Re-summoning') .. ' ' .. entry.english .. '.')

    if release_first then
        trusts.release(entry.english)
    end

    ashita.tasks.once(release_first and config.trusts.wait.retr or 0, function()
        summon_queue({ entry }, 1)
        clear_monitor_pending_later(key)
    end)

    return true
end

summon_queue = function(queue, index)
    if stopped then
        queue_active = false
        return
    end

    index = index or 1

    if index > #queue then
        queue_active = false
        echo('Set summon complete.')
        return
    end

    queue_active = true
    local entry = queue[index]
    cmd('/ma "' .. entry.english .. '" <me>')
    config.trusts.trust_cooldowns[entry.english] = now()

    if save then
        save()
    end

    if config.trusts.auto == false then
        queue_active = false
        return
    end

    local started = false
    local start_time = os.clock()

    local function wait_for_cast()
        if stopped then
            queue_active = false
            return
        end

        local elapsed = os.clock() - start_time

        if elapsed >= CAST_WAIT_TIMEOUT then
            if shared_state.debug == true then
                echo('Cast wait timed out; continuing queue.')
            end
            ashita.tasks.once(config.trusts.wait.aftercast, function()
                summon_queue(queue, index + 1)
            end)
            return
        end

        if player_is_casting() then
            started = true
            ashita.tasks.once(CAST_POLL_INTERVAL, wait_for_cast)
            return
        end

        if not started and elapsed < CAST_START_WINDOW then
            ashita.tasks.once(CAST_POLL_INTERVAL, wait_for_cast)
            return
        end

        ashita.tasks.once(config.trusts.wait.aftercast, function()
            summon_queue(queue, index + 1)
        end)
    end

    ashita.tasks.once(CAST_POLL_INTERVAL, wait_for_cast)
end

-------------------------------------------------
-- PUBLIC API
-------------------------------------------------
function trusts.stop()
    stopped = true
    queue_active = false
    monitor_pending = {}
    maintenance_requested = false
    if maintenance_controller and maintenance_controller.cancel then
        maintenance_controller.cancel()
    end
    maintenance_active = false
end

function trusts.resume()
    stopped = false
end

function trusts.get_trust_options()
    return trust_data.names
end

function trusts.get_active()
    return get_party_trusts()
end

function trusts.get_active_details()
    return get_party_trust_details()
end

function trusts.list_sets()
    ensure_config()

    local names = {}
    for name, _ in pairs(config.trusts.trust_sets or {}) do
        table.insert(names, name)
    end

    table.sort(names)
    return names
end

function trusts.get_set(name)
    ensure_config()

    local set = config.trusts.trust_sets[name]

    if not set then
        return nil
    end

    return valid_set_trusts(set)
end

function trusts.save_set(name)
    ensure_config()

    name = tostring(name or ''):match('^%s*(.-)%s*$')
    if name == '' then
        echo('No set name provided.')
        return false
    end

    local active = get_party_trusts()
    if #active == 0 then
        echo('No active trusts found.')
        return false
    end

    while #active > MAX_TRUSTS do
        table.remove(active)
    end

    config.trusts.trust_sets[name] = active
    config.trusts.selected_set = name

    local saved, save_error = persist_sets()
    if saved == false then
        echo('Could not save set "' .. name .. '": ' .. tostring(save_error))
        return false
    end

    echo('Set "' .. name .. '" saved.')
    return true
end

function trusts.create_set(name, members)
    ensure_config()

    name = tostring(name or ''):match('^%s*(.-)%s*$')
    if name == '' then
        return false, 'missing set name'
    end

    local clean = valid_set_trusts(members or {})
    if #clean == 0 then
        return false, 'set has no valid trusts'
    end

    while #clean > MAX_TRUSTS do
        table.remove(clean)
    end

    config.trusts.trust_sets[name] = clean
    config.trusts.selected_set = name

    persist_sets()

    return true
end

function trusts.delete_set(name)
    ensure_config()

    if name == 'default' then
        echo('Default set cannot be deleted.')
        return false
    end

    if config.trusts.trust_sets[name] then
        config.trusts.trust_sets[name] = nil
        if config.trusts.selected_set == name then
            config.trusts.selected_set = 'default'
        end
        persist_sets()
        echo('Deleted set "' .. name .. '".')
        return true
    end

    echo('Unknown set "' .. tostring(name) .. '".')
    return false
end

function trusts.add_to_set(set_name, trust_name)
    ensure_config()

    local display = trust_display_name(trust_name)
    if not display then
        return false, 'invalid trust'
    end

    config.trusts.trust_sets[set_name] = config.trusts.trust_sets[set_name] or {}
    local set = config.trusts.trust_sets[set_name]
    local key = normalize(display)

    for _, existing in ipairs(set) do
        if normalize(existing) == key then
            return true
        end
    end

    if #set >= MAX_TRUSTS then
        return false, 'trust sets can contain up to 5 trusts'
    end

    table.insert(set, display)

    persist_sets()

    return true
end

function trusts.remove_from_set(set_name, index)
    ensure_config()

    local set = config.trusts.trust_sets[set_name]
    index = tonumber(index)

    if not set or not index or not set[index] then
        return false
    end

    table.remove(set, index)

    persist_sets()

    return true
end

function trusts.summon_set(name)
    ensure_config()

    name = name or config.trusts.selected_set or 'default'
    local set = valid_set_trusts(config.trusts.trust_sets[name])

    if #set == 0 then
        echo('Unknown or empty set "' .. tostring(name) .. '".')
        return false
    end

    if queue_active then
        echo('Summon queue is already running.')
        return false
    end

    config.trusts.last_summoned_set = name
    config.trusts.selected_set = name

    if save then
        save()
    end

    if pulling and pulling.stop then pulling.stop() end
    if targeting and targeting.stop then targeting.stop() end

    local active = {}
    for _, trust in ipairs(get_party_trusts()) do
        active[normalize(trust)] = true
    end

    local desired = {}
    local queue = {}
    for _, trust in ipairs(set) do
        local entry = trust_entry(trust)
        if entry then
            desired[normalize(entry.english)] = true

            if not active[normalize(entry.english)] then
                table.insert(queue, entry)
            end
        end
    end

    local release_delay = 0
    for _, trust in ipairs(get_party_trusts()) do
        if not desired[normalize(trust)] then
            release_trust(trust, release_delay)
            release_delay = release_delay + config.trusts.wait.retr
        end
    end

    if #queue == 0 then
        echo('No trusts need to be summoned.')
        return true
    end

    ashita.tasks.once(release_delay > 0 and config.trusts.wait.retrall or 0, function()
        summon_queue(queue, 1)
    end)

    echo('Summoning set "' .. name .. '".')
    return true
end

function trusts.summon_random()
    ensure_config()

    if queue_active then
        echo('Summon queue is already running.')
        return false
    end

    local checked = {}
    local queue = {}
    local attempts = 0
    local desired_count = 5

    while #queue < desired_count and attempts < #trust_data.list * 2 do
        attempts = attempts + 1
        local entry = trust_data.list[math.random(1, #trust_data.list)]
        local key = normalize(entry.english)

        if not checked[key] then
            checked[key] = true
            table.insert(queue, entry)
        end
    end

    if #queue == 0 then
        echo('No random trusts are ready.')
        return false
    end

    trusts.release_all()
    ashita.tasks.once(config.trusts.wait.retrall, function()
        summon_queue(queue, 1)
    end)

    echo('Summoning a random trust set.')
    return true
end

function trusts.release(name)
    local display = trust_display_name(name) or name
    cmd('/retr "' .. display .. '"')
end

function trusts.release_all()
    ensure_config()
    config.trusts.last_summoned_set = nil
    if save then
        save()
    end
    cmd('/retr all')
end

function trusts.set_monitor_watched(name, enabled)
    ensure_config()

    local display = trust_display_name(name) or name
    if not display or display == '' then
        return false
    end

    config.trusts.monitor.watched[normalize(display)] = enabled == true

    if save then
        save()
    end

    return true
end

local function next_monitor_repair()
    local active_details = get_party_trust_details()
    local active_by_key = {}

    for _, detail in ipairs(active_details) do
        if detail.key then
            active_by_key[detail.key] = detail
        end
    end

    local last_set_name = config.trusts.last_summoned_set
    local last_set = last_set_name
        and valid_set_trusts(config.trusts.trust_sets[last_set_name])
        or {}
    local last_set_keys = {}

    for _, trust_name in ipairs(last_set) do
        local entry = trust_entry(trust_name)
        if entry then
            last_set_keys[normalize(entry.english)] = true
        end
    end

    for _, detail in ipairs(active_details) do
        local entry = trust_entry(detail.name)
        local watched = config.trusts.monitor.watched[detail.key] == true
        local from_last_set = last_set_keys[detail.key] == true

        if entry and (watched or from_last_set) then
            local hp = tonumber(detail.hp)
            local mp = tonumber(detail.mp)
            local dead = (hp ~= nil and hp <= 0)
                or tonumber(detail.status) == 4
            local hp_low = hp and hp > 0
                and hp <= (tonumber(config.trusts.monitor.hp_threshold) or 30)
            local mp_low = mp and mp > 0
                and mp <= (tonumber(config.trusts.monitor.mp_threshold) or 10)

            if dead
            and config.trusts.monitor.resummon_dead == true
            and from_last_set
            then
                return entry, 'Re-summoning dead', true
            end
            if watched and (hp_low or mp_low) then
                return entry, 'Recycling low ' .. (hp_low and 'HP' or 'MP'), true
            end
        end
    end

    if config.trusts.monitor.resummon_dead ~= true or #last_set == 0 then
        return nil
    end

    local composition = get_party_composition()
    if composition.trusts >= composition.trust_slots then
        return nil
    end

    for _, trust_name in ipairs(last_set) do
        local entry = trust_entry(trust_name)
        local key = entry and normalize(entry.english) or ''
        if entry and key ~= '' and not active_by_key[key] then
            return entry, 'Restoring missing', false
        end
    end

    return nil
end

function trusts.tick()
    if stopped then
        return
    end

    ensure_config()

    if config
    and config.trusts
    and config.trusts.monitor
    and config.trusts.monitor.enabled ~= true
    and (maintenance_active or maintenance_requested)
    then
        maintenance_active = false
        maintenance_requested = false
        if maintenance_controller and maintenance_controller.resume then
            maintenance_controller.resume()
        end
        echo('Trust maintenance canceled; automation restored.')
        return
    end

    if not config
    or not config.trusts
    or not config.trusts.monitor
    or config.trusts.monitor.enabled ~= true
    or queue_active
    or player_is_casting()
    then
        return
    end

    local t = os.clock()
    if (t - last_monitor_tick) < MONITOR_INTERVAL then
        return
    end
    last_monitor_tick = t

    local entry, reason, release_first = next_monitor_repair()
    if entry then
        maintenance_requested = true

        if maintenance_controller
        and maintenance_controller.in_combat
        and maintenance_controller.in_combat()
        then
            if maintenance_controller.prepare then
                maintenance_controller.prepare()
            end
            return
        end

        if not maintenance_active then
            maintenance_active = true
            if maintenance_controller and maintenance_controller.pause then
                maintenance_controller.pause()
            end
            echo('Trust maintenance started.')
        end

        local key = normalize(entry.english)
        if not monitor_pending[key] then
            summon_single_when_ready(entry, reason, release_first)
        end
        return
    end

    if maintenance_active then
        maintenance_active = false
        maintenance_requested = false
        if maintenance_controller and maintenance_controller.resume then
            maintenance_controller.resume()
        end
        echo('Trust maintenance complete; automation restored.')
    elseif maintenance_requested then
        maintenance_requested = false
        if maintenance_controller and maintenance_controller.resume then
            maintenance_controller.resume()
        end
    end
end

function trusts.echo_sets()
    local sets = trusts.list_sets()

    if #sets == 0 then
        echo('No saved sets.')
        return
    end

    for _, name in ipairs(sets) do
        local set = trusts.get_set(name) or {}
        echo(name .. ': ' .. table.concat(set, ', '))
    end
end

return trusts
