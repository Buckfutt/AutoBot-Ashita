addon.name      = 'AutoBot'
addon.author    = 'K0D3R'
addon.version   = '2.0.0'
addon.desc      = 'Automation framework with manual settings system.'

require('common')

-------------------------------------------------
-- SETTINGS PATH
-------------------------------------------------
local settings_dir = string.format(
    '%sconfig/addons/AutoBot/',
    AshitaCore:GetInstallPath()
)

local function get_character_name()
    local ok, name = pcall(function()
        local player = AshitaCore:GetMemoryManager():GetPlayer()
        if player and type(player.GetName) == 'function' then
            return player:GetName()
        end

        local party = AshitaCore:GetMemoryManager():GetParty()
        if party then
            return party:GetMemberName(0)
        end
    end)

    if not ok or not name or name == '' then
        return nil
    end

    return tostring(name):gsub('[^%w_%-]', '')
end

local character_name = get_character_name()
local loaded_character_name = character_name
local settings_path = character_name and string.format(
    '%ssettings_%s.lua',
    settings_dir,
    character_name
) or nil

-------------------------------------------------
-- LOAD SETTINGS
-------------------------------------------------
local function load_settings()
    local config = {
        debug = false,
        whitelist = {},
        target_list = {},

        targeting = {
            max_distance = 20,
            ignore_claimed = false,
            prefer_unclaimed = true,
        },

        modules = {
            combat      = true,
            autows      = true,
            jobs        = true,
            targeting   = false,
            general     = true,
            trusts      = true,
            uberwarp    = true,
            casting     = true,
            interaction = true,
            navigation  = true,
            follow      = true,
            pulling     = false,
            items       = true,
        },

        pulling = {
            use_ranged  = false,
            use_ability = false,
            use_spell   = false,
            ability     = '',
            spell       = '',
            timeout     = 8,
        },

        combat = {
            auto_engage = false,
            approach = false,
            auto_face = false,
            auto_assist = false,
            assist_target = '',
            manage_hp = false,
            hp_minimum = 0,
            hp_maximum = 100,
            manage_mp = false,
            mp_minimum = 0,
            mp_maximum = 100,
        },

        autows = {
            enabled = false,
            weaponskill = '',
            tp_amount = 1000,
            aftermath_tp_amount = 3000,
            cooldown = 3.0,
            use_aftermath = true,
            skillchains_enabled = true,
            show_skillchain_window = true,
            open_skillchains = false,
            close_skillchains = false,
            open_weaponskill = '',
            open_tp_amount = 1000,
            close_tp_amount = 1000,
            close_window_minimum = 1.0,
            level_priority = '4,3,2,1',
            chain_priority = '',
            close_ws_priority = '',
            blacklist = 'Cyclone,Aeolian Edge,Fell Cleave,Sonic Thrust,Spinning Attack,Shockwave,Earth Crusher,Cataclysm,Spinning Scythe,Circle Blade',
        },

        items = {
            food = {
                enabled = false,
                name = '',
                retry_delay = 15,
            },
        },

        trusts = {
            auto = true,
            selected_set = 'default',
            selected_trust = 'Valaineral',
            trust_sets = {
                default = {
                    'Valaineral',
                    'Mihli Aliapoh',
                    'Tenzen',
                    'Adelheid',
                    'Joachim',
                },
            },
            trust_cooldowns = {},
            monitor = {
                enabled = false,
                resummon_dead = false,
                hp_threshold = 30,
                mp_threshold = 10,
                watched = {},
            },
            wait = {
                aftercast = 3,
                retr = 1.25,
                retrall = 3,
            },
        },

        job_modules = {},
        ui = {
            show_job_windows = false,
            main_job_window_open = true,
            sub_job_window_open = true,
        },
        runtime = {
            targeting = false,
            pulling = false,
        },
    }

    local load_path = settings_path
    local f = load_path and io.open(load_path, 'r') or nil

    if f then
        f:close()

        local ok, saved = pcall(dofile, load_path)
        if ok and type(saved) == 'table' then
            config = saved
        end
    end

    config.targeting = config.targeting or {}
    -- Remove the retired targeting/pulling diagnostic setting from older
    -- character profiles when they are next saved.
    config.logging = nil
    config.modules = config.modules or {}
    config.pulling = config.pulling or {}
    config.combat = config.combat or {}
    config.autows = config.autows or {}
    config.items = config.items or {}
    -- Remove retired fishing settings from existing character profiles.
    config.fishing = nil
    config.trusts = config.trusts or {}
    config.job_modules = config.job_modules or {}
    config.ui = config.ui or {}
    config.runtime = {
        targeting = false,
        pulling = false,
    }

    -- Names are compared case-insensitively by the remote-command handler.
    -- Normalize loaded values so older/manual files (including sparse tables)
    -- cannot silently make valid whitelist entries disappear.
    local normalized_whitelist = {}
    local seen_whitelist = {}
    for key, value in pairs(config.whitelist or {}) do
        -- Support both the normal array form and older/manual
        -- { PlayerName = true } tables.
        local entry = type(key) == 'string' and value == true and key or value
        local name = tostring(entry or ''):match('^%s*(.-)%s*$'):lower()
        if name ~= '' and not seen_whitelist[name] then
            table.insert(normalized_whitelist, name)
            seen_whitelist[name] = true
        end
    end
    config.whitelist = normalized_whitelist
    config.target_list = config.target_list or {}

    local module_defaults = {
        combat      = true,
        autows      = true,
        jobs        = true,
        targeting   = false,
        general     = true,
        trusts      = true,
        uberwarp    = true,
        casting     = true,
        interaction = true,
        navigation  = true,
        follow      = true,
        pulling     = false,
        items       = true,
    }

    for name, value in pairs(module_defaults) do
        if config.modules[name] == nil then
            config.modules[name] = value
        end
    end

    config.targeting.max_distance = tonumber(config.targeting.max_distance) or 20
    config.targeting.aggro_bonus = nil
    config.targeting.ignore_claimed = config.targeting.ignore_claimed == true
    config.targeting.prefer_unclaimed = config.targeting.prefer_unclaimed ~= false

    config.pulling.use_ranged = config.pulling.use_ranged == true
    config.pulling.use_ability = config.pulling.use_ability == true
    config.pulling.use_spell = config.pulling.use_spell == true
    config.pulling.ability = config.pulling.ability or ''
    config.pulling.spell = config.pulling.spell or ''
    if config.debug == nil and config.pulling.debug ~= nil then
        config.debug = config.pulling.debug == true
    end
    config.debug = config.debug == true
    config.pulling.debug = nil

    config.pulling.timeout =
        tonumber(config.pulling.timeout) or 8

    config.combat.auto_engage = config.combat.auto_engage == true
    config.combat.approach = config.combat.approach == true
    config.combat.auto_face = config.combat.auto_face == true
    config.combat.auto_assist = config.combat.auto_assist == true
    config.combat.assist_target = config.combat.assist_target or ''
    config.combat.manage_hp = config.combat.manage_hp == true
    config.combat.hp_minimum = math.max(0, math.min(100, tonumber(config.combat.hp_minimum) or 0))
    config.combat.hp_maximum = math.max(config.combat.hp_minimum, math.min(100, tonumber(config.combat.hp_maximum) or 100))
    config.combat.manage_mp = config.combat.manage_mp == true
    config.combat.mp_minimum = math.max(0, math.min(100, tonumber(config.combat.mp_minimum) or 0))
    config.combat.mp_maximum = math.max(config.combat.mp_minimum, math.min(100, tonumber(config.combat.mp_maximum) or 100))
    config.autows.enabled = config.autows.enabled == true
    config.autows.weaponskill = config.autows.weaponskill or ''
    config.autows.tp_amount = tonumber(config.autows.tp_amount) or 1000
    config.autows.aftermath_tp_amount = tonumber(config.autows.aftermath_tp_amount) or 3000
    config.autows.cooldown = tonumber(config.autows.cooldown) or 3.0
    if config.autows.use_aftermath == nil and config.autows.use_am3 ~= nil then
        config.autows.use_aftermath = config.autows.use_am3
    end
    config.autows.use_aftermath = config.autows.use_aftermath ~= false
    config.autows.use_am3 = nil
    config.autows.skillchains_enabled = config.autows.skillchains_enabled ~= false
    config.autows.show_skillchain_window = config.autows.show_skillchain_window ~= false
    config.autows.open_skillchains = config.autows.open_skillchains == true
    config.autows.close_skillchains = config.autows.close_skillchains == true
    config.autows.open_weaponskill = config.autows.open_weaponskill or ''
    config.autows.open_tp_amount = tonumber(config.autows.open_tp_amount) or 1000
    config.autows.close_tp_amount = tonumber(config.autows.close_tp_amount) or 1000
    config.autows.close_window_minimum = tonumber(config.autows.close_window_minimum) or 1.0
    config.autows.level_priority = config.autows.level_priority or '4,3,2,1'
    config.autows.chain_priority = config.autows.chain_priority or ''
    config.autows.close_ws_priority = config.autows.close_ws_priority or ''
    config.autows.blacklist = config.autows.blacklist or 'Cyclone,Aeolian Edge,Fell Cleave,Sonic Thrust,Spinning Attack,Shockwave,Earth Crusher,Cataclysm,Spinning Scythe,Circle Blade'
    config.items.food = config.items.food or {}
    config.items.food.enabled = config.items.food.enabled == true
    config.items.food.name = config.items.food.name or ''
    config.items.food.retry_delay = tonumber(config.items.food.retry_delay) or 15
    if config.items.food.retry_delay < 5 then config.items.food.retry_delay = 5 end
    if config.items.food.retry_delay > 120 then config.items.food.retry_delay = 120 end
    config.trusts.auto = config.trusts.auto ~= false
    config.trusts.selected_set = config.trusts.selected_set or 'default'
    config.trusts.selected_trust = config.trusts.selected_trust or 'Valaineral'
    config.trusts.trust_sets = config.trusts.trust_sets or {}
    config.trusts.trust_sets.default = config.trusts.trust_sets.default or {
        'Valaineral',
        'Mihli Aliapoh',
        'Tenzen',
        'Adelheid',
        'Joachim',
    }
    config.trusts.trust_cooldowns = config.trusts.trust_cooldowns or {}
    config.trusts.monitor = config.trusts.monitor or {}
    config.trusts.monitor.enabled = config.trusts.monitor.enabled == true
    config.trusts.monitor.resummon_dead = config.trusts.monitor.resummon_dead == true
    config.trusts.monitor.hp_threshold = tonumber(config.trusts.monitor.hp_threshold) or 30
    config.trusts.monitor.mp_threshold = tonumber(config.trusts.monitor.mp_threshold) or 10
    config.trusts.monitor.watched = config.trusts.monitor.watched or {}
    config.trusts.wait = config.trusts.wait or {}
    config.trusts.wait.aftercast = tonumber(config.trusts.wait.aftercast) or 3
    config.trusts.wait.retr = tonumber(config.trusts.wait.retr) or 1.25
    config.trusts.wait.retrall = tonumber(config.trusts.wait.retrall) or 3
    config.ui.show_job_windows = config.ui.show_job_windows == true
    config.ui.main_job_window_open = config.ui.main_job_window_open ~= false
    config.ui.sub_job_window_open = config.ui.sub_job_window_open ~= false

    return config
