local common = require('job_helpers.common')

return common.create_ability_job({
    job = 'RNG',
    cooldown = 3,
    auto_ra = true,
    abilities = {
        { key='Eagle_Eye_Shot', name='Eagle Eye Shot', timer=0, level=1, target='<t>' },
        { key='Scavenge', name='Scavenge', timer=121, level=10, engaged=false },
        { key='Camouflage', name='Camouflage', timer=122, level=20 },
        { key='Sharpshot', name='Sharpshot', timer=123, buff=67, level=1 },
        { key='Barrage', name='Barrage', timer=124, level=30 },
        { key='Shadowbind', name='Shadowbind', timer=125, level=40, target='<t>' },
        { key='Velocity_Shot', name='Velocity Shot', timer=126, buff=365, level=45 },
        { key='Double_Shot', name='Double Shot', timer=127, buff=480, level=79 },
        { key='Decoy_Shot', name='Decoy Shot', timer=128, buff=482, level=95 },
        { key='Overkill', name='Overkill', timer=254, level=96 },
    },
})
