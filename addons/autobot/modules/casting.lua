local casting = {}

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function cmd(str)
    AshitaCore:GetChatManager():QueueCommand(1, str)
end

local function clean_command_name(value)
    value = tostring(value or ''):match('^%s*(.-)%s*$')
    value = value:gsub('%{([^{}]-)%}', '%1')
    value = value:gsub('%(([^()]-)%)', '%1')
    value = value:gsub('^"(.-)"$', '%1')
    return value:match('^%s*(.-)%s*$')
end

-------------------------------------------------
-- CAST SPELL
-------------------------------------------------
function casting.cast_spell(spell, target)
    spell = clean_command_name(spell)
    target = target or '<me>'

    if spell == '' then
        return false
    end

    cmd(string.format('/p Casting [%s] on [%s]', spell, target))
    cmd(string.format('/ma "%s" %s', spell:gsub('"', '\\"'), target))
    return true
end

-------------------------------------------------
-- STOP CASTING
-------------------------------------------------
function casting.stop_casting()
    cmd('/p Canceling Casting...')
    cmd('/heal')

    ashita.tasks.once(2, function()
        cmd('/heal')
    end)
end

function casting.use_ability(ability, target)
    ability = clean_command_name(ability)
    target = tostring(target or '<me>')

    if ability == '' then
        return false
    end

    cmd('/ja "' .. ability:gsub('"', '\\"') .. '" ' .. target)
    return true
end

return casting
