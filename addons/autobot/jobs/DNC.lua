local common = require('job_helpers.common')

return common.create_ability_job({
    job = 'DNC',
    cooldown = 3,
    abilities = {
        { key='Trance', name='Trance', timer=0, level=1 },
        { key='Sambas', name='Drain Samba', timer=216, level=5 },
        { key='Spectral_Jig', name='Spectral Jig', timer=217, level=25, engaged=false },
        { key='Reverse_Flourish', name='Reverse Flourish', timer=218, level=40 },
        { key='Violent_Flourish', name='Violent Flourish', timer=219, level=45, target='<t>' },
        { key='Animated_Flourish', name='Animated Flourish', timer=220, level=20, target='<t>' },
        { key='Building_Flourish', name='Building Flourish', timer=221, level=50 },
        { key='No_Foot_Rise', name='No Foot Rise', timer=222, level=75 },
        { key='Saber_Dance', name='Saber Dance', timer=223, buff=410, blocks_buffs={411}, level=75 },
        { key='Fan_Dance', name='Fan Dance', timer=224, buff=411, blocks_buffs={410}, level=75 },
        { key='Presto', name='Presto', timer=236, level=77 },
        { key='Grand_Pas', name='Grand Pas', timer=254, level=96 },
    },
})