end

-------------------------------------------------
-- SAVE SETTINGS
-------------------------------------------------
local function save_settings(config)
    if ashita and ashita.fs then
        if type(ashita.fs.create_dir) == 'function' then
            ashita.fs.create_dir(settings_dir)
        elseif type(ashita.fs.create_directory) == 'function' then
            ashita.fs.create_directory(settings_dir)
        end
    end

    -- The addon can remain loaded while switching characters, so the cached
    -- startup name may no longer identify the active character.
    local current_character = get_character_name()
    if current_character then
        if current_character ~= loaded_character_name then
            return false, 'active character profile has not finished loading'
        end
        character_name = current_character
        settings_path = string.format(
            '%ssettings_%s.lua',
            settings_dir,
            character_name
        )
    end

    if not character_name then
        return false, 'character name is not available'
    end

    local function escape_string(value)
        return tostring(value or '')
            :gsub('\\', '\\\\')
            :gsub('\r', '\\r')
            :gsub('\n', '\\n')
            :gsub('\t', '\\t')
            :gsub('"', '\\"')
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

    local function sorted_keys(tbl)
        local keys = {}
        for k, _ in pairs(tbl or {}) do
            table.insert(keys, k)
        end

        table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
        end)

        return keys
    end

    local function write_value(value, indent)
        indent = indent or 0
        local pad = string.rep(' ', indent)
        local child_pad = string.rep(' ', indent + 4)

        if type(value) == 'table' then
            local out = "{\n"

            if is_array(value) then
                for _, item in ipairs(value) do
                    out = out .. child_pad .. write_value(item, 0) .. ",\n"
                end
            else
                for _, key in ipairs(sorted_keys(value)) do
                    local safe_key
                    if type(key) == 'string' and key:match('^[%a_][%w_]*$') then
                        safe_key = key
                    else
                        safe_key = '[' .. write_value(key, 0) .. ']'
                    end

                    out = out .. child_pad .. safe_key .. " = " ..
                        write_value(value[key], indent + 4) .. ",\n"
                end
            end

            return out .. pad .. "}"
        end

        if type(value) == 'string' then
            return '"' .. escape_string(value) .. '"'
        end

        if type(value) == 'number' then
            return tostring(value)
        end

        if type(value) == 'boolean' then
            return tostring(value)
        end

        return 'nil'
    end

    local ok, serialized = pcall(function()
        return 'return ' .. write_value(config, 0) .. '\n'
    end)
    if not ok then
        return false, 'could not serialize settings: ' .. tostring(serialized)
    end

    local f, open_error = io.open(settings_path, 'w+')
    if not f then
        return false, 'could not open settings file: ' .. tostring(open_error)
    end

    local wrote, write_error = f:write(serialized)
    if wrote then
        f:flush()
    end
    f:close()

    if not wrote then
        return false, 'could not write settings file: ' .. tostring(write_error)
    end

    return true, settings_path
