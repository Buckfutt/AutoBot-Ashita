local common = require('job_helpers.common')

return common.create_ability_job({
    job = 'WAR',
    cooldown = 3,
    abilities = {
        { key='Berserk', name='Berserk', timer=1, buff=56, level=15 },
        { key='Warcry', name='Warcry', timer=2, level=35 },
        { key='Defender', name='Defender', timer=3, buff=57, level=25 },
        { key='Aggressor', name='Aggressor', timer=4, buff=58, level=45 },
        { key='Brazen_Rush', name='Brazen Rush', timer=7, level=96 },
        { key='Blood_Rage', name='Blood Rage', timer=9, level=87 },
        { key='Warriors_Charge', name="Warrior's Charge", timer=12, level=75, aliases={'warriorcharge'} },
        { key='Retaliation', name='Retaliation', timer=15, buff=405, level=60 },
        { key='Restraint', name='Restraint', timer=16, buff=428, level=77 },
        { key='Mighty_Strikes', name='Mighty Strikes', timer=20, level=1 },
    },
})
