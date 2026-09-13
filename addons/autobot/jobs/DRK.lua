local common = require('job_helpers.common')

return common.create_ability_job({
    job = 'DRK',
    cooldown = 3,
    abilities = {
        { key='Blood_Weapon', name='Blood Weapon', timer=0, level=1 },
        { key='Arcane_Circle', name='Arcane Circle', timer=86, level=5 },
        { key='Last_Resort', name='Last Resort', timer=87, buff=64, level=15 },
        { key='Weapon_Bash', name='Weapon Bash', timer=88, level=20, target='<t>' },
        { key='Souleater', name='Souleater', timer=85, buff=63, level=30 },
        { key='Dark_Seal', name='Dark Seal', timer=89, level=75 },
        { key='Diabolic_Eye', name='Diabolic Eye', timer=90, level=75 },
        { key='Nether_Void', name='Nether Void', timer=91, level=78 },
        { key='Scarlet_Delirium', name='Scarlet Delirium', timer=245, level=95 },
        { key='Soul_Enslavement', name='Soul Enslavement', timer=254, level=96 },
    },
})