end

-------------------------------------------------
-- LOAD CONFIG & FORCE DORMANT ON STARTUP
-------------------------------------------------
local config = load_settings()

-- Force modules to stay off when loading, regardless of settings file states
config.runtime.targeting = false
config.runtime.pulling = false

-------------------------------------------------
-- MODULE MODULE REQUIREMENTS
-------------------------------------------------
local scripts = {}
scripts.general      = require('modules.general')
scripts.follow       = require('modules.follow')
scripts.targeting    = require('modules.targeting')
scripts.pulling      = require('modules.pulling')
scripts.combat       = require('modules.combat')
scripts.autows       = require('modules.autows')
scripts.casting      = require('modules.casting')
scripts.interaction  = require('modules.interaction')
scripts.navigation   = require('modules.navigation')
scripts.trusts       = require('modules.trusts')
scripts.jobs         = require('modules.jobs')
scripts.items        = require('modules.items')

local cmd    = require('core.commands')
local remote = require('core.remote')
local ui     = require('core.ui')

scripts.save = function()
    return save_settings(config)
end

local function bind_config_to_modules()
    if ui and type(ui.set_config) == 'function' then
        ui.set_config(config)
    end
    if scripts.combat and type(scripts.combat.set_settings) == 'function' then
        scripts.combat.set_settings(config)
    end
    if scripts.autows and type(scripts.autows.set_settings) == 'function' then
        scripts.autows.set_settings(config)
    end
    if scripts.targeting and type(scripts.targeting.set_settings) == 'function' then
        scripts.targeting.set_settings(config)
    end
    if scripts.pulling and type(scripts.pulling.set_settings) == 'function' then
        scripts.pulling.set_settings(config)
    end
    if scripts.trusts and type(scripts.trusts.set_config) == 'function' then
        scripts.trusts.set_config(config, scripts.save)
    end
    if scripts.jobs and type(scripts.jobs.set_config) == 'function' then
        scripts.jobs.set_config(config, scripts.save)
    end
    if scripts.items and type(scripts.items.set_config) == 'function' then
        scripts.items.set_config(config, scripts.save)
    end
