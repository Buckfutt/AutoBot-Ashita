local common = require('job_helpers.common')

return common.create_ability_job({
    job = 'NIN',
    cooldown = 3,
    abilities = {
        { key='Mijin_Gakure', name='Mijin Gakure', timer=0, level=1 },
        { key='Yonin', name='Yonin', timer=152, buff=420, blocks_buffs={421}, level=40 },
        { key='Innin', name='Innin', timer=153, buff=421, blocks_buffs={420}, level=40 },
        { key='Futae', name='Futae', timer=154, level=77 },
        { key='Issekigan', name='Issekigan', timer=155, level=95 },
        { key='Mikage', name='Mikage', timer=254, level=96 },
    },
})
