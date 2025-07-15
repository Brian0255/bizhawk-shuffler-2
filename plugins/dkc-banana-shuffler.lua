local plugin = {}

plugin.name = "DKC Banana Shuffler"
plugin.author = "OnlySpaghettiCode,TheSoundDefense"
plugin.minversion = "2.8"
plugin.settings =
{
    { name = 'banana_threshold',       type = 'number', label = 'Banana Amount', default = 10 },
    { name = 'minigame_stars_enabled', type = 'boolean', label = 'Minigame Stars Trigger Shuffling', default = false },
    { name='minigame_star_threshold', type = 'number', label='Minigame Star Amount', default=20 },
    { name = 'green_bananas_enabled', type = 'boolean', label = 'Green Bananas Trigger Shuffling (DKC3)', default = false },
    { name = 'green_banana_threshold', type = 'number',  label = 'Green Banana Amount', default = 3 },
    { name = 'disable_auto_shuffle', type = 'boolean', label = "Disable Automatic Shuffling", default = true},
    { name = "infinite_lives", type = 'boolean', label = "Infinite Lives", default = true },
    { name = "infinite_coins", type = 'boolean', label = "Infinite Coins", default = true },
    { name = "world_shuffler", type = 'boolean', label = "World Shuffler", default = false },
}

plugin.description =
[[
	Shuffles the Donkey Kong Country SNES games when you collect a configurable amount of bananas. Only US ROMs are supported (you probably have a US ROM.)

    You can also include the minigame stars from 2/3, as well as the green bananas from 3.

    "Infinite Lives" will make it so your lives are always at 5, preventing game overs.

    "Infinite Coins" will give you infinite Banana Coins in 2, and infinite Bear Coins in 3.

    "World Shuffler" splits each game into one game for each world.
    Since DKC3 has an additional world, as well as more bananas, this is very useful if you want to balance things out more. It's very chaotic though! (in a fun way).
    NOTE: This setting requires Bizhawk 2.10!
]]

local bit = bit
if compare_version("2.9") >= 0 then
	local success, migration_helpers = pcall(require, "migration_helpers")
	bit = success and migration_helpers.EmuHawk_pre_2_9_bit and migration_helpers.EmuHawk_pre_2_9_bit() or bit
end

local loaded_game
local tag
local game
local game_data
local collectibles = {
    bananas = {running_total = 0, threshold = -1, enabled = true, reverse_count = false, frame_delay = 0},
    minigame_stars = {running_total = 0, threshold = -1, enabled = false, reverse_count = true, frame_delay = 0},
    green_bananas = {running_total = 0, threshold = -1, enabled = false, reverse_count = true, frame_delay = 0},
}

local rom_collectible_queues = {}

