local common = require('job_helpers.common')

return common.create_ability_job({
    job = 'SAM',
    cooldown = 3,
    abilities = {
        { key='Meikyo_Shizui', name='Meikyo Shisui', timer=141, level=1, aliases={'meikyo'} },
        { key='Warding_Circle', name='Warding Circle', timer=132, level=5 },
        { key='Third_Eye', name='Third Eye', timer=133, level=15 },
        { key='Hasso', name='Hasso', timer=138, buff=353, blocks_buffs={354}, level=25 },
        { key='Meditate', name='Meditate', timer=134, level=30 },
        { key='Seigan', name='Seigan', timer=139, buff=354, blocks_buffs={353}, level=35 },
        { key='Sekkanoki', name='Sekkanoki', timer=140, level=40 },
        { key='Konzen_Ittai', name='Konzen-Ittai', timer=147, level=65, target='<t>' },
        { key='Sengikori', name='Sengikori', timer=148, level=77 },
        { key='Hamanoha', name='Hamanoha', timer=149, level=87 },
        { key='Hagakure', name='Hagakure', timer=150, level=95 },
        { key='Yaegasumi', name='Yaegasumi', timer=254, level=96 },
    },
})
