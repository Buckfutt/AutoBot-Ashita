local common = require('job_helpers.common')

return common.create_ability_job({
    job = 'MNK',
    cooldown = 3,
    abilities = {
        { key='Hundred_Fists', name='Hundred Fists', timer=0, level=1 },
        { key='Boost', name='Boost', timer=15, level=5 },
        { key='Dodge', name='Dodge', timer=13, buff=59, level=15 },
        { key='Focus', name='Focus', timer=12, buff=60, level=25 },
        { key='Chakra', name='Chakra', timer=14, level=35, min_hp_under=60 },
        { key='Counterstance', name='Counterstance', timer=16, buff=61, level=45 },
        { key='Footwork', name='Footwork', timer=110, buff=401, level=65 },
        { key='Formless_Strikes', name='Formless Strikes', timer=17, buff=341, level=75 },
        { key='Mantra', name='Mantra', timer=112, level=75 },
        { key='Perfect_Counter', name='Perfect Counter', timer=113, level=79 },
        { key='Impetus', name='Impetus', timer=111, buff=461, level=88 },
        { key='Inner_Strength', name='Inner Strength', timer=254, level=96 },
    },
})