local dkc1_banana_bitflags = {
    --World 1
    [0x16] = { name = "jungle hijinx", flag_end = 0xD092, bonuses = { [0x08] = 0xD086 } },
    [0xC] = { name = "ropey rampage", flag_end = 0xD11C, bonuses = { [0x6F] = 0xD016 } },
    [0xEA] = { name = "reptile rumble", flag_end = 0xD0BE, bonuses = { [0x09] = 0xD032, [0xC9] = 0xD08E, [0x0B] = 0xD056 } },
    [0xBF] = {name = "coral capers", flag_end = 0xD104 , bonuses = {}},
    [0x17] = { name = "barrel cannon canyon", flag_end = 0xD4D0, bonuses = { [0x76] = 0xD00E, [0x77] = 0xD010 } },

    --World 2
    [0xD9] = { name = "winky's walkway", flag_end = 0xD07C, bonuses = { [0x51] = 0xD02A } },
    [0x2E] = { name = "minecart carnage", flag_end = 0xD156, bonuses = {} },
    [0x7] = { name = "bouncy bonanza", flag_end = 0xD10A, bonuses = { [0x79] = 0xD056 } },
    [0x31] = { name = "stop & go station", flag_end = 0xD084, bonuses = { [0x82] = 0xD076, [0x83] = 0xD010 } },
    [0x42] = {name = "millstone mayhem", flag_end = 0xD0D4 , bonuses = {[0xAE] = 0xD010}},

    --World 3
    [0xA5] = { name = "vulture culture", flag_end = 0xD0C2, bonuses = { [0xBC] = 0xD008 } },
    [0xA4] = { name = "treetop town", flag_end = 0xD0B0, bonuses = { [0xB6] = 0xD07C } },
    [0xD0] = { name = "forest frenzy", flag_end = 0xD122, bonuses = { [0xDB] = 0xD0FA } },
    [0x43] = { name = "temple tempest", flag_end = 0xD122, bonuses = {} },
    [0xD] = { name = "orang-utan gang", flag_end = 0xD126, bonuses = { [0x75] = 0xD066 } },
    [0xDE] = { name = "clam city", flag_end = 0xD126, bonuses = {} },

    --World 4
    [0x24] = { name = "snow barrel blast", flag_end = 0xD378, bonuses = { [0x95] = 0xD07C, [0x96] = 0xD016 } },
    [0x6D] = { name = "slipslide ride", flag_end = 0xD090, bonuses = { [0xCB] = 0xD01E } },
    [0xA7] = { name = "ice age alley", flag_end = 0xD0D8, bonuses = { [0xAC] = 0xD09E } },
    [0x3E] = { name = "croctopus chase", flag_end = 0xD09E, bonuses = {} },
    [0x14] = { name = "torchlight trouble", flag_end = 0xD062, bonuses = {} },
    [0xCE] = { name = "rope bridge rumble", flag_end = 0xD0C4, bonuses = { [0xD8] = 0xD044 } },

    --World 5
    [0x40] = { name = "oil drum alley", flag_end = 0xD0AA, bonuses = { [0x8F] = 0xD07C, [0x91] = 0xD016 } },
    [0x2F] = { name = "trick track trek", flag_end = 0xD09E, bonuses = { [0x88] = 0xD0BA } },
    [0x18] = { name = "elevator antics", flag_end = 0xD08C, bonuses = { [0x7E] = 0xD00E, [0x7F] = 0xD07C } },
    [0x22] = { name = "poison pond", flag_end = 0xD0C6, bonuses = {} },
    [0x27] = { name = "minecart madness", flag_end = 0xD11C, bonuses = { [0x8C] = 0xD00E, [0x8E] = 0xD032 } },
    [0x41] = { name = "blackout basement", flag_end = 0xD0B4, bonuses = { [0x92] = 0xD09E } },

    --World 6
    [0x30] = { name = "tanked up trouble", flag_end = 0xD0BA, bonuses =  {} },
    [0x12] = { name = "manic mincers", flag_end = 0xD054, bonuses = { [0x7B] = 0xD002 } },
    [0xA] = { name = "misty mine", flag_end = 0xD100, bonuses = { [0x80] = 0xD19A } },
    [0x36] = { name = "loopy lights", flag_end = 0xD0A8, bonuses = { [0x84] = 0xD00E, [0x85] = 0xD02A } },
    [0x2B] = {name = "platform perils", flag_end = 0xD0C8 , bonuses = {}},
}

local Memory = {
    read_u8 = function(addr) return memory.read_u8(addr, "WRAM") end,
    read_u16_le = function(addr) return memory.read_u16_le(addr, "WRAM") end,
    read_u32_le = function(addr) return memory.read_u32_le(addr, "WRAM") end,

    write_u8 = function(addr, val) return memory.write_u8(addr, val, "WRAM") end,
    write_u16_le = function(addr, val) return memory.write_u16_le(addr,val,"WRAM") end,
    write_u32_le = function(addr, val) return memory.write_u32_le(addr, val, "WRAM") end
}

local memory_size_to_read_function = {
    [1] = Memory.read_u8,
    [2] = Memory.read_u16_le,
    [4] = Memory.read_u32_le
}

