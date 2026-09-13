local common = require('job_helpers.common')

return common.create_ability_job({
    job = 'SCH',
    cooldown = 3,
    abilities = {
        { key='Tabula_Rasa', name='Tabula Rasa', timer=0, level=1 },
        { key='Light_Arts', name='Light Arts', timer=228, buff=358, level=10, engaged=false },
        { key='Dark_Arts', name='Dark Arts', timer=229, buff=359, level=10, engaged=false },
        { key='Addendum_White', name='Addendum: White', timer=230, buff=401, requires_buff=358, level=10, engaged=false },
        { key='Addendum_Black', name='Addendum: Black', timer=231, buff=402, requires_buff=359, level=30, engaged=false },
        { key='Penury', name='Penury', timer=232, requires_any_buff={358,401}, level=10, engaged=false },
        { key='Celerity', name='Celerity', timer=233, requires_any_buff={358,401}, level=25, engaged=false },
        { key='Rapture', name='Rapture', timer=234, requires_any_buff={358,401}, level=55, engaged=false },
        { key='Accession', name='Accession', timer=235, requires_any_buff={358,401}, level=40, engaged=false },
        { key='Parsimony', name='Parsimony', timer=232, requires_any_buff={359,402}, level=10, engaged=false },
        { key='Alacrity', name='Alacrity', timer=233, requires_any_buff={359,402}, level=25, engaged=false },
        { key='Ebullience', name='Ebullience', timer=234, requires_any_buff={359,402}, level=55, engaged=false },
        { key='Manifestation', name='Manifestation', timer=235, requires_any_buff={359,402}, level=40, engaged=false },
        { key='Sublimation', name='Sublimation', timer=234, level=35, engaged=false },
        { key='Enlightenment', name='Enlightenment', timer=0, level=75, engaged=false },
        { key='Libra', name='Libra', timer=237, level=76, target='<t>' },
        { key='Perpetuance', name='Perpetuance', timer=238, requires_any_buff={358,401}, level=87, engaged=false },
        { key='Immanence', name='Immanence', timer=239, requires_any_buff={359,402}, level=87, engaged=false },
    },
})
