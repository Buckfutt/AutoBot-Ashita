local common = require('job_helpers.common')

return common.create_ability_job({
    job = 'PLD',
    cooldown = 3,
    abilities = {
        { key='Invincible', name='Invincible', timer=0, level=1 },
        { key='Holy_Circle', name='Holy Circle', timer=74, level=5 },
        { key='Shield_Bash', name='Shield Bash', timer=73, level=15, target='<t>' },
        { key='Sentinel', name='Sentinel', timer=75, buff=62, level=30 },
        { key='Rampart', name='Rampart', timer=77, level=62 },
        { key='Fealty', name='Fealty', timer=78, level=75 },
        { key='Chivalry', name='Chivalry', timer=79, level=75 },
        { key='Divine_Emblem', name='Divine Emblem', timer=80, level=78 },
        { key='Palisade', name='Palisade', timer=242, level=95 },
        { key='Intervene', name='Intervene', timer=254, level=96, target='<t>' },
        { key='Majesty', name='Majesty', timer=253, buff=621, level=70 },
    },
})