local function get_variable(key)
    local cur_val = game_data.cur_data[key]
    local prev_val = game_data.prev_data[key]
    local changed = (cur_val ~= prev_val) and (prev_val ~= nil)
    return changed, cur_val, prev_val
end

local function update_variable(key)
    local read_func = game_data.var_data[key]
    if read_func == nil then return end
    local cur_val = game_data.cur_data[key]
    local prev_val = game_data.prev_data[key]
    local new_val = read_func()
    game_data.prev_data[key] = cur_val
    game_data.cur_data[key] = new_val
    return get_variable(key)
end

local function reset_variable(key)
    game_data.prev_data[key] = nil
    game_data.cur_data[key] = nil
end

local function count_set_bits(x)
    local count = 0
    while x ~= 0 do
        x = bit.band(x, (x - 1))
        count = count + 1
    end
    return count
end

local function count_cleared_bits(current, old)
    local cleared = bit.band(old,bit.bnot(current))
    return count_set_bits(cleared)
end

local function BCD_to_decimal(BCD)
    --bananas are stored as a Binary Coded Decimal. i.e. if you have 16 bananas it is stored as 0x16
    --hacky, but simplest way is to format this as hex and then call tonumber()
    return tonumber(string.format("%X",BCD))
end

local function BCD_counter_read(addr, size)
    size = size or 2
    local BCD_banana_count
    if size == 2 then
        BCD_banana_count = Memory.read_u16_le(addr)
    elseif size == 1 then
        BCD_banana_count = Memory.read_u8(addr)
    end
    return BCD_to_decimal(BCD_banana_count)
end

local function read_object_table(base, total, entry_size)
    local data = {}
    local func = memory_size_to_read_function[entry_size]
    for address = base, (base + total * entry_size), entry_size do
        table.insert(data, func(address))
    end
    return data
end

local function queue_collectible_update(collectible_key, change, frames_to_wait)
    frames_to_wait = frames_to_wait or 0
    local entry = {["collectible_key"] = collectible_key, ["change"] = change, frame_counter = frames_to_wait}
    table.insert(rom_collectible_queues[loaded_game], entry)
end

local function dkc1_read_boss_HP()
    local _, stage = get_variable("stage")
    local stage_to_HP_address = {
        [0xE0] = 0x1503,
        [0xE1] = 0x1501,
        [0xE2] = 0x1503,
        [0xE5] = 0x1175,
        [0xE4] = 0x1501
    }
    if not stage_to_HP_address[stage] then return end
    return Memory.read_u16_le(stage_to_HP_address[stage])
end

local function dkc1_read_banana_flag_offsets()
    local offsets = {}
    local substage = Memory.read_u8(0x565)
    local _, stage = get_variable("stage")
    local data = dkc1_banana_bitflags[stage]
    if not data then return {} end
    --0x16 or 0x00 = main stage
    if substage ~= 0x16 and substage ~= 00 and not data.bonuses[substage] then return {} end
    local flag_end = data.bonuses[substage] or data.flag_end
    for offset = 0xD000, flag_end, 2 do
        local value = Memory.read_u16_le(offset)
        if value > 0 then
            table.insert(offsets, offset)
        end
    end
    return offsets
end

local function dkc1_read_banana_flags()
    local flags = {}
    local _, offsets = get_variable("banana_flag_offsets")
    if offsets == nil then return end
    for _, offset in pairs(offsets) do
        table.insert(flags, Memory.read_u16_le(offset))
    end
    return flags
end

local function dkc1_is_level_loaded()
    local fade_timer = Memory.read_u8(0x51A)
    local fade_direction = Memory.read_u8(0x51B)
    return (fade_timer > 1 and fade_timer <= 0xF and fade_direction <= 3) and game_data.in_stage()
end

