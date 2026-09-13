local mage = require('job_helpers.mage_common')

local protectra = {
    protectra1 = 'Protectra',
    protectra2 = 'Protectra II',
    protectra3 = 'Protectra III',
    protectra4 = 'Protectra IV',
    protectra5 = 'Protectra V',
}

local shellra = {
    shellra1 = 'Shellra',
    shellra2 = 'Shellra II',
    shellra3 = 'Shellra III',
    shellra4 = 'Shellra IV',
    shellra5 = 'Shellra V',
}

return mage.create({
    job = 'WHM',
    cast_delay = 2.0,
    order = {
        'cure', 'cure2', 'cure3', 'cure4', 'cure5', 'cure6',
        'poisona', 'paralyna', 'silena', 'blindna', 'viruna', 'stona', 'cursna', 'erase',
        'haste', 'protectra', 'shellra', 'auspice', 'regen', 'regen2', 'regen3', 'regen4', 'regen5',
    },
    cure_order = { 'cure6', 'cure5', 'cure4', 'cure3', 'cure2', 'cure' },
    spells = {
        cure = { name = 'Cure', type = 'cure', missing = 150 },
        cure2 = { name = 'Cure II', type = 'cure', missing = 350 },
        cure3 = { name = 'Cure III', type = 'cure', missing = 650 },
        cure4 = { name = 'Cure IV', type = 'cure', missing = 1100 },
        cure5 = { name = 'Cure V', type = 'cure', missing = 1600 },
        cure6 = { name = 'Cure VI', type = 'cure', missing = 2200 },
        poisona = { name = 'Poisona', type = 'status' },
        paralyna = { name = 'Paralyna', type = 'status' },
        silena = { name = 'Silena', type = 'status' },
        blindna = { name = 'Blindna', type = 'status' },
        viruna = { name = 'Viruna', type = 'status' },
        stona = { name = 'Stona', type = 'status' },
        cursna = { name = 'Cursna', type = 'status' },
        erase = { name = 'Erase', type = 'status' },
        haste = { name = 'Haste', type = 'buff' },
        protectra = { name = 'Protectra', type = 'buff' },
        shellra = { name = 'Shellra', type = 'buff' },
        auspice = { name = 'Auspice', type = 'buff' },
        regen = { name = 'Regen', type = 'buff' },
        regen2 = { name = 'Regen II', type = 'buff' },
        regen3 = { name = 'Regen III', type = 'buff' },
        regen4 = { name = 'Regen IV', type = 'buff' },
        regen5 = { name = 'Regen V', type = 'buff' },
    },
    debuff_map = {
        [3] = 'poisona', [4] = 'paralyna', [5] = 'blindna', [6] = 'silena',
        [7] = 'stona', [8] = 'viruna', [9] = 'cursna', [15] = 'cursna',
        [21] = 'erase', [22] = 'erase', [23] = 'erase',
    },
    tier_options = {
        { setting = 'protectra_tier', label = 'Protectra Tier', options = { 'protectra1', 'protectra2', 'protectra3', 'protectra4', 'protectra5' } },
        { setting = 'shellra_tier', label = 'Shellra Tier', options = { 'shellra1', 'shellra2', 'shellra3', 'shellra4', 'shellra5' } },
    },
    buffs = {
        { key = 'haste', name = 'Haste', group = 'haste', buff_id = 33, interval = 150 },
        { key = 'protectra', group = 'cures', buff_id = 40, target = 'self', tiers = protectra, tier_setting = 'protectra_tier', interval = 1800 },
        { key = 'shellra', group = 'cures', buff_id = 41, target = 'self', tiers = shellra, tier_setting = 'shellra_tier', interval = 1800 },
        { key = 'auspice', name = 'Auspice', group = 'cures', buff_id = 476, target = 'self', interval = 180 },
        { key = 'regen5', name = 'Regen V', group = 'regen', buff_id = 42, interval = 60 },
        { key = 'regen4', name = 'Regen IV', group = 'regen', buff_id = 42, interval = 60 },
        { key = 'regen3', name = 'Regen III', group = 'regen', buff_id = 42, interval = 60 },
        { key = 'regen2', name = 'Regen II', group = 'regen', buff_id = 42, interval = 60 },
        { key = 'regen', name = 'Regen', group = 'regen', buff_id = 42, interval = 60 },
    },
})