end

bind_config_to_modules()

local function load_character_profile(name, force)
    name = tostring(name or ''):gsub('[^%w_%-]', '')
    if name == '' or (name == loaded_character_name and force ~= true) then
        return false
    end

    character_name = name
    settings_path = string.format(
        '%ssettings_%s.lua',
        settings_dir,
        character_name
    )

    local loaded = load_settings()
    for key, _ in pairs(config) do
        config[key] = nil
    end
    for key, value in pairs(loaded) do
        config[key] = value
    end

    config.runtime = config.runtime or {}
    config.runtime.targeting = false
    config.runtime.pulling = false
    loaded_character_name = name
    bind_config_to_modules()

    AshitaCore:GetChatManager():QueueCommand(
        1,
        '/echo [AutoBot] Loaded character settings: ' .. name
    )
    return true
end

scripts.reload_profile = function()
    local name = get_character_name()
    if not name then
        return false, 'character name is not available'
    end

    if load_character_profile(name, true) then
        return true, settings_path
    end

    return false, 'could not reload character settings'
end

if scripts.trusts and type(scripts.trusts.set_modules) == 'function' then
    scripts.trusts.set_modules(scripts.pulling, scripts.targeting)
end
if scripts.pulling and type(scripts.pulling.set_modules) == 'function' then
    scripts.pulling.set_modules(scripts.targeting)