local function dkc1_check_banana_flags()
    local changed_level, level_loaded, prev_loaded = get_variable("is_level_loaded")
    local changed_stage = get_variable("stage")
    local new_level = level_loaded and (changed_level or prev_loaded == nil or changed_stage)
    if new_level then
        reset_variable("banana_flags")
        update_variable("banana_flag_offsets")
    end
    local _, banana_flags, prev_flags = update_variable("banana_flags")
    if not prev_flags then return 0 end
    local new_bananas = 0
    for index, value in pairs(banana_flags) do
        --if this case happens, something went wrong
        if not prev_flags[index] then return 0 end
        new_bananas = new_bananas + count_cleared_bits(value, prev_flags[index])
    end
    return new_bananas
end


local function dkc1_check_for_the_single_banana_in_that_one_bonus_game()
    local changed, spawned_sprites, prev_sprites = update_variable("spawned_sprites")
    if not changed then return 0 end
    local substages = { [0x78] = true, [0xC2] = true }
    local substage = Memory.read_u8(0x565)
    if substages[substage] and spawned_sprites[1] == 0x42 and prev_sprites[1] == 0x00 then
        return 1
    end
    return 0
end

--god i wish there was an internal counter separate from the HUD
local function dkc1_read_new_bananas()
    local _, level_loaded = update_variable("is_level_loaded")
    if not level_loaded then return 0 end
    local _, object_ids, prev_ids = update_variable("object_ids")
    local _, object_timers = update_variable("object_timers")
    local _, object_states, prev_states = update_variable("object_states")
    local new_bananas = dkc1_check_banana_flags()
    local bunch_id = 0x15
    for index, id in pairs(object_ids) do
        if (id == bunch_id) or (id == 0 and prev_ids and prev_ids[index] == bunch_id) then
            if object_states[index] == 0x02 and prev_states and prev_states[index] ~= 0x02 then
                new_bananas = new_bananas + object_timers[index] + 1
            end
        end
    end
    new_bananas = new_bananas + dkc1_check_for_the_single_banana_in_that_one_bonus_game()
    if new_bananas > 0 then queue_collectible_update("bananas",new_bananas, 3) end
end

local function dkc2_in_stage()
    local map_or_stage = Memory.read_u8(0x1FF)
    return map_or_stage == 0x80
end

local function dkc2_in_bonus()
    return Memory.read_u8(0x515) > 0
end

local function dkc2_in_star_bonus()
    if not dkc2_in_bonus() then return end
    return Memory.read_u8(0x52D) == 0x02
end

local function dkc2_read_stars()
    if not dkc2_in_star_bonus() then return end
    return BCD_counter_read(0x8BC)
end

local function dkc2_read_bananas()
    if dkc2_in_star_bonus() then return end
    return BCD_counter_read(0x8BC)
end

local function dkc3_in_stage()
    local map_or_stage = Memory.read_u16_le(0x18F5)
    return map_or_stage > 0
end

local function dkc3_in_non_banana_bonus()
    local bonus_type = Memory.read_u8(0x75E)
    return bonus_type == 0x03 or bonus_type == 0x04
end

--minigame bonus type can be set in dkc3 before the banana counter is updated correctly
--i.e. if you go into a green banana game and have 30 bananas, code would think you picked up 15. this check prevents that
--there is also a scenario where you go in with less than the goal amount, but that just gets ignored by other code for being negative
local function dkc3_minigame_total_in_bound(total)
    local goal_amount = BCD_counter_read(0x75F,1)
    return total <= goal_amount
end

local function dkc3_read_bananas()
    if dkc3_in_non_banana_bonus() then return end
    return BCD_counter_read(0x5D3)
end

local function dkc3_read_stars()
    if Memory.read_u8(0x75E) ~= 0x03 then return end
    local total = BCD_counter_read(0x5D3)
    if dkc3_minigame_total_in_bound(total) then
        return total
    end
end

local function dkc3_read_green_bananas()
    if Memory.read_u8(0x75E) ~= 0x04 then return end
    local total = BCD_counter_read(0x5D3)
    if dkc3_minigame_total_in_bound(total) then
        return total
    end
end

