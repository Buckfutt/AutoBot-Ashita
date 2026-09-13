local common = require('job_helpers.common')

return common.create_ability_job({
    job = 'SMN',
    cooldown = 3,
    abilities = {
        { key='Astral_Flow', name='Astral Flow', timer=0, level=1 },
        { key='Elemental_Siphon', name='Elemental Siphon', timer=173, level=50, min_mp_under=80 },
        { key='Mana_Cede', name='Mana Cede', timer=71, level=87 },
        { key='Apogee', name='Apogee', timer=108, level=70 },
        { key='Astral_Conduit', name='Astral Conduit', timer=254, level=96 },
    },
})
