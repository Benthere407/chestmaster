--[[
    ChestMaster 2.4 - Ashita v4 / VanaCore addon for Abyssea's Sturdy Pyxis.

    Walk up to your Sturdy Pyxis (or talk to it). ChestMaster reads what it holds straight
    from the server's menu packet and, by your rules, Leaves it to you, Opens it (trades it a
    Forbidden Key) or Destroys it (you get its Cruor).

    From LandSandBoat's scripts/globals/abyssea/sturdypyxis/:
      - A locked pyxis starts event 2003+tier (2004..2066). Its first parameter is
        contentMessage[MESSAGE] + chestType: the contents (npc.lua's table, below) plus
        1 blue / 2 red / 3 gold.
      - Menu option 999 breaks the chest and pays Cruor (tier x 10).
      - A Forbidden Key opens it only when TRADED to it (onPyxisTrade).
      - The unlocked chest (event 2067+) is the item list: always left to you.

    Install: addons/ashita/Chestmaster/chestmaster.lua (+ vcmenu.lua beside it)
    Load:    /addon load chestmaster

    Commands:
        /cm            show / hide the window
        /cm on | off   automation on or off (/cm toggle flips it)
        /cm auto       auto-talk on or off
        /cm widget     show / hide the ON/OFF pill
        /cm last       the last chest seen and what was done
        /cm debug      debug messages in chat

    AFK safety: 10 minutes with no movement, key, mouse click, controller button, command or
    action from you turns automation OFF until you turn it back on. Not configurable.
]]--

addon.name    = 'chestmaster';
addon.author  = 'Benthere';
addon.version = '2.4.0';
addon.desc    = 'Abyssea Sturdy Pyxis: leave, open or destroy each chest by what it holds.';
addon.link    = '';

require('common');
local chat     = require('chat');
local imgui    = require('imgui');
local settings = require('settings');
local vc       = require('vcmenu');

local LEAVE, OPEN, DESTROY, TIMED = 0, 1, 2, 3;
local ACT_NAMES = { [0] = 'Leave', [1] = 'Open', [2] = 'Destroy', [3] = 'Timed' };

local PYXIS_NAME   = 'sturdy pyxis';
local LOCKED_MIN   = 2004;   -- 2003 + tier
local LOCKED_MAX   = 2066;   -- unlocked (item list) events are locked + 64
local OPT_UPDATE   = 111;    -- the update the game sends as the menu opens
local OPT_DESTROY  = 999;    -- break the chest: Cruor
local CLOSE_PARAM2 = 0x4000; -- option 0 with this high half: close the menu the way the game does

local COLORS = { [1] = 'Blue', [2] = 'Red', [3] = 'Gold' };

-- Categories, as shown on the Contents page.
local CATS = {
    { key = 'cruor',    label = 'Cruor',             group = 'cur' },
    { key = 'exp',      label = 'Experience points', group = 'cur' },
    { key = 'time',     label = 'Time extension',    group = 'cur' },
    { key = 'soothing', label = 'Soothing light',    group = 'light' },
    { key = 'pearl',    label = 'Pearlescent light', group = 'light' },
    { key = 'azure',    label = 'Azure light',       group = 'light' },
    { key = 'ruby',     label = 'Ruby light',        group = 'light' },
    { key = 'amber',    label = 'Amber light',       group = 'light' },
    { key = 'golden',   label = 'Golden light',      group = 'light' },
    { key = 'silvery',  label = 'Silvery light',     group = 'light' },
    { key = 'ebon',     label = 'Ebon light',        group = 'light' },
    { key = 'temp',     label = 'Temporary items',   group = 'item' },
    { key = 'item',     label = 'Items',             group = 'item' },
    { key = 'powerful', label = 'Powerful items',    group = 'item' },
    { key = 'keyitem',  label = 'Key items',         group = 'item' },
};
local CAT_BY_KEY = {};
for _, c in ipairs(CATS) do CAT_BY_KEY[c.key] = c; end

-- npc.lua's xi.pyxis.npc.contentMessage, by its value / 0x10000.
local CONTENT = {
    [0x01] = { 'soothing', 'Feeble soothing light' },
    [0x02] = { 'cruor',    'Miniscule cruor' },
    [0x03] = { 'exp',      'Tiny exp' },
    [0x05] = { 'soothing', 'Faint soothing light' },
    [0x06] = { 'cruor',    'Small cruor' },
    [0x07] = { 'exp',      'Little exp' },
    [0x09] = { 'soothing', 'Mild soothing light' },
    [0x0A] = { 'cruor',    'Moderate cruor' },
    [0x0B] = { 'exp',      'Some exp' },
    [0x0D] = { 'soothing', 'Strong soothing light' },
    [0x0E] = { 'cruor',    'Considerable cruor' },
    [0x0F] = { 'exp',      'Considerable exp' },
    [0x11] = { 'soothing', 'Intense soothing light' },
    [0x12] = { 'temp',     'Numerous temporary items' },
    [0x13] = { 'cruor',    'Princely cruor' },
    [0x14] = { 'exp',      'Tremendous exp' },
    [0x15] = { 'time',     'Stone fragment (time extension)' },
    [0x16] = { 'pearl',    'Faint pearlescent light' },
    [0x17] = { 'azure',    'Faint azure light' },
    [0x18] = { 'ruby',     'Faint ruby light' },
    [0x19] = { 'amber',    'Faint amber light' },
    [0x1A] = { 'pearl',    'Mild pearlescent light' },
    [0x1B] = { 'azure',    'Mild azure light' },
    [0x1C] = { 'ruby',     'Mild ruby light' },
    [0x1D] = { 'amber',    'Mild amber light' },
    [0x1E] = { 'pearl',    'Strong pearlescent light' },
    [0x1F] = { 'azure',    'Strong azure light' },
    [0x20] = { 'ruby',     'Strong ruby light' },
    [0x21] = { 'amber',    'Strong amber light' },
    [0x22] = { 'golden',   'Faint golden light' },
    [0x23] = { 'silvery',  'Faint silvery light' },
    [0x24] = { 'ebon',     'Faint ebon light' },
    [0x25] = { 'azure',    'Intense azure light' },
    [0x26] = { 'ruby',     'Intense ruby light' },
    [0x27] = { 'amber',    'Intense amber light' },
    [0x28] = { 'golden',   'Mild golden light' },
    [0x29] = { 'silvery',  'Mild silvery light' },
    [0x2A] = { 'ebon',     'Mild ebon light' },
    [0x2B] = { 'golden',   'Strong golden light' },
    [0x2C] = { 'silvery',  'Strong silvery light' },
    [0x2D] = { 'ebon',     'Strong ebon light' },
    [0x100] = { 'temp',     'Temporary items' },
    [0x200] = { 'item',     'Items' },
    [0x300] = { 'powerful', 'Powerful items' },
    [0x400] = { 'keyitem',  'Key items' },
};

-- code -> category key, description, colour name
local function decode(code)
    local hi, color = math.floor(code / 0x10000), code % 0x10000;
    local c = CONTENT[hi];
    if not c then return nil, ('unknown contents (0x%X)'):fmt(code), COLORS[color] or '?'; end
    return c[1], c[2], COLORS[color] or '?';
end

