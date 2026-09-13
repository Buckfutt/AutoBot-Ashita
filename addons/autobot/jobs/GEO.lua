local common = require('job_helpers.common')

return common.create_ability_job({
    job = 'GEO',
    cooldown = 3,
    abilities = {
        { key='Bolster', name='Bolster', timer=0, level=1 },
        { key='Full_Circle', name='Full Circle', timer=241, level=5 },
        { key='Life_Cycle', name='Life Cycle', timer=242, level=50 },
        { key='Blaze_of_Glory', name='Blaze of Glory', timer=243, level=60 },
        { key='Dematerialize', name='Dematerialize', timer=244, level=75 },
        { key='Theurgic_Focus', name='Theurgic Focus', timer=245, level=80 },
        { key='Concentric_Pulse', name='Concentric Pulse', timer=246, level=90, target='<t>' },
        { key='Mending_Halation', name='Mending Halation', timer=247, level=95 },
        { key='Radial_Arcana', name='Radial Arcana', timer=248, level=75 },
        { key='Widened_Compass', name='Widened Compass', timer=254, level=96 },
    },
})