end

-------------------------------------------------
-- ROUTE CHAT COMMAND HANDLING
-------------------------------------------------
local function is_whitelisted(sender)
    sender = sender and tostring(sender):lower() or ''

    for _, name in ipairs(config.whitelist or {}) do
        if tostring(name):lower() == sender then
            return true
        end
    end

    return false
end

local function dispatch_args(args)
    cmd.handle(args, {
        config = config,
        scripts = scripts,
        save = scripts.save,
        ui = ui
    })
end

ashita.events.register('command', 'command_cb', function(e)
    local args = e.command:args()
    if #args == 0 then return end

    local cmd_name = args[1]:lower()
    if cmd_name ~= '/autobot' and cmd_name ~= '/ab' then return end

    e.blocked = true
    table.remove(args, 1)

    dispatch_args(args)
end)

local function remote_context()
    return {
        whitelist = is_whitelisted,
        handle_args = function(args)
            dispatch_args(args)
        end,
        execute = function(command_string)
            AshitaCore:GetChatManager():QueueCommand(1, command_string)
        end
    }
end

ashita.events.register('text_in', 'autobot_remote_text_in_cb', function(e)
    if scripts.pulling
    and type(scripts.pulling.handle_text) == 'function'
    then
        scripts.pulling.handle_text(e)
    end
end)

-------------------------------------------------
-- COMPONENT RENDER TICK LOGIC
-------------------------------------------------
local targeting_active = false
local pulling_active  = false
local last_ui_error_at = 0
local shared_state = require('modules.state')
local safety_halted = false
local zone_in_progress = false
local death_resume_state = nil
local trust_maintenance_resume = nil

local function reset_runtime_coordination()
    shared_state.auto_assist_active = false
    shared_state.combat_lock = false
    shared_state.target_server_id = 0
    shared_state.target_index = -1
    shared_state.target_locked_at = 0
    shared_state.pull_in_progress = false
    shared_state.pull_target_id = 0
    shared_state.pull_started_at = 0
    shared_state.pull_completed = false
    shared_state.force_retarget = false
    shared_state.force_retarget_reason = ''
    shared_state.combat_settle_until = 0
    shared_state.trust_maintenance = false
    shared_state.player_resting = false
end

local function player_is_engaged()
    local memory = AshitaCore:GetMemoryManager()
    local player = memory:GetPlayer()
    local party = memory:GetParty()
    local entity = memory:GetEntity()
    local player_status = nil
    local entity_status = nil

    if player then
        pcall(function()
            player_status = tonumber(player:GetStatus())
        end)
    end
    if party and entity then
        pcall(function()
            local index = tonumber(party:GetMemberTargetIndex(0)) or 0
            if index > 0 then
                entity_status = tonumber(entity:GetStatus(index))
            end
        end)
    end

    if player_status ~= nil then
        return player_status == 1
    end

    return entity_status == 1
end

local function prepare_trust_maintenance()
    if not trust_maintenance_resume then
        trust_maintenance_resume = {
            targeting = config.runtime.targeting == true,
            pulling = config.runtime.pulling == true,
            navigation = scripts.navigation
                and type(scripts.navigation.is_playing) == 'function'
                and scripts.navigation.is_playing()
                or false,
            navigation_paused = scripts.navigation
                and type(scripts.navigation.is_paused) == 'function'
                and scripts.navigation.is_paused()
                or false,
        }
    end

    config.runtime.targeting = false
    config.runtime.pulling = false
    targeting_active = false
    pulling_active = false
    if scripts.targeting and type(scripts.targeting.stop) == 'function' then
        scripts.targeting.stop()
    end
    if scripts.pulling and type(scripts.pulling.stop) == 'function' then
        scripts.pulling.stop()
    end
end

local function begin_trust_maintenance()
    prepare_trust_maintenance()
    shared_state.trust_maintenance = true

    if scripts.combat and type(scripts.combat.shutdown) == 'function' then
        scripts.combat.shutdown()
    end
    if scripts.navigation and type(scripts.navigation.pause_playback) == 'function' then
        scripts.navigation.pause_playback()
    end
    if scripts.follow and type(scripts.follow.pause_follow) == 'function' then
        scripts.follow.pause_follow()
    end
    AshitaCore:GetChatManager():QueueCommand(1, '/movement navstop')
end

