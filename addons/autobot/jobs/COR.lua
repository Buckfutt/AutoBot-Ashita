local common = require('job_helpers.common')

return common.create_ability_job({
    job = 'COR',
    cooldown = 3,
    auto_ra = true,
    abilities = {
        { key='Wild_Card', name='Wild Card', timer=0, level=1 },
        { key='Double_Up', name='Double-Up', timer=194, level=5 },
        { key='Random_Deal', name='Random Deal', timer=196, level=50 },
        { key='Snake_Eye', name='Snake Eye', timer=197, level=75 },
        { key='Fold', name='Fold', timer=198, level=75 },
        { key='Triple_Shot', name='Triple Shot', timer=84, level=87 },
        { key='Crooked_Cards', name='Crooked Cards', timer=96, level=95 },
        { key='Cutting_Cards', name='Cutting Cards', timer=254, level=96 },
    },
})
