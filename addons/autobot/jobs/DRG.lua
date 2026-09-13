local common = require('job_helpers.common')

return common.create_ability_job({
    job = 'DRG',
    cooldown = 3,
    abilities = {
        { key='Spirit_Surge', name='Spirit Surge', timer=0, level=1 },
        { key='Ancient_Circle', name='Ancient Circle', timer=159, level=5 },
        { key='Jump', name='Jump', timer=158, level=10, target='<t>' },
        { key='High_Jump', name='High Jump', timer=157, level=35, target='<t>' },
        { key='Super_Jump', name='Super Jump', timer=161, level=50, target='<t>' },
        { key='Spirit_Link', name='Spirit Link', timer=162, level=25 },
        { key='Call_Wyvern', name='Call Wyvern', timer=163, level=1 },
        { key='Deep_Breathing', name='Deep Breathing', timer=164, level=75 },
        { key='Angon', name='Angon', timer=165, level=75, target='<t>' },
        { key='Spirit_Jump', name='Spirit Jump', timer=166, level=77, target='<t>' },
        { key='Soul_Jump', name='Soul Jump', timer=167, level=85, target='<t>' },
        { key='Steady_Wing', name='Steady Wing', timer=70, level=95 },
        { key='Fly_High', name='Fly High', timer=254, level=96 },
    },
})