local function finish_trust_maintenance()
    local resume = trust_maintenance_resume or {}
    shared_state.trust_maintenance = false
    config.runtime.targeting = resume.targeting == true
    config.runtime.pulling = resume.pulling == true

    if resume.navigation
    and not resume.navigation_paused
    and scripts.navigation
    and type(scripts.navigation.resume_playback) == 'function'
    then
        scripts.navigation.resume_playback()
    end
    if scripts.follow and type(scripts.follow.resume_follow) == 'function' then
        scripts.follow.resume_follow()
    end

    trust_maintenance_resume = nil
end

local function cancel_trust_maintenance()
    shared_state.trust_maintenance = false
    trust_maintenance_resume = nil
end

if scripts.trusts and type(scripts.trusts.set_maintenance_controller) == 'function' then
    scripts.trusts.set_maintenance_controller({
        in_combat = player_is_engaged,
        prepare = prepare_trust_maintenance,
        pause = begin_trust_maintenance,
        resume = finish_trust_maintenance,
        cancel = cancel_trust_maintenance,
    })
end

local function stop_runtime_automation(reason, disable_jobs)
    config.runtime = config.runtime or {}
    local is_resumable_stop = reason == 'manual full stop'

    if is_resumable_stop and not death_resume_state then
        local maintenance_resume = trust_maintenance_resume or {}
        death_resume_state = {
            -- Trust maintenance temporarily turns these runtime flags off.
            -- Preserve the real pre-maintenance state if death occurs then.
            targeting = maintenance_resume.targeting == true
                or config.runtime.targeting == true,
            pulling = maintenance_resume.pulling == true
                or config.runtime.pulling == true,
            navigation = scripts.navigation
                and type(scripts.navigation.is_playing) == 'function'
                and scripts.navigation.is_playing()
                or false,
        }
    end

    config.runtime.targeting = false
    config.runtime.pulling = false
    targeting_active = false
    pulling_active = false

    if scripts.pulling and type(scripts.pulling.stop) == 'function' then
        scripts.pulling.stop()
    end
    if scripts.targeting and type(scripts.targeting.stop) == 'function' then
        scripts.targeting.stop()
    end
    if scripts.combat and type(scripts.combat.shutdown) == 'function' then
        scripts.combat.shutdown()
    end
    if scripts.follow and type(scripts.follow.stop_follow) == 'function' then
        scripts.follow.stop_follow()
    end
    if scripts.navigation then
        if type(scripts.navigation.stop_record) == 'function' then
            scripts.navigation.stop_record()
        end
        if is_resumable_stop and type(scripts.navigation.pause_playback) == 'function' then
            scripts.navigation.pause_playback()
        elseif type(scripts.navigation.stop_playback) == 'function' then
            scripts.navigation.stop_playback()
        end
    end
    if scripts.trusts and type(scripts.trusts.stop) == 'function' then
        scripts.trusts.stop()
    end
    if scripts.jobs and type(scripts.jobs.stop_all) == 'function' then
        scripts.jobs.stop_all(reason, disable_jobs == true)
    end

    reset_runtime_coordination()
end

scripts.full_stop = function()
    if safety_halted then
        AshitaCore:GetChatManager():QueueCommand(1, '/echo [AutoBot] Automation is already safety-paused.')
        return false
    end

    safety_halted = true
    stop_runtime_automation('manual full stop', false)
    AshitaCore:GetChatManager():QueueCommand(1, '/echo [AutoBot] Full stop engaged. Use /ab resume to continue.')
    return true
end

scripts.resume_automation = function()
    if not safety_halted then
        AshitaCore:GetChatManager():QueueCommand(1, '/echo [AutoBot] Automation is not safety-paused.')
        return false
    end

    local resume = death_resume_state or {}
    config.runtime = config.runtime or {}
    config.runtime.targeting = resume.targeting == true
    config.runtime.pulling = resume.pulling == true

    reset_runtime_coordination()

    if scripts.combat and type(scripts.combat.set_settings) == 'function' then
        scripts.combat.set_settings(config)
    end
    if scripts.targeting and type(scripts.targeting.set_settings) == 'function' then
        scripts.targeting.set_settings(config)
    end
    if scripts.pulling and type(scripts.pulling.set_settings) == 'function' then
        scripts.pulling.set_settings(config)
    end
    if scripts.trusts and type(scripts.trusts.resume) == 'function' then
        -- Return the trust module to an idle usable state only. Dead trusts
        -- must be explicitly summoned again through the normal trust flow.
        scripts.trusts.resume()
    end

    if resume.navigation
    and scripts.navigation
    and type(scripts.navigation.resume_playback) == 'function'
    then
        scripts.navigation.resume_playback()
    end

    safety_halted = false
    death_resume_state = nil
    AshitaCore:GetChatManager():QueueCommand(1, '/echo [AutoBot] Automation resumed.')
    return true