local defaults = T{
    enabled     = true,
    actions     = T{ cruor = OPEN, exp = DESTROY, time = LEAVE, soothing = DESTROY,
                     pearl = LEAVE, ebon = LEAVE, golden = LEAVE, silvery = LEAVE,
                     azure = DESTROY, ruby = LEAVE, amber = DESTROY,
                     temp = DESTROY, powerful = LEAVE, keyitem = LEAVE, item = LEAVE },
    no_key      = LEAVE,   -- Open chosen but no Forbidden Key: LEAVE or DESTROY
    timer_minutes = 5,     -- Timed: open one, then destroy that kind until this many minutes pass
    hide_menu   = true,    -- chests you talk to yourself: skip the menu when acting
    ui_scale    = 1.0,
    show_widget = true,    -- the small ON/OFF pill
    widget_theme  = 'classic', -- 'classic' | 'vex' | 'hex' (YunaUI looks, as StopMove's)
    widget_scheme = 'yuna',    -- Vex colours: 'yuna' | 'blue' | 'purple'
    widget_row    = 'card',    -- Vex row: 'card' (StopMove's Menu row) | 'slant' (its Party row)
    widget_gold   = true,      -- Hex link: gold corners
    widget_cut    = 'medium',  -- Hex link: corner cut 'small' | 'medium' | 'large'
    widget_size   = 1.0,       -- Vex / Hex link size
    auto_talk   = true,    -- talk to a nearby pyxis by itself (by its server id)
    auto_range  = 5.0,     -- yalms
    own_only    = true,    -- auto-talk only to chests from monsters your party / alliance claimed
    leave_show  = false,   -- auto mode reaching a Leave chest: false = skip it (close quietly) and carry on; true = show you its menu
    wait_combat = true,    -- auto mode: hold off until the fight is over (you idle, no party-claimed monster alive)
    combat_scope = 'party', -- whose fights count as combat: 'self' | 'party' | 'alliance'
    near_fight  = true,    -- a living monster close to you that is claimed or hurt counts as combat
    combat_radius = 15,    -- ...this close (yalms)
    settle      = 3,       -- seconds after the last kill / fight before chests are handled
    trace       = false,   -- write chestmaster_trace.log in the addon folder (debugging only)
};

local cfg = settings.load(defaults, 'v2');

local state = {
    win   = vc.new_state('rules'),
    debug = false,
    job   = nil,   -- the pyxis being handled now
    last  = nil,   -- { label, desc, color, code, action, note }
    flash = nil,
    sched = {},
    keys  = { id = nil, count = 0, slot = nil, t = 0 },
    done     = {},    -- [server id] = true: this chest has had its turn
    attempts = {},    -- [server id] = auto-talks sent
    tried_at = {},    -- [server id] = os.clock() of the last auto-talk
    reopen   = {},    -- [server id] = true: opened with a key, talk again to show its item list
    timed    = {},    -- [category] = os.clock() it was last opened (Timed rule)
    mobs     = {},    -- [entity index] = { sid, x, y, z, dead }: monsters your party / alliance claimed
    deaths   = {},    -- { x, y, z, t }: where those monsters died lately
    conceal  = {},    -- os.clock() of each "The monster was concealing a treasure chest!" lately
    seen_pyxis = {},  -- [server id] = true: chests already looked at
    owned    = {},    -- [server id] = true: chests that came from your party's / alliance's kills
    owned_n  = 0,
    last_track = 0,
    pending_talk = nil, -- { id, index, t }: we talked to it, waiting for its menu
    menu_open    = nil, -- os.clock() a menu (any npc's) was shown; nil once it closes
    last_scan = 0,
    active_at = os.clock(), -- last time you moved, pressed a key / button, clicked or acted (AFK safety)
    afk_pos   = nil,        -- { x, y, z }: where you were last seen moving
};

-- AFK safety: with no movement or input from you for this long, automation turns itself OFF.
-- Fixed on purpose (no setting): ChestMaster is only for use at the keyboard.
local AFK_MINUTES = 10;
state.win.scale = cfg.ui_scale or 1.0;

settings.register('v2', 'cm_settings_update', function (s)
    if s ~= nil then cfg = s; end
    state.win.scale = cfg.ui_scale or 1.0;
    settings.save('v2');
end);

local function save() settings.save('v2'); end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function log(msg) print(chat.header(addon.name):append(chat.message(msg))); end

-- you did something: the AFK timer starts over
local function mark_active() state.active_at = os.clock(); end
-- seconds until the AFK safety turns automation off
local function afk_left() return AFK_MINUTES * 60 - (os.clock() - (state.active_at or os.clock())); end

local TRACE_DIR = (addon.path and addon.path ~= '') and addon.path or (os.getenv('TEMP') or '.');
if not TRACE_DIR:find('[\\/]$') then TRACE_DIR = TRACE_DIR .. '\\'; end
local TRACE_FILE = TRACE_DIR .. 'chestmaster_trace.log';
local function trace(msg)
    if not cfg.trace then return; end
    local f = io.open(TRACE_FILE, 'a');
    if f then f:write(os.date('%H:%M:%S'), (' %9.2f  '):format(os.clock()), msg, '\n'); f:close(); end
end
local function hexs(d)
    return (tostring(d or ''):gsub('.', function (c) return ('%02X '):format(c:byte()); end));
end
local function dbg(msg)
    if state.debug then log('[debug] ' .. msg); end
    trace(msg);
end

local function later(delay, fn) table.insert(state.sched, { at = os.clock() + delay, fn = fn }); end
local function run_sched()
    if #state.sched == 0 then return; end
    local now, due, keep = os.clock(), {}, {};
    for _, it in ipairs(state.sched) do
        if it.at <= now then due[#due + 1] = it; else keep[#keep + 1] = it; end
    end
    state.sched = keep;
    for _, it in ipairs(due) do
        local ok, err = pcall(it.fn);
        if not ok then log('Error: ' .. tostring(err)); end
    end
end

local function r16(d, o) return struct.unpack('<H', d, o + 1); end
local function r32(d, o) return struct.unpack('<I', d, o + 1); end
local function b16(v) return { v % 256, math.floor(v / 256) % 256 }; end
local function b32(v) return { v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256 }; end
local function append(t, bytes) for _, x in ipairs(bytes) do t[#t + 1] = x; end end

local function esc(s) return (tostring(s):gsub('%%', '%%%%')); end

local function mmss(sec)
    sec = math.max(0, math.floor(sec + 0.5));
    return ('%d:%02d'):fmt(math.floor(sec / 60), sec % 60);
end

-- Timed rule: seconds until `cat` may be opened again (0 = now).
local function timed_left(cat)
    local last = state.timed[cat];
    if not last then return 0; end
    return math.max(0, (cfg.timer_minutes or 5) * 60 - (os.clock() - last));
end

----------------------------------------------------------------------
-- Forbidden Keys
----------------------------------------------------------------------
local function update_keys(force)
    local k, now = state.keys, os.clock();
    if not force and now - k.t < 1.0 then return; end
    k.t = now;
    if not k.id then
        local res = AshitaCore:GetResourceManager():GetItemByName('Forbidden Key', 0);
        if res then k.id = res.Id; end
    end
    k.count, k.slot = 0, nil;
    if not k.id then return; end
    local inv = AshitaCore:GetMemoryManager():GetInventory();
    for i = 1, inv:GetContainerCountMax(0) do
        local it = inv:GetContainerItem(0, i);
        if it and it.Id == k.id and it.Count > 0 then
            k.count = k.count + it.Count;
            k.slot = k.slot or i;
        end
    end
end

----------------------------------------------------------------------
-- Packets (plain byte tables, as campaign sends them under VanaCore)
----------------------------------------------------------------------
local function send_menu(job, option, stay, param2)
    local p = { 0x5B, 0x0A, 0x00, 0x00 };
    append(p, b32(job.id));
    append(p, b16(option));
    append(p, b16(param2 or 0));
    append(p, b16(job.index));
    append(p, b16(stay));
    append(p, b16(job.zone));
    append(p, b16(job.menu));
    AshitaCore:GetPacketManager():AddOutgoingPacket(0x5B, p);
    dbg(('sent 0x5B option=%d param2=%d stay=%d menu=%d'):fmt(option, param2 or 0, stay, job.menu));
end

-- Trade one item (inventory slot) to the npc: 0x36, the same layout the game sends.
local function send_trade(job, slot)
    local p = { 0x36, 0x20, 0x00, 0x00 };
    append(p, b32(job.id));                    -- 0x04 target
    append(p, b32(1));                         -- 0x08 count, trade slot 1
    for _ = 1, 8 do append(p, b32(0)); end     -- 0x0C counts, slots 2..9
    append(p, b32(0));                         -- 0x2C
    p[#p + 1] = slot;                          -- 0x30 inventory index, trade slot 1
    for _ = 1, 9 do p[#p + 1] = 0; end         -- 0x31..0x39
    append(p, b16(job.index));                 -- 0x3A target index
    p[#p + 1] = 1;                             -- 0x3C number of items
    for _ = 1, 3 do p[#p + 1] = 0; end         -- 0x3D..0x3F
    AshitaCore:GetPacketManager():AddOutgoingPacket(0x36, p);
    dbg(('sent 0x36 trade: inventory slot %d -> [%03X]'):fmt(slot, job.index));
end

-- Talk to the npc: 0x1A, category 0 (as campaign does)
local function send_talk(id, index)
    local p = { 0x1A, 0x0E, 0x00, 0x00 };
    append(p, b32(id));
    append(p, b16(index));
    append(p, b16(0));    -- category 0 = talk
    append(p, b16(0));
    append(p, b16(0));
    for _ = 1, 12 do p[#p + 1] = 0; end
    AshitaCore:GetPacketManager():AddOutgoingPacket(0x1A, p);
    dbg(('sent 0x1A talk -> pyxis [%03X] id %d'):fmt(index, id));
end

local function my_status()
    local ok, st = pcall(function ()
        local me = AshitaCore:GetMemoryManager():GetParty():GetMemberTargetIndex(0);
        if me == 0 then return -1; end
        return AshitaCore:GetMemoryManager():GetEntity():GetStatus(me);
    end);
    return ok and st or -1;
end

-- Free the game from waiting on a menu (a 0x52 release, as the server sends).
local function release_now(why)
    dbg('releasing the game: ' .. (why or ''));
    for i, t in ipairs({ 0, 1 }) do
        later(0.15 * i, function ()
            pcall(function ()
                AshitaCore:GetPacketManager():AddIncomingPacket(0x52, { 0x52, 0x04, 0x00, 0x00, t, 0x00, 0x00, 0x00 });
            end);
        end);
    end
end

-- If the game is still showing a menu after we finished it, release it.
local function release_if_stuck()
    later(2.5, function ()
        if state.job ~= nil or my_status() ~= 4 then return; end
        dbg('still in event state - releasing the client');
        pcall(function ()
            AshitaCore:GetPacketManager():AddIncomingPacket(0x52, { 0x52, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 });
        end);
    end);
end

----------------------------------------------------------------------
-- Deciding and acting
----------------------------------------------------------------------
-- Steps for an action (nil: leave it), and the action really taken.
-- A step: { kind, ..., pre = seconds to wait before it }.
local function plan(job, action)
    if action == OPEN then
        update_keys(true);
        if state.keys.slot then
            -- close the menu like the game does, then trade the key a moment later (as the game did)
            return { { 'menu', 0, 0, CLOSE_PARAM2 }, { 'trade', state.keys.slot, pre = 1.0 } }, OPEN;
        end
        if cfg.no_key ~= DESTROY then
            job.note = 'no Forbidden Key - left to you';
            return nil, LEAVE;
        end
        job.note = 'no Forbidden Key - destroyed instead';
        action = DESTROY;
    end
    if action == DESTROY then
        local steps = {};
        -- the game sends the update itself when it shows the menu; send it only when it's hidden
        if not job.shown then steps[#steps + 1] = { 'menu', OPT_UPDATE, 1 }; end
        steps[#steps + 1] = { 'menu', OPT_DESTROY, 0, pre = 0.4 };
        return steps, DESTROY;
    end
    return nil, LEAVE;
end

local function next_step(job)
    job.i = job.i + 1;
    local s = job.steps[job.i];
    if not s then return false; end
    if s[1] == 'menu' then
        send_menu(job, s[2], s[3], s[4]);
        if s[3] == 0 then state.menu_open = nil; end
    else
        send_trade(job, s[2]);
        later(4.0, function () update_keys(true); end);
        if job.group == 'item' then
            -- an item chest opens to an item list: talk to it again so the list pops up for you
            local id = job.id;
            later(2.0, function ()
                state.done[id], state.attempts[id], state.tried_at[id] = nil, 0, -99;
                state.reopen[id] = true;
            end);
        end
    end
    job.waiting, job.t = true, os.clock();
    return true;
end

-- seconds to wait before the next step
local function gap(job)
    local nxt = job.steps and job.steps[job.i + 1];
    return (nxt and nxt.pre) or 0.25;
end

local function finish(job)
    dbg(('finished chest [%03X] after %d step(s)'):fmt(job.index, job.i or 0));
    state.next_talk_at = os.clock() + 1.0;   -- a second before the next chest
    if state.job == job then state.job = nil; end
    if job.shown then release_if_stuck(); end
end

-- Act on `job`. Returns true when it will answer the menu itself.
local function decide(job)
    local cat, desc, color = decode(job.code);
    job.group = cat and CAT_BY_KEY[cat].group or nil;
    local action = cat and (cfg.actions[cat] or LEAVE) or LEAVE;
    local timed = (action == TIMED);
    if timed then
        local left = timed_left(cat);
        if left <= 0 then
            action = OPEN;
            job.note = ('timed: opening one, next in %d min'):fmt(cfg.timer_minutes or 5);
        else
            action = DESTROY;
            job.note = ('timed: next open in %s'):fmt(mmss(left));
        end
    end
    local steps;
    steps, action = plan(job, action);
    if timed and action == OPEN then state.timed[cat] = os.clock(); end   -- start the timer
    state.last = { label = cat and CAT_BY_KEY[cat].label or 'Unknown', desc = desc, color = color,
                   code = job.code, action = action, note = job.note, time = os.time() };
    -- "[3/12]" while auto mode works through a round of chests
    local count = '';
    local b = state.batch;
    if job.auto and b then
        b.n = b.n + 1;
        count = ('[%d/%d] '):fmt(b.n, b.n - 1 + (b.left or 1));
        if action == LEAVE then b.leave = (b.leave or 0) + 1; end   -- skipped: yours to check after
    end
    log(('%s%s chest: %s -> %s%s'):fmt(count, color, desc, ACT_NAMES[action], job.note and (' (' .. job.note .. ')') or ''));
    state.flash = { text = ('%s: %s'):fmt(ACT_NAMES[action], desc), until_t = os.clock() + 5 };
    if not steps then return false; end
    job.steps, job.i = steps, 0;
    if job.shown then
        -- you see the menu: the game sends its own update (111) as it opens. Wait for the server's
        -- answer to that first (or 1.2s), then answer the menu - sent too soon, it was lost.
        job.waiting, job.t, job.ready_at = true, os.clock(), nil;
    else
        job.ready_at = os.clock() + (steps[1].pre or 0.35);
    end
    state.job = job;
    return true;
end

----------------------------------------------------------------------
-- Whose chest is it? A pyxis spawns where the monster died. Monsters your party or
-- alliance claimed are watched; when one dies its spot is kept for a few seconds, and a
-- Sturdy Pyxis that appears there is yours. Everything else (other people's chests,
-- free-spawning ones that may be mimics) is never auto-talked to.
----------------------------------------------------------------------
local MOB_FLAG = 0x10;

local function party_ids()
    local ids, party = {}, AshitaCore:GetMemoryManager():GetParty();
    for i = 0, 17 do
        if party:GetMemberIsActive(i) == 1 then
            local id = party:GetMemberServerId(i);
            if id and id ~= 0 then ids[bit.band(id, 0xFFFF)] = true; end   -- as HXUI: the claim keeps 16 bits
        end
    end
    return ids;
end

-- Whose fights count as combat (Settings > Auto mode: Me / My party / Alliance): their claim ids
-- (16 bits, as above) and entity indexes [index] = slot. Slots 0-5 are your party, 6-17 the alliance.
local SCOPE_LAST = { self = 0, party = 5, alliance = 17 };
local function scope_members()
    local last = SCOPE_LAST[cfg.combat_scope or 'party'] or 5;
    local ids, idxs, party = {}, {}, AshitaCore:GetMemoryManager():GetParty();
    for p = 0, last do
        if party:GetMemberIsActive(p) == 1 then
            local id = party:GetMemberServerId(p);
            if id and id ~= 0 then ids[bit.band(id, 0xFFFF)] = true; end
            local idx = party:GetMemberTargetIndex(p);
            if idx and idx ~= 0 then idxs[idx] = p; end
        end
    end
    return ids, idxs;
end

local function pos_of(ent, i)
    return ent:GetLocalPositionX(i), ent:GetLocalPositionY(i), ent:GetLocalPositionZ(i);
end

local function add_death(m, now, sc_ids)
    if m.dead then return; end
    m.dead = true;
    table.insert(state.deaths, { x = m.x, y = m.y, z = m.z, t = now });
    if sc_ids and m.claim and sc_ids[m.claim] then   -- a kill of the members whose fights count
        state.combat_until = math.max(state.combat_until or 0, now + (cfg.settle or 3));   -- kills still coming in
    end
    dbg(('party kill: monster id %d died at %.1f, %.1f'):fmt(m.sid, m.x, m.y));
end

local function track_world(now)
    if now - state.last_track < 0.25 then return; end
    state.last_track = now;
    local ent = AshitaCore:GetMemoryManager():GetEntity();
    local ids = party_ids();
    local here = {};
    -- the members whose fights count as combat (you / your party / the alliance): a monster
    -- targeting one of them, or claimed by one, or one of them engaged
    local sc_ids, mine = scope_members();
    local aggro = false;
    local near = false;                        -- a monster in a fight close to you
    local radius = (cfg.near_fight ~= false) and (cfg.combat_radius or 15) or 0;

    for i = 1, 0x3FF do
        local name = ent:GetName(i);
        if name and #name > 0 and bit.band(ent:GetRenderFlags0(i), 0x200) ~= 0 then
            local sid   = ent:GetServerId(i);
            local flags = ent:GetSpawnFlags(i);
            if name:lower() == PYXIS_NAME then
                if state.seen_pyxis[sid] then state.seen_pyxis[sid].last = now; end
                if bit.band(flags, MOB_FLAG) ~= 0 then
                    state.owned[sid] = nil;            -- a monster now (a mimic): never ours to talk to
                elseif not state.owned[sid] then
                    local first = state.seen_pyxis[sid];
                    if not first then
                        first = { t = now, last = now };
                        state.seen_pyxis[sid] = first;
                        dbg(('pyxis [%03X] id %d appeared'):fmt(i, sid));
                    end
                    -- keep deciding for 30s: under AoE lag the kill or the server's message can
                    -- arrive after the chest does
                    if now - first.t < 30 then
                        local x, y, z = pos_of(ent, i);
                        local why = nil;
                        for _, d in ipairs(state.deaths) do                -- a party kill on this spot
                            local dx, dy, dz = d.x - x, d.y - y, d.z - z;
                            if math.abs(d.t - first.t) < 30 and dx * dx + dy * dy + dz * dz < 36 then
                                why = 'party/alliance kill here';
                                break;
                            end
                        end
                        if not why and math.sqrt(ent:GetDistance(i)) <= 30 then   -- "...concealing a treasure chest!"
                            for k, ct in ipairs(state.conceal) do
                                if math.abs(ct - first.t) < 20 then   -- (chat floods delay the message)
                                    table.remove(state.conceal, k);
                                    why = 'treasure chest message';
                                    break;
                                end
                            end
                        end
                        if why then
                            state.owned[sid] = true;
                            state.owned_n = state.owned_n + 1;
                            state.last_owned_t = now;   -- (a round isn't over while yours keep turning up)
                            dbg(('pyxis [%03X] id %d is YOURS (%s)'):fmt(i, sid, why));
                        end
                    end
                end
            elseif bit.band(flags, MOB_FLAG) ~= 0 then
                here[i] = true;
                -- a living monster with you or your party as its target (you have hate): combat
                local hpp = ent:GetHPPercent(i);
                if not aggro and hpp > 0 then
                    local ok, ti = pcall(function () return ent:GetTargetedIndex(i); end);
                    if ok and ti and ti ~= 0 and mine[ti] then aggro = true; end
                end
                -- a living monster close by that is claimed by anyone or already hurt: a fight is
                -- going on right here (stunned / slept monsters target no one, but are claimed)
                if not near and radius > 0 and hpp > 0 then
                    local raw = bit.band(ent:GetClaimStatus(i) or 0, 0xFFFF);
                    if (raw ~= 0 or hpp < 100) and math.sqrt(ent:GetDistance(i)) <= radius then near = true; end
                end
                local m = state.mobs[i];
                if m and m.sid ~= sid then m = nil; state.mobs[i] = nil; end   -- index reused by another monster
                local claim = bit.band(ent:GetClaimStatus(i) or 0, 0xFFFF);   -- (upper bits: flags)
                local ours  = claim ~= 0 and ids[claim];
                if ours or m then
                    local x, y, z = pos_of(ent, i);
                    if not m then m = { sid = sid }; state.mobs[i] = m; end
                    m.x, m.y, m.z = x, y, z;
                    if ours then m.claim = claim; end   -- who claimed it (for the combat scope)
                    if ent:GetHPPercent(i) == 0 then add_death(m, now, sc_ids); end
                end
            end
        end
    end

    -- chests that are gone (opened, destroyed, despawned): forget them. The game reuses a small
    -- pool of chest ids, so a new chest later can come back with the same id and must start fresh.
    for sid, s in pairs(state.seen_pyxis) do
        if now - (s.last or s.t) > 3 then
            state.seen_pyxis[sid], state.owned[sid], state.done[sid] = nil, nil, nil;
            state.attempts[sid], state.tried_at[sid], state.reopen[sid] = nil, nil, nil;
            dbg(('pyxis id %d gone - forgotten'):fmt(sid));
        end
    end

    -- watched monsters that vanished: died (or despawned) where last seen
    for i, m in pairs(state.mobs) do
        if not here[i] then add_death(m, now, sc_ids); state.mobs[i] = nil; end
    end

    -- in combat: you're engaged, or a monster your party / alliance claimed is still alive.
    -- Auto mode waits until 2s after the last of it.
    -- (AoE: you may never be engaged, so a party member engaged, or a kill / chest in the
    -- last few seconds, counts too: it waits until the kills stop)
    local fighting = (my_status() == 1) or aggro or near;
    if not fighting then
        for _, m in pairs(state.mobs) do   -- a monster claimed by one of them, still alive
            if not m.dead and m.claim and sc_ids[m.claim] then fighting = true; break; end
        end
    end
    if not fighting then
        for idx, slot in pairs(mine) do    -- one of them engaged (you are checked above)
            if slot ~= 0 and ent:GetStatus(idx) == 1 then fighting = true; break; end
        end
    end
    if fighting then state.combat_until = math.max(state.combat_until or 0, now + (cfg.settle or 3)); end
    -- forget old deaths and chest messages
    for k = #state.deaths, 1, -1 do
        if now - state.deaths[k].t > 45 then table.remove(state.deaths, k); end
    end
    for k = #state.conceal, 1, -1 do
        if now - state.conceal[k] > 45 then table.remove(state.conceal, k); end
    end
end

-- Auto mode: talk to the nearest pyxis in range that hasn't had its turn.
local function auto_scan(now)
    if not (cfg.enabled and cfg.auto_talk) or state.job or state.pending_talk then return; end
    if state.menu_open and now - state.menu_open < 90 then return; end   -- a menu is up
    if cfg.wait_combat ~= false and now < (state.combat_until or 0) then return; end   -- still fighting
    if now < (state.next_talk_at or 0) then return; end   -- at most one chest a second
    if now - state.last_scan < 0.5 then return; end
    state.last_scan = now;
    local st = my_status();
    if st ~= 0 and st ~= 1 then return; end   -- idle or engaged only

    local ent, best, left, far, waiting = AshitaCore:GetMemoryManager():GetEntity(), nil, 0, 0, 0;
    local range = cfg.auto_range or 5;
    for i = 1, 0x3FF do
        local name = ent:GetName(i);
        if name and #name > 0 and name:lower() == PYXIS_NAME and bit.band(ent:GetRenderFlags0(i), 0x200) ~= 0
           and bit.band(ent:GetSpawnFlags(i), MOB_FLAG) == 0 then            -- never a mimic
            local id = ent:GetServerId(i);
            local d  = math.sqrt(ent:GetDistance(i));
            local mine = state.owned[id] or not cfg.own_only;
            if id ~= 0 and mine and not state.done[id] and (state.attempts[id] or 0) < 3 then
                if d > range then
                    far = far + 1;                                   -- yours, but too far to talk to
                elseif now - (state.tried_at[id] or -99) > 8 then
                    left = left + 1;
                    if not best or d < best.d then best = { index = i, id = id, d = d }; end
                else
                    waiting = waiting + 1;                           -- didn't answer: tried again soon
                end
            end
        end
    end
    if not best then
        -- nothing to do right now. A round is over once nothing is waiting for a retry and no
        -- chest of yours has turned up for 5s (under lag they keep arriving): say so once.
        local b = state.batch;
        if b and not state.job and not state.pending_talk and waiting == 0
           and now - (state.last_owned_t or 0) >= 5 then
            local lv = b.leave or 0;
            log(('All chests in range checked - %d chest%s done%s.%s'):fmt(
                b.n - lv, (b.n - lv) == 1 and '' or 's',
                lv > 0 and (', %d left for you to check'):fmt(lv) or '',
                far > 0 and (' %d more of yours %s out of range - walk closer.'):fmt(far, far == 1 and 'is' or 'are') or ''));
            state.batch = nil;
        end
        return;
    end
    state.batch = state.batch or { n = 0 };
    state.batch.left = left;   -- chests still to do, this one included
    state.attempts[best.id] = (state.attempts[best.id] or 0) + 1;
    state.tried_at[best.id] = now;
    state.pending_talk = { id = best.id, index = best.index, t = now };
    state.next_talk_at = now + 1.0;   -- (also spaces out talks that get no answer)
    dbg(('auto: pyxis [%03X] id %d at %.1fy (try %d)'):fmt(best.index, best.id, best.d, state.attempts[best.id]));
    send_talk(best.id, best.index);
end

local function tick()
    local now = os.clock();
    local pt = state.pending_talk;
    if pt and now - pt.t > 6.0 then   -- (lag: the server can be slow to answer)
        dbg(('auto: no menu from [%03X] (someone else\'s chest?)'):fmt(pt.index));
        state.pending_talk = nil;
    end
    -- you talked to a chest and the server never answered: free you rather than leave you stuck
    local gt = state.game_talk;
    if gt and now - gt.t > 2.5 then
        state.game_talk = nil;
        release_now(('no answer to your talk to chest [%03X]'):fmt(gt.index));
    end

    local ok, err = pcall(track_world, now);
    if not ok and not state.track_err then
        state.track_err = true;
        log('Chest ownership tracking failed: ' .. tostring(err));
        trace('track_world error: ' .. tostring(err));
    end
    local job = state.job;
    if not job then auto_scan(now); return; end

    -- each step waits for the server's answer (0x52 / 0x5C), or 1.2s at most
    if job.waiting and now - job.t > 1.2 then job.waiting = false; job.ready_at = now + gap(job); end
    if not job.waiting and job.ready_at and now >= job.ready_at then
        job.ready_at = nil;
        if not next_step(job) then finish(job); end
    end
    if state.job == job and now - job.started > 15 then dbg('job timed out'); finish(job); end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
ashita.events.register('packet_in', 'cm_packet_in', function (e)
    if e.id == 0x0A then
        state.job, state.pending_talk, state.menu_open = nil, nil, nil;
        state.done, state.attempts, state.tried_at, state.reopen = {}, {}, {}, {};
        state.mobs, state.deaths, state.seen_pyxis, state.owned, state.conceal = {}, {}, {}, {}, {};
        state.batch = nil;
        return;
    end

    local job = state.job;
    if (job or state.pending_talk) and (e.id == 0x52 or e.id == 0x5C or e.id == 0x2A or e.id == 0x53) then
        trace(('IN  0x%02X: %s'):fmt(e.id, hexs(e.data)));
    end
    if (e.id == 0x52 or e.id == 0x5C) and job and job.waiting then
        job.waiting  = false;
        job.ready_at = os.clock() + gap(job);
        dbg(('server answered (0x%02X), step %d/%d'):fmt(e.id, job.i, #job.steps));
        return;
    end

    if e.id ~= 0x34 and e.id ~= 0x32 then return; end
    state.menu_open = os.clock();   -- some npc's menu is up (cleared below if we hide it)
    if e.id ~= 0x34 then return; end

    local id    = r32(e.data, 0x04);
    local code  = r32(e.data, 0x08);
    local index = r16(e.data, 0x28);
    local zone  = r16(e.data, 0x2A);
    local menu  = r16(e.data, 0x2C);

    local name = AshitaCore:GetMemoryManager():GetEntity():GetName(index) or '';
    if name:lower() ~= PYXIS_NAME then return; end
    trace(('IN  0x34: %s'):fmt(hexs(e.data)));
    state.last_menu = { id = id, index = index, zone = zone, menu = menu };
    if state.game_talk and state.game_talk.id == id then state.game_talk = nil; end   -- your talk was answered

    -- ours if we talked to it lately (the server can answer late while a fight is busy)
    local auto = state.tried_at[id] ~= nil and os.clock() - state.tried_at[id] < 8;
    if state.pending_talk and state.pending_talk.id == id then state.pending_talk = nil; end
    state.done[id] = true;   -- one turn per chest
    dbg(('pyxis menu %d, code 0x%08X, npc [%03X]%s'):fmt(menu, code, index, auto and ' (auto)' or ''));

    if menu < LOCKED_MIN or menu > LOCKED_MAX then
        if state.reopen[id] then
            state.reopen[id] = nil;
            log('Chest opened - pick your items.');
        end
        dbg('unlocked chest (item list) - left to you');
        return;
    end
    if not cfg.enabled then return; end
    if job then dbg('busy with another chest - ignored'); return; end

    job = { id = id, index = index, zone = zone, menu = menu, code = code, auto = auto,
            started = os.clock(), shown = true };
    -- hide the menu only when we talked to it ourselves: when YOU talk to a chest the game
    -- waits for its menu, and hiding it leaves you stuck in place
    local hide = auto;
    job.shown = not hide;
    local acting = decide(job);
    if acting then
        if hide then e.blocked = true; state.menu_open = nil; end
    elseif auto and cfg.leave_show == true then
        -- a chest you leave, reached by auto mode: its menu is shown to you to look at and pick
        job.shown = true;
        log('Left for you - its menu is open.');
    elseif auto then
        -- we opened this menu ourselves for a chest you leave: close it quietly
        e.blocked = true;
        state.menu_open = nil;
        job.steps, job.i = { { 'menu', 0, 0, CLOSE_PARAM2 } }, 0;
        job.ready_at = os.clock() + 0.3;
        state.job = job;
    else
        job.shown = true;   -- you see the menu as normal
    end
end);

ashita.events.register('packet_out', 'cm_packet_out', function (e)
    -- AFK safety: your own actions (not ChestMaster's or another addon's) count as activity:
    -- talk / attack / cast, trade, use an item, answer a menu. Position updates (0x15) are sent
    -- all the time, so they don't count.
    if not e.injected and (e.id == 0x1A or e.id == 0x36 or e.id == 0x37 or e.id == 0x5B) then mark_active(); end

    -- You talking to a chest: the game now waits for its menu. If ChestMaster is handling that
    -- chest already, the server won't answer and you'd be stuck: drop the talk and free you.
    if e.id == 0x1A and not e.injected and #e.data >= 0x0C then
        local id  = struct.unpack('<I', e.data, 0x04 + 1);
        local idx = struct.unpack('<H', e.data, 0x08 + 1);
        local cat = struct.unpack('<H', e.data, 0x0A + 1);
        if cat == 0 then
            local nm = (AshitaCore:GetMemoryManager():GetEntity():GetName(idx) or ''):lower();
            if nm == PYXIS_NAME then
                local job, pt = state.job, state.pending_talk;
                if (job and job.id == id) or (pt and pt.id == id) then
                    e.blocked = true;
                    trace(('you talked to chest [%03X] while ChestMaster handles it - dropped, freeing you'):fmt(idx));
                    release_now('your talk to a chest already being handled');
                    return;
                end
                state.game_talk = { id = id, index = idx, t = os.clock() };
            end
        end
    end
    if e.id == 0x5B and not e.injected then
        local stay = struct.unpack('<B', e.data, 0x0E + 1);
        if stay == 0 then state.menu_open = nil; end   -- you closed / finished a menu
    end
    if cfg.trace and (e.id == 0x5B or e.id == 0x1A or e.id == 0x36) and (state.job or state.pending_talk) then
        trace(('OUT 0x%02X%s: %s'):fmt(e.id, e.injected and ' (ours)' or ' (game)', hexs(e.data)));
    end
end);

ashita.events.register('text_in', 'cm_text_in', function (e)
    local raw = e.message or '';
    -- the server tells your party / alliance each time one of its kills drops a chest
    if raw:lower():find('concealing a treasure chest', 1, true) then
        local now = os.clock();
        table.insert(state.conceal, now);
        -- kills still coming in (it can't tell whose kill it was, so not when only your own fights count)
        if (cfg.combat_scope or 'party') ~= 'self' then
            state.combat_until = math.max(state.combat_until or 0, now + (cfg.settle or 3));
        end
    end
    if not cfg.trace or not (state.job or state.pending_talk) then return; end
    local msg = raw:gsub('\30.', ''):gsub('\31.', ''):gsub('[%c]', '');
    if msg ~= '' and not msg:lower():find('chestmaster', 1, true) then trace('chat: ' .. msg); end
end);

----------------------------------------------------------------------
-- UI (vcmenu: the VanaCore look your other addons use)
----------------------------------------------------------------------
local SEG = { { LEAVE, 'Leave' }, { OPEN, 'Open' }, { DESTROY, 'Destroy' }, { TIMED, 'Timed' } };

-- "Soothing light: open now" / "Soothing light: 3:12" for every Timed rule
local function timed_lines()
    local out = {};
    for _, c in ipairs(CATS) do
        if cfg.actions[c.key] == TIMED then
            local left = timed_left(c.key);
            out[#out + 1] = { c.label, left <= 0 and 'opens the next one' or ('destroying, next open in ' .. mmss(left)), left <= 0 };
        end
    end
    return out;
end
local SUB = { rules = 'Contents', status = 'Status', settings = 'Settings', help = 'Help' };
local PAGES = {};

-- Free you from a stuck menu / event: tell the server the last chest menu is finished, drop
-- what ChestMaster was doing, and release the game. `only_if_stuck`: tell the server only when
-- you are actually in an event (the widget's switch runs this on every click).
local function unstick(only_if_stuck)
    local m = state.last_menu;
    if m and (not only_if_stuck or my_status() == 4) then pcall(send_menu, m, 0, 0, CLOSE_PARAM2); end
    state.job, state.pending_talk, state.menu_open, state.game_talk = nil, nil, nil, nil;
    release_now('unstick');
end

local function set_enabled(on)
    cfg.enabled = on; save();
    if on then mark_active(); end   -- turning it on is you at the keyboard
    log('Automation ' .. (on and 'ON.' or 'OFF.'));
end

-- AFK safety, each frame: your movement counts as activity; with none of it (and no key,
-- mouse, controller, command or action of yours) for AFK_MINUTES, automation turns OFF.
local function afk_check()
    local ok, x, y, z = pcall(function ()
        local me = AshitaCore:GetMemoryManager():GetParty():GetMemberTargetIndex(0);
        if me == 0 then return nil; end
        return pos_of(AshitaCore:GetMemoryManager():GetEntity(), me);
    end);
    if ok and x then
        local p = state.afk_pos;
        if not p or math.abs(x - p[1]) + math.abs(y - p[2]) + math.abs(z - p[3]) > 0.5 then
            if p then mark_active(); end
            state.afk_pos = { x, y, z };
        end
    end
    if not cfg.enabled or afk_left() > 0 then return; end
    if state.job or state.pending_talk then return; end   -- let the chest in hand finish first
    set_enabled(false);
    log(('No movement or input for %d minutes: ChestMaster turned itself OFF (AFK safety). Turn it back on with /cm on or the widget.'):fmt(AFK_MINUTES));
end

-- the widget's on / off switch: flips ChestMaster and frees you if you're stuck
local function widget_toggle()
    set_enabled(not cfg.enabled);
    unstick(true);
end

local function rule_rows(group)
    for _, c in ipairs(CATS) do
        if c.group == group then
            vc.label_row(c.label, 300);
            local v = vc.seg('act_' .. c.key, SEG, cfg.actions[c.key] or LEAVE);
            if v ~= nil then cfg.actions[c.key] = v; save(); end
        end
    end
end

PAGES.rules = function ()
    vc.title('Contents', 'what to do with each kind of chest');
    local v = vc.switch_row('en_top', cfg.enabled and 'ChestMaster is ON' or 'ChestMaster is OFF', cfg.enabled);
    if v ~= nil then set_enabled(v); end
    vc.note('Open trades the chest a Forbidden Key. Destroy breaks it and pays Cruor (tier x 10). Leave shows you the menu as normal. Timed opens one, then destroys that kind until the timer below runs out.');
    vc.section('CRUOR & EXPERIENCE');
    rule_rows('cur');
    vc.section('LIGHTS');
    rule_rows('light');
    vc.section('ITEMS');
    rule_rows('item');

    vc.section('TIMED');
    vc.label_row('Open one, then wait', 210);
    v = vc.slider('tmin', cfg.timer_minutes or 5, 1, 30, 1, '%d min', 150);
    if v ~= nil then cfg.timer_minutes = v; save(); end
    local lines = timed_lines();
    if #lines == 0 then
        vc.note('No kind is set to Timed.');
    else
        for _, t in ipairs(lines) do vc.stat(t[1], t[2], t[3] and vc.colors.good or vc.colors.gold, 170); end
        if vc.button('Reset timers') then state.timed = {}; log('Timers reset: the next one of each Timed kind opens.'); end
    end
    vc.note('Item chests opened with a key show the item list: picking items is left to you.');
end

PAGES.status = function ()
    vc.title('Status');
    vc.section('NOW');
    vc.stat('Automation', cfg.enabled and 'On' or 'Off', cfg.enabled and vc.colors.good or vc.colors.bad);
    vc.stat('Auto-talk', cfg.auto_talk and ('On, %.1f yalms%s'):fmt(cfg.auto_range or 5,
        (cfg.own_only ~= false) and ', your chests only' or ', any chest') or 'Off');
    vc.stat('Your chests seen', tostring(state.owned_n));
    if cfg.auto_talk and cfg.wait_combat ~= false and os.clock() < (state.combat_until or 0) then
        vc.stat('Auto mode', ('waiting for the fight to end (%s)'):fmt(
            ({ self = 'yours', party = 'your party\'s', alliance = 'the alliance\'s' })[cfg.combat_scope or 'party'] or 'your party\'s'),
            vc.colors.gold);
    end
    local k = state.keys;
    vc.stat('Forbidden Keys', k.id and tostring(k.count) or '?', k.count > 0 and vc.colors.gold or vc.colors.dim);
    vc.stat('Working on', state.job and ('chest [%03X], step %d'):fmt(state.job.index, state.job.i or 0)
        or (state.pending_talk and 'talking to a chest' or 'nothing'));
    for _, t in ipairs(timed_lines()) do vc.stat(t[1], t[2], t[3] and vc.colors.good or vc.colors.gold); end
    if cfg.enabled then
        local left = math.max(0, afk_left());
        vc.stat('AFK safety', ('turns OFF in %s if you stay idle'):fmt(mmss(left)),
            left < 120 and vc.colors.gold or vc.colors.dim);
    end

    vc.section('LAST CHEST');
    local l = state.last;
    if l then
        vc.stat('Chest', esc(l.color));
        vc.stat('Contents', esc(l.desc));
        vc.stat('Rule', esc(l.label));
        vc.stat('Done', ACT_NAMES[l.action], l.action == LEAVE and vc.colors.dim or vc.colors.teal);
        if l.note then vc.stat('Note', esc(l.note), vc.colors.gold); end
        vc.stat('Code', ('0x%08X'):fmt(l.code), vc.colors.mute);
    else
        vc.note('No chest yet. Walk up to a Sturdy Pyxis.');
    end
end

PAGES.settings = function ()
    vc.title('Settings');
    vc.section('AUTOMATION');
    local v = vc.switch_row('en', 'Handle chests automatically', cfg.enabled);
    if v ~= nil then set_enabled(v); end
    vc.note(('AFK safety: with no movement, key, mouse or controller input, command or action from you for %d minutes, ChestMaster turns itself OFF. It stays off until you turn it back on. This can\'t be turned off: ChestMaster is for use at the keyboard only.'):fmt(AFK_MINUTES));

    vc.section('ON-SCREEN WIDGET');
    v = vc.switch_row('wid', 'Show the ON/OFF widget on screen', cfg.show_widget);
    if v ~= nil then cfg.show_widget = v; save(); end
    vc.label_row('Look', 250);
    v = vc.seg('wtheme', { { 'classic', 'Classic' }, { 'vex', 'Vex' }, { 'hex', 'Hex link' } }, cfg.widget_theme or 'classic');
    if v ~= nil then cfg.widget_theme = v; save(); end
    if cfg.widget_theme == 'vex' then
        vc.label_row('Row', 230);
        v = vc.seg('wrow', { { 'card', 'Menu card' }, { 'slant', 'Party slant' } }, cfg.widget_row or 'card');
        if v ~= nil then cfg.widget_row = v; save(); end
        vc.label_row('Colours', 280);
        v = vc.seg('wscheme', { { 'yuna', 'Yuna' }, { 'blue', 'Blue & white' }, { 'purple', 'Purple' } }, cfg.widget_scheme or 'yuna');
        if v ~= nil then cfg.widget_scheme = v; save(); end
    elseif cfg.widget_theme == 'hex' then
        v = vc.switch_row('wgold', 'Gold corners', cfg.widget_gold ~= false);
        if v ~= nil then cfg.widget_gold = v; save(); end
        vc.label_row('Corner cut', 230);
        v = vc.seg('wcut', { { 'small', 'Small' }, { 'medium', 'Medium' }, { 'large', 'Large' } }, cfg.widget_cut or 'medium');
        if v ~= nil then cfg.widget_cut = v; save(); end
    end
    if cfg.widget_theme == 'vex' or cfg.widget_theme == 'hex' then
        vc.label_row('Size', 210);
        v = vc.slider('wsize', cfg.widget_size or 1.0, 0.6, 2.0, 0.05, '%.2fx', 150);
        if v ~= nil then cfg.widget_size = v; save(); end
        vc.note('Click the tag to turn ChestMaster on or off, drag the plate to move it, right-click for settings. The tag turns gold (WORK) while a chest is being handled.');
    end

    vc.section('AUTO MODE');
    v = vc.switch_row('auto', 'Talk to nearby chests by myself (no clicking)', cfg.auto_talk);
    if v ~= nil then cfg.auto_talk = v; save(); end
    v = vc.switch_row('own', 'Only chests from my party / alliance kills', cfg.own_only ~= false);
    if v ~= nil then cfg.own_only = v; save(); end
    v = vc.switch_row('lshow', 'Leave chests: stop and open their menu for me (off: skip them, I check them after)', cfg.leave_show == true);
    if v ~= nil then cfg.leave_show = v; save(); end
    v = vc.switch_row('wcombat', 'Wait until out of combat', cfg.wait_combat ~= false);
    if v ~= nil then cfg.wait_combat = v; save(); end
    if cfg.wait_combat ~= false then
        vc.label_row('Combat counts for', 250);
        v = vc.seg('cscope', { { 'self', 'Me' }, { 'party', 'My party' }, { 'alliance', 'Alliance' } }, cfg.combat_scope or 'party');
        if v ~= nil then cfg.combat_scope = v; save(); end
        vc.note('Who must be out of the fight before chests are handled: monsters attacking them, monsters they claimed, or them engaged. Pick Me to farm chests while the rest of the alliance keeps fighting. Which chests count as yours is the whole alliance either way.');
        vc.label_row('Wait after the last kill', 210);
        v = vc.slider('settle', cfg.settle or 3, 1, 10, 1, '%ds', 150);
        if v ~= nil then cfg.settle = v; save(); end
        v = vc.switch_row('nfight', 'Nearby fights hold off chests', cfg.near_fight ~= false);
        if v ~= nil then cfg.near_fight = v; save(); end
        if cfg.near_fight ~= false then
            vc.label_row('Nearby fight range', 210);
            v = vc.slider('crad', cfg.combat_radius or 15, 1, 30, 1, '%d yalms', 150);
            if v ~= nil then cfg.combat_radius = v; save(); end
        end
        vc.note('Nearby fights: any living monster this close to you that is claimed (by anyone) or hurt holds off chests, e.g. stunned or slept monsters that aren\'t attacking yet.');
    end
    vc.label_row('Range', 210);
    v = vc.slider('ar', cfg.auto_range or 5.0, 2.0, 6.0, 0.5, '%.1f yalms', 150);
    if v ~= nil then cfg.auto_range = v; save(); end
    vc.note('Each chest gets one turn, and never while a menu is open. A chest counts as yours when it appears where a monster your party or alliance claimed just died; other people\'s chests, free-spawning ones and mimics are left alone. Chests you click yourself are always handled.');

    vc.section('NO FORBIDDEN KEY');
    vc.label_row('When Open is picked but you have no key', 170);
    v = vc.seg('nokey', { { LEAVE, 'Leave' }, { DESTROY, 'Destroy' } }, cfg.no_key);
    if v ~= nil then cfg.no_key = v; save(); end

    vc.section('DEBUG');
    v = vc.switch_row('dbg', 'Debug messages in chat', state.debug);
    if v ~= nil then state.debug = v; end
    v = vc.switch_row('trc', 'Write chestmaster_trace.log (for fixing problems)', cfg.trace);
    if v ~= nil then cfg.trace = v; save(); end
end

PAGES.help = function ()
    vc.title('Help');
    vc.section('USING IT');
    vc.note('With auto-talk on, just stand near your Sturdy Pyxis: ChestMaster talks to it, reads what it holds from the server and acts on your Contents rules.');
    vc.note('You can also talk to a chest yourself; it is handled the same way.');
    vc.note('Timed: the first chest of that kind is opened (with a key) and starts the timer; every one after is destroyed until the timer runs out. With no key, nothing is opened and the timer does not start.');
    vc.note('Unlocked chests (the item list after opening) are always left to you.');
    vc.note(('AFK safety: %d minutes without you moving, pressing a key or button, clicking, typing a command or acting turns ChestMaster OFF.'):fmt(AFK_MINUTES));
    vc.section('COMMANDS');
    vc.stat('/cm', 'show or hide this window');
    vc.stat('/cm on | off', 'automation on or off');
    vc.stat('/cm toggle', 'flip it (handy for a macro)');
    vc.stat('/cm auto', 'auto-talk on or off');
    vc.stat('/cm widget', 'show or hide the ON/OFF pill');
    vc.stat('/cm last', 'the last chest and what was done');
    vc.stat('/cm debug', 'debug messages');
    vc.stat('/cm unstick', 'if you are ever stuck in place');
end

local function sidebar(nav)
    if nav.head('list', 'Contents', state.win.page == 'rules') then state.win.page = 'rules'; end
    nav.tip('Leave, open or destroy each kind of chest');
    if nav.head('widget', 'Status', state.win.page == 'status') then state.win.page = 'status'; end
    nav.caption('SETUP');
    if nav.head('gear', 'Settings', state.win.page == 'settings') then state.win.page = 'settings'; end
    nav.gap(8);
    if nav.head('about', 'Help', state.win.page == 'help') then state.win.page = 'help'; end
end

local WIN = {
    id = 'chestmaster', title = 'ChestMaster', size = { 760, 600 }, min = { 620, 420 },
    pages = PAGES, sidebar = sidebar, scaler = true,
    on_scale = function (s) cfg.ui_scale = s; save(); end,
    subtitle = function (page) return SUB[page]; end,
    header_right = function ()
        local k = state.keys;
        return ('%s   |   Forbidden Keys: %s'):fmt(cfg.enabled and 'ON' or 'OFF', k.id and tostring(k.count) or '?'),
               cfg.enabled and vc.colors.good or vc.colors.bad;
    end,
};

-- The small always-on pill: switch = on/off, status text, right-click opens the window.
local WIDGET_OPEN = { true };

----------------------------------------------------------------------
-- YunaUI widget looks, after StopMove's (Settings > On-screen widget)
--   vex : a slanted state tag, then a dark slanted plate with the name and a state bar
--   hex : Hex link's cut-corner plate lit gold, the name, a slanted gold divider, a job-box tag
----------------------------------------------------------------------
local WSCHEME = {
    yuna   = { on = { 0.36, 0.79, 0.42 }, off = { 0.85, 0.28, 0.30 }, busy = { 0.95, 0.70, 0.24 },
               plate = { 0.085, 0.08, 0.11 }, plate_a = 0.88, edge = { 0.29, 0.27, 0.34 },
               name = { 0.84, 0.84, 0.88 }, lockname = { 0.95, 0.70, 0.24 } },
    blue   = { on = { 0.35, 0.55, 1.00 }, off = { 0.20, 0.25, 0.36 }, busy = { 0.93, 0.96, 1.00 },
               plate = { 0.055, 0.055, 0.065 }, plate_a = 0.88, edge = { 0, 0, 0 },
               name = { 0.95, 0.97, 1.00 }, lockname = { 0.80, 0.92, 1.00 } },
    purple = { on = { 0.36, 0.79, 0.42 }, off = { 0.85, 0.28, 0.30 }, busy = { 0.95, 0.70, 0.24 },
               plate = { 0.085, 0.08, 0.11 }, plate_a = 0.88, edge = { 0.55, 0.40, 0.88 },
               name = { 0.84, 0.84, 0.88 }, lockname = { 0.95, 0.70, 0.24 } },
    hex    = { on = { 0.36, 0.79, 0.42 }, off = { 0.85, 0.28, 0.30 }, busy = { 0.95, 0.70, 0.24 },
               plate = { 0.067, 0.059, 0.09 }, plate_a = 0.86, edge = { 0.79, 0.65, 0.35 },
               name = { 0.84, 0.84, 0.88 }, lockname = { 0.95, 0.70, 0.24 } },
};
local TRACK = { 0.14, 0.13, 0.17 };

local function c32(c, a) return imgui.GetColorU32({ c[1], c[2], c[3], a or 1 }); end
local function poly_fill(dl, p, col)            -- a convex shape (triangle fan if this ImGui can't)
    if not pcall(function () dl:AddConvexPolyFilled(p, col); end) then
        for i = 2, #p - 1 do pcall(function () dl:AddTriangleFilled(p[1], p[i], p[i + 1], col); end); end
    end
end
local function poly_line(dl, p, col, th)
    for i = 1, #p do dl:AddLine(p[i], p[i % #p + 1], col, th); end
end
local function lighten(c, t) return { c[1] + (1 - c[1]) * t, c[2] + (1 - c[2]) * t, c[3] + (1 - c[3]) * t }; end

local function draw_widget_yuna()
    local vex    = (cfg.widget_theme == 'vex');
    local sch    = vex and (WSCHEME[cfg.widget_scheme] or WSCHEME.yuna) or WSCHEME.hex;
    local blue   = vex and cfg.widget_scheme == 'blue';
    local purple = vex and cfg.widget_scheme == 'purple';
    local u      = cfg.widget_size or 1.0;

    -- what to show
    local now, job = os.clock(), state.job;
    local st, label, msg = 'on', 'ON', 'CHESTMASTER';
    if not cfg.enabled then
        st, label = 'off', 'OFF';
    elseif job then
        st, label, msg = 'busy', 'WORK', 'WORKING...';
    elseif state.pending_talk then
        st, label, msg = 'busy', 'WORK', 'TALKING...';
    elseif state.flash and now < state.flash.until_t then
        msg = state.flash.text:upper();
    end
    -- no words on the plate: the chest icon, the keys and the tag (ON / OFF / WORK) say it all
    local idle = true;
    msg = '';
    local c    = sch[st];
    local tagc = { c, lighten(c, 0.45), { c[1] * 0.18, c[2] * 0.18, c[3] * 0.18 } };
    if blue then
        local lum = 0.30 * c[1] + 0.59 * c[2] + 0.11 * c[3];
        tagc[3] = (lum > 0.6) and { 0.06, 0.09, 0.18 } or { 1, 1, 1 };
    end
    local lit   = (st == 'busy');
    local keys  = state.keys.id and tostring(state.keys.count) or '';

    -- geometry (sizes at 100%, as StopMove's defaults)
    local TAG_W, TAG_H, NAME_W, NAME_H, GAP = 40, 17, (idle and 112 or 200), 30, 10;
    local card = vex and (cfg.widget_row or 'card') == 'card';
    local pad = (card and 5 or 3) * u;          -- (room for the card's glow)
    local W, H, over;
    if card then                                -- [name | divider | tag] in one rounded card
        TAG_W, TAG_H, NAME_W = 48, 18, (idle and 86 or 180);   -- (86: chest, key and a centred 3-digit count)
        W, H = (NAME_W + GAP + TAG_W + 14) * u, math.max(NAME_H, TAG_H + 8) * u;
    elseif vex then
        over = blue and 0 or 0.32 * (NAME_H + TAG_H) / 2;
        W, H = (TAG_W + NAME_W - over) * u, NAME_H * u;
    else
        if idle then NAME_W = 96; end           -- chest, key and a centred 3-digit count
        W, H = (NAME_W + GAP + TAG_W + 6) * u, math.max(NAME_H, TAG_H + 8) * u;
    end

    imgui.SetNextWindowPos({ 300, 300 }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSize({ math.floor(W + 2 * pad + 2), math.floor(H + 2 * pad + 2) }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    imgui.PushStyleColor(ImGuiCol_WindowBg, { 0, 0, 0, 0 });
    local flags = bit.bor(ImGuiWindowFlags_NoDecoration or 0, ImGuiWindowFlags_NoBackground or 0,
                          ImGuiWindowFlags_NoFocusOnAppearing or 0, ImGuiWindowFlags_NoNav or 0);
    if imgui.Begin('ChestMaster pill###cm_widget', WIDGET_OPEN, flags) then
        vc.safe(function ()
            local wx, wy = vc.xy(imgui.GetWindowPos());
            local dl = imgui.GetWindowDrawList();
            local x0, y0 = wx + pad, wy + pad;

            -- text helpers: px is the size at 100% (13 = the normal line)
            local function scale(px) pcall(imgui.SetWindowFontScale, u * px / 13); end
            local function tw(str) return (vc.xy(imgui.CalcTextSize(str))) or #str * 7; end
            local function lh() local ok, v = pcall(imgui.GetTextLineHeight); return (ok and v) or 13 * u; end
            local function spaced_w(str, sp)
                local w = 0;
                for i = 1, #str do w = w + tw(str:sub(i, i)); end
                return w + sp * math.max(0, #str - 1);
            end
            local function fit(str, avail, sp)
                if spaced_w(str, sp) <= avail then return str; end
                for n = #str - 1, 1, -1 do
                    local t = str:sub(1, n) .. '.';
                    if spaced_w(t, sp) <= avail then return t; end
                end
                return str:sub(1, 1);
            end
            local function spaced(x, y, str, col, sp)
                for i = 1, #str do
                    local ch = str:sub(i, i);
                    dl:AddText({ x, y }, col, ch);
                    x = x + tw(ch) + sp;
                end
            end
            local function centred(cx, cy, str, px, col)
                scale(px);
                dl:AddText({ cx - tw(str) / 2, cy - lh() / 2 }, col, str);
            end

            local NAME_PX, SP = 14, 1.6 * u;
            local ncol = c32(lit and sch.lockname or sch.name);
            local tag_x, tag_y, tag_w, tag_h;

            -- a little treasure chest (a pyxis): wooden lid and body, gold bands and lock plate.
            -- Drawn with its left edge at x, centred on cy; returns the room it takes.
            local ICON = 24 * u;
            local function chest(x, cy)
                local w, h = 20 * u, 16 * u;
                local a = cfg.enabled and 1 or 0.45;
                local top, seam, bot = cy - h / 2, cy - h / 2 + h * 0.42, cy + h / 2;
                local gold = lit and { 1.0, 0.92, 0.70 } or { 0.95, 0.74, 0.34 };
                local r = 4 * u;
                -- lid (rounded top) and body
                dl:AddRectFilled({ x, top }, { x + w, seam + r }, c32({ 0.58, 0.37, 0.18 }, a), r);
                dl:AddRectFilled({ x, seam }, { x + w, bot }, c32({ 0.44, 0.27, 0.12 }, a), 1.5 * u);
                dl:AddLine({ x + 2 * u, top + 2.5 * u }, { x + w - 2 * u, top + 2.5 * u }, c32({ 0.80, 0.56, 0.30 }, 0.6 * a), 1);  -- lid highlight
                -- outline, seam and the two bands
                dl:AddRect({ x, top }, { x + w, bot }, c32(gold, a), r, 0, 1.2);
                dl:AddLine({ x, seam }, { x + w, seam }, c32(gold, a), 1.2);
                dl:AddLine({ x + w * 0.22, top + 1 }, { x + w * 0.22, bot - 1 }, c32(gold, 0.85 * a), 1.4 * u);
                dl:AddLine({ x + w * 0.78, top + 1 }, { x + w * 0.78, bot - 1 }, c32(gold, 0.85 * a), 1.4 * u);
                -- the lock plate and its keyhole
                local lw, lh_ = 5 * u, 6 * u;
                local lx, ly = x + w / 2 - lw / 2, seam - lh_ * 0.35;
                dl:AddRectFilled({ lx, ly }, { lx + lw, ly + lh_ }, c32(gold, a), 1 * u);
                dl:AddCircleFilled({ x + w / 2, ly + lh_ * 0.42 }, 0.9 * u, c32({ 0.12, 0.07, 0.03 }, a), 8);
                return ICON;
            end

            -- a little gold key, then the Forbidden Key count. xl is the chest's right edge:
            -- one space, the key, two spaces, the count (room kept for 3 digits).
            -- Returns the room it takes (0 when the count is unknown).
            local function draw_keys(xl, xr, cy)
                if keys == '' then return 0; end
                scale(11);
                local sp = tw(' ');
                if not sp or sp <= 0 then sp = 3.5 * u; end
                local nw = tw('888');
                local iw = 14 * u;
                local x  = xl + sp;                          -- one space after the chest
                local total = sp + iw + 2 * sp + nw;
                local a  = cfg.enabled and 1 or 0.45;
                local gold = { 0.95, 0.74, 0.34 };
                -- bow (ring), shaft and two teeth
                dl:AddCircle({ x + 3.5 * u, cy }, 3 * u, c32(gold, a), 12, 1.6 * u);
                dl:AddLine({ x + 6.5 * u, cy }, { x + iw, cy }, c32(gold, a), 1.6 * u);
                dl:AddLine({ x + iw - 3.5 * u, cy }, { x + iw - 3.5 * u, cy + 3 * u }, c32(gold, a), 1.4 * u);
                dl:AddLine({ x + iw - 1 * u, cy }, { x + iw - 1 * u, cy + 2.5 * u }, c32(gold, a), 1.4 * u);
                -- the count: red when you have none
                local ncol = (state.keys.count > 0) and c32(sch.name, 0.8 * a) or c32({ 0.93, 0.43, 0.47 }, a);
                -- the count: centred between the key and xr (the divider), else two spaces after the key
                local kx, aw = x + iw, tw(keys);
                local tx = xr and (kx + math.max(sp, (xr - kx - aw) / 2)) or (kx + 2 * sp);
                dl:AddText({ tx, cy - lh() / 2 }, ncol, keys);
                return total;
            end

            if card then
                -- StopMove's Vex Menu row: a rounded near-black card, its edge running pink-red to
                -- violet with a soft glow (white while working), a glowing violet divider, a rounded tag
                local EL, ER = { 1.00, 0.36, 0.62 }, { 0.62, 0.40, 1.00 };
                if blue then EL, ER = { 0.30, 0.52, 0.98 }, { 0.78, 0.90, 1.00 }; end
                if purple then EL, ER = sch.edge, sch.edge; end
                local function card_edge(x, y, w, h, r, th, a)
                    local pts = {};
                    local function arc(cx, cy, a0, a1)
                        for i = 0, 6 do
                            local t = a0 + (a1 - a0) * i / 6;
                            pts[#pts + 1] = { cx + math.cos(t) * r, cy + math.sin(t) * r };
                        end
                    end
                    arc(x + r, y + r, math.pi, 1.5 * math.pi);
                    arc(x + w - r, y + r, 1.5 * math.pi, 2 * math.pi);
                    arc(x + w - r, y + h - r, 0, 0.5 * math.pi);
                    arc(x + r, y + h - r, 0.5 * math.pi, math.pi);
                    for i = 1, #pts do
                        local p0, p1 = pts[i], pts[i % #pts + 1];
                        local t = math.max(0, math.min(1, ((p0[1] + p1[1]) / 2 - x) / math.max(1, w)));
                        local col = lit and { 1, 1, 1 } or { EL[1] + (ER[1] - EL[1]) * t, EL[2] + (ER[2] - EL[2]) * t, EL[3] + (ER[3] - EL[3]) * t };
                        dl:AddLine(p0, p1, c32(col, a), th);
                    end
                end
                local r = math.min(8 * u, H / 2 - 1);
                if not purple then card_edge(x0 - 1.5, y0 - 1.5, W + 3, H + 3, r + 1.5, 3.5, lit and 0.16 or 0.12); end
                dl:AddRectFilled({ x0, y0 }, { x0 + W, y0 + H }, c32(sch.plate, sch.plate_a), r);
                card_edge(x0, y0, W, H, r, purple and 1.6 or 1.3, purple and 1 or 0.95);

                -- the name / status (and keys), spaced capitals
                local cut = x0 + (7 + NAME_W + GAP / 2) * u;
                local kw = draw_keys(x0 + 9 * u + 20 * u, cut, y0 + H / 2);
                local iw = chest(x0 + 9 * u, y0 + H / 2);
                scale(12.5);
                local txt = fit(msg, (NAME_W - 6) * u - kw - 10 * u - iw, 1.5 * u);
                spaced(x0 + 9 * u + iw, y0 + H / 2 - lh() / 2, txt, ncol, 1.5 * u);

                -- the divider: violet, with a faint glow
                dl:AddLine({ cut, y0 + 5 * u }, { cut, y0 + H - 5 * u }, c32(blue and { 0.40, 0.62, 1.0 } or { 0.62, 0.40, 1.0 }, 0.35), 3.5 * u);
                dl:AddLine({ cut, y0 + 5 * u }, { cut, y0 + H - 5 * u }, c32(blue and { 0.72, 0.86, 1.0 } or { 0.78, 0.62, 1.0 }, 1), 1.2);

                -- the rounded tag; light text on a dark tag (OFF), dark on a bright one (ON)
                tag_w, tag_h = TAG_W * u, TAG_H * u;
                tag_x, tag_y = x0 + (7 + NAME_W + GAP) * u, y0 + (H - tag_h) / 2;
                local l, t, rr_, b = tag_x, tag_y, tag_x + tag_w, tag_y + tag_h;
                local rr = math.min(5 * u, tag_h / 2);
                dl:AddRectFilled({ l, t }, { rr_, b }, c32(tagc[1]), rr);
                dl:AddRect({ l, t }, { rr_, b }, c32({ 0.04, 0.04, 0.055 }), rr, 0, 1);
                dl:AddRect({ l + 1.5 * u, t + 1.5 * u }, { rr_ - 1.5 * u, b - 1.5 * u }, c32(tagc[2], 0.8), math.max(1, rr - 1.5 * u), 0, 1);
                local lum = 0.30 * c[1] + 0.59 * c[2] + 0.11 * c[3];
                local tcol = blue and tagc[3] or ((lum > 0.5) and tagc[3] or lighten(c, 0.70));
                centred((l + rr_) / 2, (t + b) / 2, label, math.min(10.5, TAG_H * 0.62), c32(tcol));
            elseif vex then
                -- the tag: upright left side, right side slanted like the plate (Blue & white: mirrored)
                tag_w, tag_h = TAG_W * u, TAG_H * u;
                tag_x, tag_y = x0, y0 + (H - tag_h) / 2;
                local k = tag_h * 0.32;
                local P = { { tag_x, tag_y }, { tag_x + tag_w, tag_y }, { tag_x + tag_w - k, tag_y + tag_h }, { tag_x, tag_y + tag_h } };
                if blue then P = { { tag_x + k, tag_y }, { tag_x + tag_w, tag_y }, { tag_x + tag_w, tag_y + tag_h }, { tag_x, tag_y + tag_h } }; end
                poly_fill(dl, P, c32(tagc[1]));
                if blue then poly_line(dl, P, c32({ 0.92, 0.95, 1.0 }, 0.85), 1); end
                centred(tag_x + (blue and (tag_w + k / 2) or (tag_w - k / 2)) / 2, tag_y + tag_h / 2, label,
                        math.min(10.5, TAG_H * 0.62), c32(tagc[3]));

                -- the plate: slanted, its slanted edge on the tag's
                local px, ph, pw = tag_x + tag_w - over * u, H, NAME_W * u;
                local pk = ph * 0.32;
                local p = { { px + pk, y0 }, { px + pw, y0 }, { px + pw - pk, y0 + ph }, { px, y0 + ph } };
                if blue then p[1] = { px, y0 }; end
                poly_fill(dl, p, c32(sch.plate, sch.plate_a));
                if lit and not blue then
                    poly_line(dl, p, c32(sch.busy, 0.25), 3.5 * u);
                    poly_line(dl, p, c32(sch.busy, 0.95), 1);
                else
                    poly_line(dl, p, c32(sch.edge, (blue or purple) and 1 or 0.8), purple and 1.6 or 1);
                end

                -- keys at the right, then the name / status in what's left
                local kw = draw_keys(px + 13 * u + 20 * u, px + pw - pk - 4 * u, y0 + (ph - 5 * u) / 2 + 1 * u);
                local iw = chest(px + 13 * u, y0 + (ph - 5 * u) / 2 + 1 * u);
                scale(NAME_PX);
                local avail = pw - 13 * u - pk - 18 * u - kw - iw;
                local txt = fit(msg, avail, SP);
                spaced(px + 13 * u + iw, y0 + ((ph - 5 * u) - lh()) / 2, txt, ncol, SP);
                -- the state bar
                local bx, by, bw = px + 11 * u, y0 + ph - 7 * u, pw - 28 * u;
                dl:AddRectFilled({ bx, by }, { bx + bw, by + 3 * u }, c32(TRACK, 0.9), 0);
                dl:AddRectFilled({ bx, by }, { bx + bw, by + 3 * u }, c32(tagc[1]), 0);
            else
                -- Hex link: the cut-corner plate
                local K = math.min((({ small = 4, medium = 7, large = 10 })[cfg.widget_cut] or 7) * u, H * 0.32);
                local p = { { x0 + K, y0 }, { x0 + W, y0 }, { x0 + W, y0 + H - K }, { x0 + W - K, y0 + H }, { x0, y0 + H }, { x0, y0 + K } };
                local pl = sch.plate;
                poly_fill(dl, p, lit and c32({ pl[1] + 0.03, pl[2] + 0.035, pl[3] + 0.03 }, sch.plate_a) or c32(pl, sch.plate_a));
                if lit then
                    poly_line(dl, p, c32({ 1.0, 0.80, 0.43 }, 0.22), 4 * u);
                    poly_line(dl, p, c32({ 1.0, 0.94, 0.78 }, 0.95), 1.4);
                else
                    poly_line(dl, p, c32(sch.edge, 0.45), 1);
                end
                if cfg.widget_gold then
                    local cc, ca = lit and { 1.0, 0.94, 0.78 } or { 1.0, 0.90, 0.62 }, lit and 1 or 0.6;
                    dl:AddLine({ x0, y0 + K }, { x0 + K, y0 }, c32(cc, ca), math.max(1.5, 2.0 * u));
                    dl:AddLine({ x0 + W - K, y0 + H }, { x0 + W, y0 + H - K }, c32(cc, ca), math.max(1.5, 2.0 * u));
                end

                -- keys before the divider, the name / status at the left
                local cut = x0 + (NAME_W + GAP / 2) * u;
                local kw = draw_keys(x0 + 12 * u + 20 * u, cut, y0 + H / 2);
                local iw = chest(x0 + 12 * u, y0 + H / 2);
                scale(NAME_PX);
                local txt = fit(msg, (NAME_W - 16) * u - kw - 12 * u - iw, SP);
                spaced(x0 + 12 * u + iw, y0 + H / 2 - lh() / 2, txt, ncol, SP);

                -- the slanted gold divider
                dl:AddLine({ cut + 3 * u, y0 + 3 * u }, { cut - 3 * u, y0 + H - 3 * u }, c32({ 1.0, 0.76, 0.34 }, 0.9), math.max(1, 0.9 * u));

                -- the job-box style tag
                tag_w, tag_h = TAG_W * u, TAG_H * u;
                tag_x, tag_y = x0 + (NAME_W + GAP) * u, y0 + (H - tag_h) / 2;
                local l, t, r, b = tag_x, tag_y, tag_x + tag_w, tag_y + tag_h;
                local kc, sl = 3 * u, 2.5 * u;
                local T = { { l + sl, t }, { r, t }, { r, b - kc }, { r - kc, b }, { l - sl, b } };
                poly_fill(dl, T, c32(tagc[1]));
                poly_line(dl, T, c32({ 0.04, 0.04, 0.055 }), 1);
                local i = 1.5 * u;
                poly_line(dl, { { l + sl + i, t + i }, { r - i, t + i }, { r - i, b - kc - i * 0.3 }, { r - kc - i * 0.3, b - i }, { l - sl + i * 1.2, b - i } },
                          c32(tagc[2], 0.8), 1);
                centred((l + r) / 2, (t + b) / 2, label, math.min(11, TAG_H * 0.55), c32(tagc[3]));
            end
            pcall(imgui.SetWindowFontScale, 1);

            -- the tag is the on / off switch; the plate drags the widget; right-click opens ChestMaster
            imgui.SetCursorScreenPos({ tag_x, tag_y });
            if imgui.InvisibleButton('##cm_wtag', { tag_w, tag_h }) then widget_toggle(); end
            if imgui.IsWindowHovered() then
                imgui.SetTooltip(('ChestMaster %s%s - Forbidden Keys: %s\nClick the tag: on / off (also frees you if stuck). Drag the plate to move. Right-click: settings.')
                    :fmt(cfg.enabled and 'ON' or 'OFF', cfg.auto_talk and ' (auto)' or '',
                         state.keys.id and tostring(state.keys.count) or '?'));
                if imgui.IsMouseClicked(1) then state.win.open[1] = true; end
            end
        end);
    end
    imgui.End();
    imgui.PopStyleColor(1);
    imgui.PopStyleVar(2);
end

local function draw_widget()
    if not cfg.show_widget then return; end
    if cfg.widget_theme == 'vex' or cfg.widget_theme == 'hex' then return draw_widget_yuna(); end
    local C = vc.colors;
    imgui.SetNextWindowPos({ 300, 300 }, ImGuiCond_FirstUseEver);
    imgui.PushStyleColor(ImGuiCol_WindowBg, C.bg);
    imgui.PushStyleColor(ImGuiCol_Border, C.line);
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 10);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 10, 6 });
    local flags = bit.bor(ImGuiWindowFlags_NoDecoration or 0, ImGuiWindowFlags_AlwaysAutoResize or 0,
                          ImGuiWindowFlags_NoFocusOnAppearing or 0, ImGuiWindowFlags_NoNav or 0);
    if imgui.Begin('ChestMaster pill###cm_widget', WIDGET_OPEN, flags) then
        vc.safe(function ()
            local v = vc.switch('w_en', 'ChestMaster', cfg.enabled);
            if v ~= nil then widget_toggle(); end
            imgui.SameLine();
            local job, now = state.job, os.clock();
            if not cfg.enabled then
                imgui.TextColored(C.bad, 'OFF');
            elseif job then
                imgui.TextColored(C.teal, 'working...');
            elseif state.pending_talk then
                imgui.TextColored(C.acc, 'talking to chest...');
            elseif state.flash and now < state.flash.until_t then
                imgui.TextColored(C.gold, esc(state.flash.text));
            else
                imgui.TextColored(C.good, cfg.auto_talk and 'ON (auto)' or 'ON');
            end
            imgui.SameLine();
            imgui.TextColored(C.dim, ('Keys %s'):fmt(state.keys.id and tostring(state.keys.count) or '?'));
            if imgui.IsWindowHovered() then
                imgui.SetTooltip('Click the switch to turn it on or off. Right-click: open ChestMaster.');
                if imgui.IsMouseClicked(1) then state.win.open[1] = true; end
            end
        end);
    end
    imgui.End();
    imgui.PopStyleVar(2);
    imgui.PopStyleColor(2);
end

ashita.events.register('d3d_present', 'cm_present', function ()
    run_sched();
    afk_check();
    tick();
    update_keys(false);
    draw_widget();
    vc.window(state.win, WIN);
end);

----------------------------------------------------------------------
-- AFK safety: what counts as you being at the keyboard
----------------------------------------------------------------------
ashita.events.register('key', 'cm_afk_key', function (e) mark_active(); end);           -- any key (press or release)
ashita.events.register('key_data', 'cm_afk_keydata', function (e)                       -- the game's own keyboard read
    if e and e.down and not e.injected then mark_active(); end
end);
ashita.events.register('mouse', 'cm_afk_mouse', function (e)                           -- a click or the wheel
    local m = e and (e.message or (e.type and e.type + 0x200)) or 0;
    if m > 0x200 and m <= 0x20E then mark_active(); end   -- not plain moves (0x200): only a real press counts
end);
ashita.events.register('xinput_button', 'cm_afk_xinput', function (e)                   -- controller
    if e and not e.injected and (e.state or 0) ~= 0 then mark_active(); end
end);
ashita.events.register('dinput_button', 'cm_afk_dinput', function (e)
    if e and not e.injected and (e.state or 0) ~= 0 then mark_active(); end
end);

----------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------
ashita.events.register('command', 'cm_command', function (e)
    mark_active();   -- any command counts as activity
    local args = e.command:args();
    if #args == 0 then return; end
    local cmd = args[1]:lower();
    if cmd ~= '/cm' and cmd ~= '/chestmaster' then return; end
    e.blocked = true;

    local sub = args[2] and args[2]:lower() or '';
    if sub == '' then
        state.win.open[1] = not state.win.open[1];
    elseif sub == 'on' or sub == 'off' then
        set_enabled(sub == 'on');
    elseif sub == 'toggle' then
        set_enabled(not cfg.enabled);
    elseif sub == 'auto' then
        cfg.auto_talk = not cfg.auto_talk; save();
        log('Auto-talk ' .. (cfg.auto_talk and 'ON.' or 'OFF.'));
    elseif sub == 'widget' or sub == 'pill' then
        cfg.show_widget = not cfg.show_widget; save();
        log('ON/OFF pill ' .. (cfg.show_widget and 'shown.' or 'hidden.'));
    elseif sub == 'last' then
        local l = state.last;
        if not l then log('No chest yet.'); return; end
        log(('%s chest: %s -> %s%s'):fmt(l.color, l.desc, ACT_NAMES[l.action], l.note and (' - ' .. l.note) or ''));
    elseif sub == 'unstick' then
        unstick(false);
        log('Releasing you from the menu/event. If still stuck, zone or /cm unstick again.');
    elseif sub == 'debug' then
        state.debug = not state.debug;
        log('Debug ' .. (state.debug and 'on.' or 'off.'));
    else
        log('Usage: /cm [on|off|toggle|auto|widget|last|unstick|debug]');
    end
end);

ashita.events.register('load', 'cm_load', function ()
    if not cfg.migrated_leave_skip then   -- Leave chests are skipped, not shown, during auto mode
        cfg.leave_show, cfg.migrated_leave_skip = false, true;
        save();
    end
    if not cfg.migrated_trace_off then   -- the trace was on while ChestMaster was being fixed: off now
        cfg.trace, cfg.migrated_trace_off = false, true;
        save();
    end
    if cfg.trace then
        local f = io.open(TRACE_FILE, 'w');
        if f then f:write(('ChestMaster %s trace, started %s\n'):fmt(addon.version, os.date())); f:close(); end
    end
    if not cfg.migrated_21 then   -- 2.1: skip the menu by default (2.0 left it on screen)
        cfg.hide_menu, cfg.migrated_21 = true, true;
        save();
    end
    if not cfg.migrated_22 then   -- 2.2: soothing light on a timer, as asked
        cfg.actions.soothing, cfg.migrated_22 = TIMED, true;
        save();
    end
    update_keys(true);
end);
ashita.events.register('unload', 'cm_unload', function () save(); end);