local function dkc2_3_infinite_lives(lives_counter_addr)
    local changed = update_variable("lives_hud")
    if changed then
        Memory.write_u8(game_data.lives_hud_addr, 5)
        Memory.write_u8(lives_counter_addr, 5)
    end
end

local function dkc1_infinite_lives()
    Memory.write_u8(0x575,5)
    Memory.write_u8(0x577,5)
end

local all_game_data = {
    dkc1 = {
        var_data = {
            boss_HP = dkc1_read_boss_HP,
            stage = function() return Memory.read_u8(0x563) end,
            substage = function() return Memory.read_u8(0x565) end,
            is_level_loaded = dkc1_is_level_loaded,
            banana_flag_offsets = dkc1_read_banana_flag_offsets,
            banana_flags = dkc1_read_banana_flags,
            gnawty_value = function() return Memory.read_u16_le(0x1271) end,
            drum_minion_1_state = function() return Memory.read_u16_le(0x1035) end,
            drum_minion_2_state = function() return Memory.read_u16_le(0x1037) end,
            krool_value = function() return Memory.read_u16_le(0x1539) end,
            object_ids = function() return read_object_table(0xD45, 15, 2) end,
            object_timers = function() return read_object_table(0x1375, 15, 2) end,
            object_states = function() return read_object_table(0x1029, 15, 2) end,
            object_graphics = function() return read_object_table(0xD11, 15, 2) end,
            spawned_sprites = function() return read_object_table(0xD79, 32, 2) end,
        },
        cur_data = {},
        prev_data = {},
        stages = {
            gnawty = 0xE0,
            necky = 0xE1,
            queen_b = 0xE5,
            drum = 0xE3,
            very_gnawty = 0xE2,
            necky_snr = 0xE4,
            k_rool = 0x68
        },
        in_stage = function() return Memory.read_u8(0x527) == 0 end,
        infinite_lives = dkc1_infinite_lives,
        infinite_coins = function() end,
        collectible_updating_func = dkc1_read_new_bananas
    },
    dkc2 = {
        var_data = {
            stage = function() return Memory.read_u8(0x8A8) end,
            bananas = dkc2_read_bananas,
            lives_hud = function() return Memory.read_u8(0x8C0) end,
            minigame_stars = dkc2_read_stars,
            boss_HP = function() return Memory.read_u16_le(0x652) end,
            kudgel_value = function() return Memory.read_u8(0xF2B) end,
            krool_value = function() return Memory.read_u8(0xB74) end
        },
        cur_data = {},
        prev_data = {},
        stages = {
            krow = 0x9,
            kiln = 0x21,
            kudgel = 0x63,
            zing = 0x60,
            kreepy_krow = 0xD,
            krool = 0x61
        },
        infinite_coins = function() Memory.write_u8(0x8CA, 99) end,
        infinite_lives = function() return dkc2_3_infinite_lives(0x8BE) end,
        lives_hud_addr = 0x8C0,
        in_stage = dkc2_in_stage
    },
     dkc3 = {
        var_data = {
            stage = function() return Memory.read_u8(0x5B9) end,
            bananas = dkc3_read_bananas,
            lives_hud = function() return Memory.read_u8(0x18D1) end,
            minigame_stars = dkc3_read_stars,
            green_bananas = dkc3_read_green_bananas,
            generic_boss_state = function() return Memory.read_u8(0x98C) end,
            squirt_left_eye = function() return Memory.read_u8(0xA8C) end,
            squirt_right_eye = function() return Memory.read_u8(0xAFA) end,
            bleak_value = function() return Memory.read_u8(0x8B0) end,
            --barbos guard counter = 0x1B9B
            krool_value = function() return Memory.read_u8(0x9FA) end,
            boss_HP = function() return Memory.read_u16_le(0x1B75) end,
        },
        cur_data = {},
        prev_data = {},
        stages = {
            belcha = 0x1D,
            arich = 0x1E,
            squirt = 0x1F,
            kaos = 0x20,
            bleak = 0x21,
            barbos = 0x22,
            krool = 0x23,
            krool_2 = 0x24
        },
        in_stage = dkc3_in_stage,
        infinite_coins = function() Memory.write_u8(0x5C9, 99) end,
        infinite_lives = function() return dkc2_3_infinite_lives(0x5D5) end,
        lives_hud_addr = 0x18D1,
        disabled_collectibles = {}
    }
}