end

local function player_is_mounted()
    local memory = AshitaCore:GetMemoryManager()
    local player = memory:GetPlayer()
    if not player then
        return false
    end

    local ok_buffs, buffs = pcall(function()
        if type(player.GetBuffs) == 'function' then
            return player:GetBuffs()
        end
        return player:GetStatusIcons()
    end)
    if not ok_buffs or not buffs then
        return false
    end

    for index = 0, 31 do
        local ok_buff, buff = pcall(function()
            return buffs[index]
        end)

        if ok_buff and tonumber(buff) == 252 then
            return true
        end
    end

    return false
end

local function handle_zone_start(mark_in_progress)
    if mark_in_progress ~= false then
        zone_in_progress = true
        shared_state.zone_in_progress = true
        shared_state.resource_settle_until = 0
    end
    shared_state.player_resting = false
    config.runtime = config.runtime or {}
    config.runtime.targeting = false
    config.runtime.pulling = false
    targeting_active = false
    pulling_active = false

    if scripts.pulling and type(scripts.pulling.stop) == 'function' then
        scripts.pulling.stop()
    end
    if scripts.targeting and type(scripts.targeting.stop) == 'function' then
        scripts.targeting.stop()
    end
    if scripts.navigation then
        if type(scripts.navigation.stop_record) == 'function' then
            scripts.navigation.stop_record()
        end
        if type(scripts.navigation.stop_playback) == 'function' then
            scripts.navigation.stop_playback()
        end
    end
    if scripts.jobs and type(scripts.jobs.stop_all) == 'function' then
        scripts.jobs.stop_all('zone change', true)
    end
end

ashita.events.register('d3d_present', 'present_cb', function()
    local active_character = get_character_name()
    if active_character and active_character ~= loaded_character_name then
        load_character_profile(active_character)
    end

    shared_state.debug = config.debug == true
    local mounted = player_is_mounted()

    if mounted and shared_state.mounted ~= true then
        -- Stop any persistent Movement-plugin vector. Navigation remains
        -- configured and resumes on its next tick after dismounting.
        AshitaCore:GetChatManager():QueueCommand(1, '/movement navstop')
    end
    shared_state.mounted = mounted

    local player = AshitaCore:GetMemoryManager():GetPlayer()

    if player and not safety_halted and not mounted then
        if not shared_state.trust_maintenance
        and config.modules.combat
        and config.combat
        and config.combat.auto_face
        and scripts.combat
        and type(scripts.combat.start_face_loop) == 'function'
        then
            scripts.combat.start_face_loop()
        end

        if not shared_state.trust_maintenance
        and config.modules.combat
        and scripts.combat
        and type(scripts.combat.tick) == 'function'
        then
            scripts.combat.tick()
        end

        if not shared_state.trust_maintenance
        and config.modules.autows
        and scripts.autows
        and type(scripts.autows.tick) == 'function'
        then
            scripts.autows.tick()
        end

        if config.modules.trusts
        and scripts.trusts
        and type(scripts.trusts.tick) == 'function'
        then
            scripts.trusts.tick()
        end

        if not shared_state.trust_maintenance
        and config.modules.jobs
        and scripts.jobs
        and type(scripts.jobs.tick) == 'function'
        then
            scripts.jobs.tick()
        end

        if not shared_state.trust_maintenance
        and config.modules.items
        and scripts.items
        and type(scripts.items.tick) == 'function'
        then
            scripts.items.tick()
        end

        -------------------------------------------------
        -- TARGETING SYNC CONTROL
        -------------------------------------------------
        if config.modules.targeting
        and config.runtime.targeting
        and shared_state.player_resting ~= true
        then
            if not targeting_active then
                scripts.targeting.set_settings(config)
                scripts.targeting.start()
                targeting_active = true
            end
        else
            if targeting_active then
                scripts.targeting.stop()
                targeting_active = false
            end
        end

        -------------------------------------------------
        -- PULLING SYNC CONTROL
        -------------------------------------------------
        if config.modules.pulling
        and config.runtime.pulling
        and shared_state.player_resting ~= true
        then
            if not pulling_active then
                scripts.pulling.set_settings(config)
                scripts.pulling.start()
                pulling_active = true
            end
        else
            if pulling_active then
                scripts.pulling.stop()
                pulling_active = false
            end
        end

        -------------------------------------------------
        -- NAVIGATION TICK
        -------------------------------------------------
        if not shared_state.trust_maintenance
        and config.modules.navigation
        and scripts.navigation
        and type(scripts.navigation.tick) == 'function'
        then
            scripts.navigation.tick()
        end
    end

    local ok, err = pcall(function()
        ui.render(config, scripts)
    end)

    if not ok
    and config.debug == true
    and (os.clock() - last_ui_error_at) >= 2
    then
        last_ui_error_at = os.clock()

        AshitaCore:GetChatManager():QueueCommand(
            1,
            '/echo [AutoBot] UI error: ' .. tostring(err)
        )
    end
end)

