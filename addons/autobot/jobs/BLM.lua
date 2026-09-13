local common = require('job_helpers.common')

return common.create_ability_job({
    job = 'BLM',
    cooldown = 3,
    abilities = {
        { key='Manafont', name='Manafont', timer=0, level=1 },
        { key='Elemental_Seal', name='Elemental Seal', timer=38, level=15 },
        { key='Mana_Wall', name='Mana Wall', timer=254, buff=457, level=76 },
        { key='Enmity_Douse', name='Enmity Douse', timer=175, level=87 },
        { key='Manawell', name='Manawell', timer=254, level=95 },
        { key='Subtle_Sorcery', name='Subtle Sorcery', timer=254, level=96 },
    },
})
