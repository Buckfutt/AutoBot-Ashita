local common = require('job_helpers.common')

return common.create_ability_job({
    job = 'BST',
    cooldown = 3,
    abilities = {
        { key='Familiar', name='Familiar', timer=0, level=1 },
        { key='Charm', name='Charm', timer=97, level=1, target='<t>' },
        { key='Gauge', name='Gauge', timer=98, level=10, target='<t>' },
        { key='Reward', name='Reward', timer=103, level=12 },
        { key='Call_Beast', name='Call Beast', timer=104, level=23 },
        { key='Sic', name='Sic', timer=102, level=25 },
        { key='Tame', name='Tame', timer=101, level=30, target='<t>' },
        { key='Ready', name='Ready', timer=102, level=25 },
        { key='Spur', name='Spur', timer=253, level=83 },
        { key='Run_Wild', name='Run Wild', timer=254, level=93 },
        { key='Bestial_Loyalty', name='Bestial Loyalty', timer=104, level=23 },
        { key='Unleash', name='Unleash', timer=254, level=96 },
    },
})