local function generic_boss_HP_check()
    local _, boss_HP, prev_HP = update_variable("boss_HP")
    return (prev_HP ~= nil and boss_HP > 0 and (prev_HP - boss_HP == 1))
end

local function generic_boss_value_check(variable_key, expected_value)
    local changed, state = update_variable(variable_key)
    return (changed and state == expected_value)
end

local function generic_boss_value_HP_check(variable_key, expected_value)
    local _, boss_HP = update_variable("boss_HP")
    return (boss_HP > 1 and generic_boss_value_check(variable_key, expected_value))
end

local function dkc1_drum_hit_check()
    local minion_1_changed, minion_1_state = update_variable("drum_minion_1_state")
    local minion_2_changed, minion_2_state = update_variable("drum_minion_2_state")
    local current_wave = Memory.read_u8(0x1503)
    local minion_1_dead = (minion_1_state == 0x01)
    local minion_2_dead = (minion_2_state == 0x01)
    local minion_1_just_killed = (minion_1_dead and minion_1_changed)
    local minion_2_just_killed = (minion_2_dead and minion_2_changed)
    local boss_is_over = (minion_1_dead and minion_2_dead and current_wave == 5)
    if boss_is_over then return end
    return (minion_1_just_killed or minion_2_just_killed)
end

local function dkc1_krool_hit_check()
    local changed, state = update_variable("krool_value")
    return (changed and (state == 0x12 or state == 0x05))
end

local function dkc2_krool_hit_check()
    local cannon_fire_states = {[0x6] = true, [0xD] = true,[0x14] = true,[0x1B] = true, [0x22] = true, [0x29] = true, [0x30] = true, [0x37] = true}
    local changed, krool_value, prev = update_variable("krool_value")
    --idk why this works but it does across versions
    return (changed and cannon_fire_states[krool_value] and krool_value - prev == 4)
end

local function dkc3_kaos_hit_check()
    local _, boss_HP = update_variable("boss_HP")
    local changed, boss_value = update_variable("generic_boss_state")
    return  (boss_HP > 1 and changed and (boss_value == 0x05 or boss_value == 0x07))
end

local function dkc3_squirt_hit_check()
    local changed_left, left_eye, prev_left_eye = update_variable("squirt_left_eye")
    local changed_right, right_eye, prev_right_eye = update_variable("squirt_right_eye")
    local _, boss_HP = update_variable("boss_HP")
    local left_eye_hit = changed_left and ((left_eye - prev_left_eye) == 1)
    local right_eye_hit = changed_right and ((right_eye - prev_right_eye) == 1)
    local boss_over = (boss_HP == 1 and left_eye == 2 and right_eye == 2)
    if boss_over then return end
    return (left_eye_hit or right_eye_hit)
end

--this gets pretty janky because kaos 2/k. rool are both in the same arena
local function dkc3_krool_hit_check()
    local _, boss_HP = update_variable("boss_HP")
    local kaos_changed, kaos_state = update_variable("generic_boss_state")
    local krool_changed, krool_value = update_variable("krool_value")
    local kaos_hit_state = (kaos_state == 0x7 or (kaos_state == 0x14 and krool_value == 0x4))
    local kaos_hit = kaos_hit_state and kaos_changed
    --exit early here to potentially avoid some weird overlap
    if kaos_hit then return true end
    local krool_hit_state = (krool_value == 0x9 or krool_value == 0x13 or krool_value == 0x1C)
    local krool_hit = boss_HP > 1 and krool_changed and krool_hit_state
    return krool_hit
end