ashita.events.register('packet_in', 'autobot_packet_in_cb', function(e)
    if e.id == 0x0017 then
        local data = e.data_modified or e.data
        local mode = struct.unpack('B', data, 0x04 + 1)

        -- FFXI chat packet modes: tell = 3, party = 4.
        if mode == 3 or mode == 4 then
            local sender = struct.unpack('c15', data, 0x08 + 1):trimend('\x00')
            local message = struct.unpack('s', data, 0x17 + 1)

            message = AshitaCore:GetChatManager():ParseAutoTranslate(message, true)
            message = message:strip_colors():strip_translate(true)
            message = message:gsub('[\r\n]+$', '')

            remote.handle_message(
                sender,
                message,
                mode == 3 and 'tell' or 'party',
                remote_context()
            )
        end
    end

    if e.id == 0x00A then
        handle_zone_start(true)
    elseif e.id == 0x01B then
        zone_in_progress = false
        shared_state.zone_in_progress = false
        shared_state.resource_settle_until = os.clock() + 5.0
    end

    if e.id == 0x0028
    and scripts.autows
    and type(scripts.autows.handle_packet) == 'function'
    then
        scripts.autows.handle_packet(e)
    end

    if e.id == 0x0028
    and scripts.pulling
    and type(scripts.pulling.handle_packet_in) == 'function'
    then
        scripts.pulling.handle_packet_in(e)
    end
end)

ashita.events.register('packet_out', 'autobot_packet_out_cb', function(e)
    if e.id == 0x001A
    and scripts.pulling
    and type(scripts.pulling.handle_packet_out) == 'function'
    then
        scripts.pulling.handle_packet_out(e)
    end
end)

-------------------------------------------------
-- SYSTEM STAGE HANDLERS
-------------------------------------------------
ashita.events.register('load', 'load_cb', function()
    config.runtime = config.runtime or {}
    config.runtime.targeting = false
    config.runtime.pulling = false

    if ui and type(ui.show) == 'function' then
        ui.show()
    end

    AshitaCore:GetChatManager():QueueCommand(1, '/echo [AutoBot] loaded successfully.')
end)

ashita.events.register('zone_change', 'autobot_jobs_zone_change', function()
    handle_zone_start(false)
end)

ashita.events.register('unload', 'unload_cb', function()
    if scripts.combat and type(scripts.combat.shutdown) == 'function' then
        scripts.combat.shutdown()
    end
    if scripts.pulling and type(scripts.pulling.stop) == 'function' then
        scripts.pulling.stop()
    end
    if scripts.targeting and type(scripts.targeting.stop) == 'function' then
        scripts.targeting.stop()
    end
    if scripts.navigation then
        if type(scripts.navigation.stop_record) == 'function' then
            scripts.navigation.stop_record()
        end
        if type(scripts.navigation.stop_playback) == 'function' then
            scripts.navigation.stop_playback()
        end
    end
    if scripts.jobs and type(scripts.jobs.stop_all) == 'function' then
        scripts.jobs.stop_all()
    end
end)

local function build_uberwarp_alias(location, index)
    local alias = tostring(location or ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('"', '')
    local warp_index = math.floor(tonumber(index) or 1)

    return alias, warp_index
end

function scripts.uberwarp(wtype, location, index)
    local warp_type = tostring(wtype or ''):lower():gsub('"', '')
    local alias, warp_index = build_uberwarp_alias(location, index)

    if warp_type == '' or alias == '' then
        return
    end

    local command_string = warp_index > 1
        and string.format('/uw %s "%s" %d', warp_type, alias, warp_index)
        or string.format('/uw %s "%s"', warp_type, alias)
    AshitaCore:GetChatManager():QueueCommand(1, command_string)
end