local stage_to_boss_function = {
    ["dkc1"] = {
        [all_game_data.dkc1.stages.gnawty] = function() return generic_boss_value_HP_check("gnawty_value", 0x00) end,
        [all_game_data.dkc1.stages.necky] = generic_boss_HP_check,
        [all_game_data.dkc1.stages.queen_b] = generic_boss_HP_check,
        [all_game_data.dkc1.stages.very_gnawty] = function() return generic_boss_value_HP_check("gnawty_value", 0x00) end,
        [all_game_data.dkc1.stages.drum] = dkc1_drum_hit_check,
        [all_game_data.dkc1.stages.necky_snr] = generic_boss_HP_check,
        [all_game_data.dkc1.stages.k_rool] = dkc1_krool_hit_check
    },
    ["dkc2"] = {
        [all_game_data.dkc2.stages.krow] = generic_boss_HP_check,
        [all_game_data.dkc2.stages.kiln] = generic_boss_HP_check,
        [all_game_data.dkc2.stages.kudgel] = function() return generic_boss_value_HP_check("kudgel_value",0x02) end,
        [all_game_data.dkc2.stages.zing] = generic_boss_HP_check,
        [all_game_data.dkc2.stages.kreepy_krow] = generic_boss_HP_check,
        [all_game_data.dkc2.stages.krool] = dkc2_krool_hit_check
    },

    ["dkc3"] = {
        [all_game_data.dkc3.stages.belcha] = function() return generic_boss_value_check("generic_boss_state",0x6) end,
        [all_game_data.dkc3.stages.arich] = function() return generic_boss_value_HP_check("generic_boss_state",0x4) end,
        [all_game_data.dkc3.stages.kaos] = dkc3_kaos_hit_check,
        [all_game_data.dkc3.stages.squirt] = dkc3_squirt_hit_check,
        [all_game_data.dkc3.stages.bleak] = function() return generic_boss_value_HP_check("bleak_value",0x8) end,
        [all_game_data.dkc3.stages.barbos] = function() return generic_boss_value_HP_check("generic_boss_state",0x4) end,
        [all_game_data.dkc3.stages.krool] = dkc3_krool_hit_check,
        [all_game_data.dkc3.stages.krool_2] = generic_boss_HP_check
    }
}

local function check_boss_hit()
    if not game_data.in_stage() then return end
    local _, stage = get_variable("stage")
    if not stage_to_boss_function[game][stage] then return end
    if stage_to_boss_function[game][stage]() then print("hit boss") swap_game_delay(3) end
end

local function update_collectible_amount(collectible_key, change)
    if change < 0 or change > 50 then return end
    local collectible = collectibles[collectible_key]
    collectible.running_total = collectible.running_total + change
    if collectible.running_total >= collectible.threshold then
        swap_game_delay(0)
    end
end

local function update_collectible_queue()
    for index, entry in pairs(rom_collectible_queues[loaded_game]) do
        entry.frame_counter = entry.frame_counter - 1
        if entry.frame_counter == 0 then
            update_collectible_amount(entry.collectible_key, entry.change)
            rom_collectible_queues[loaded_game][index] = nil
        end
    end
end

local function standard_update_collectibles()
    if not game_data.in_stage() then return end
    for collectible_key, data in pairs(collectibles) do
        if data.enabled then
            local changed, amount, prev_amount = update_variable(collectible_key)
            if changed and amount then
                local diff = amount - prev_amount
                if data.reverse_count then
                    diff = prev_amount - amount
                end
                queue_collectible_update(collectible_key, diff, 4)
            end
        end
    end
end

function plugin.on_frame(data, settings)
    update_variable("stage")
    if settings.infinite_lives then game_data.infinite_lives() end
    if settings.infinite_coins then game_data.infinite_coins() end
    update_collectible_queue(settings)
    if tag == nil then return end
    local collectible_update_function = game_data.collectible_updating_func or standard_update_collectibles
    collectible_update_function()
    check_boss_hit()
end

function plugin.on_setup(data, settings)
    if settings.disable_auto_shuffle then
        config.auto_shuffle = false
    end
    collectibles.bananas.threshold = settings.banana_threshold
    collectibles.minigame_stars.threshold = settings.minigame_star_threshold
    collectibles.green_bananas.threshold = settings.green_banana_threshold
    collectibles.minigame_stars.enabled = settings.minigame_stars_enabled
    collectibles.green_bananas.enabled = settings.green_bananas_enabled
end

local function reset_data()
    game_data.prev_data = {}
    game_data.cur_data = {}
    for _, data in pairs(collectibles) do
        data.frame_delay = 0
        data.running_total = 0
    end
end

function string.tohex(str)
    return (str:gsub('.', function (c)
        return string.format('%02X', string.byte(c))
    end))
end

--this is a bit hacky but the only fast way I can think of for identifying the ROMs before a session starts without client.openrom() or calling some slow pure lua SHA-1/CRC32/etc. code
local function get_tag_from_rom(rom_name)
    local rom_names = {
        ["444F4E4B4559204B4F4E4720434F554E5452592020"] = "dkc1",
        ["44494444592753204B4F4E47205155455354202020"] = "dkc2",
        ["444F4E4B4559204B4F4E4720434F554E5452592033"] = "dkc3"
    }
    local checksums = {
        ["dkc1"] = {
            ["7F1080EF"] = "dkc1",
            ["832E7CD1"] = "dkc1_rev1",
            ["33D4CC2B"] = "dkc1_rev2"
        },
        ["dkc2"] = {
            ["FDED0212"] = "dkc2",
            ["9F676098"] = "dkc2_rev1"
        },
        ["dkc3"] = {
            ["734D8CB2"] = "dkc3"
        }
    }
    local file = io.open(GAMES_FOLDER .. '/' .. rom_name, "rb")
    if not file then return end
    local data = file:read("*all")
    local copier_offset = (#data % 1024 == 512) and 512 or 0
    local header_start = 0xFFC0 + copier_offset + 1
    local internal_name = data:sub(header_start, header_start + 20):tohex()
    local game_name = rom_names[internal_name]
    local checksum = data:sub(header_start + 0x1C, header_start + 0x1C + 3):tohex()
    if game_name == nil or checksums[game_name][checksum] == nil then return end
    return checksums[game_name][checksum]
end

function plugin.on_games_list_load(data, settings)
    if not settings.world_shuffler then return end
    local world_counts = {
        ["dkc1"] = 6,
        ["dkc2"] = 6,
        ["dkc3"] = 7
    }
    local to_remove = {}
    local to_add = {}
    for game_key, info in pairs(config.active_games) do
        local game_tag = get_tag_from_rom(info.rom_name)
        if game_tag ~= nil then
            local game_name = game_tag:match("([^_]+)")
            local total_worlds = world_counts[game_name]
            for i = 1, total_worlds, 1 do
                local new_name = string.format("%s_world_%s", game_name, i)
                local savestate_path = PLUGINS_FOLDER .. '/dkc-banana-shuffler-states/'..game_tag..'/world'..i..'.state'
                to_add[new_name] = {rom_name = info.rom_name, initial_savestate = savestate_path}
            end
        end
        to_remove[game_key] = true
    end
    for old_key, _ in pairs(to_remove) do
        config.active_games[old_key] = nil
    end
    for new_game, new_data in pairs(to_add) do
        add_game(new_game, new_data.rom_name, new_data.initial_savestate)
    end
end

function plugin.on_game_load(data, settings)
    loaded_game = config.current_game
    if not rom_collectible_queues[loaded_game] then
        rom_collectible_queues[loaded_game] = {}
    end
    tag = get_tag_from_hash_db(gameinfo.getromhash(), 'plugins/dkc-hashes.dat') or nil
    if tag == nil then
        error("DKC hash not found in database.")
        print(config.active_games[config.current_game].rom_name)
        print(gameinfo.getromhash())
        return
    end
    game = tag:match("([^_]+)")
    game_data = all_game_data[game]
    reset_data()
end

return plugin
