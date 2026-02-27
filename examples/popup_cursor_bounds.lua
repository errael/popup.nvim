local function SF(fmt, ...)
    return string.format(fmt, ...)
end
local PR = vim.schedule_wrap(function(fmt, ...)
    vim.print(SF(fmt, ...))
end)

PR('=== start')
local Popup = require 'popup'
-- There are a variety of keybindings, at the end, to play with popop features.
--
-- popup_create options used: focusable, moved, filter, filtermode, close, minwidth,
--          minheight, drag, border, hidden, callback, col, line, zindex, highlight
--
-- When "moved = {x1,x2}", place cursor in one of these areas: "|-->...<--|"
--|-->               <--|   |-->               <--|   |-->               <--|      
-- and then ":source", and move cursor left/right, notice when cursor not
-- in an area or leaves an area, the associated popup closes
-- Drag popup by border. Use ":messages" to see output of callback and filter.

      -- -- -- Use "x" around the beginning of this line, filter_cb closes popup.

local popup_wid

local mev_map
-- see all_events.vim
mev_map = {
    ["\128\253\047"] = "<MiddleMouse>",
    ["\128\253\048"] = "<MiddleDrag>",
    ["\128\253\049"] = "<MiddleRelease>",
    ["\128\253\050"] = "<RightMouse>",
    ["\128\236\088"] = "<SgrMouseRelease>",
    ["\128\253\100"] = "<MouseMove>",
    ["\128\253\069"] = "<LeftMouseNM>",
    ["\128\253\070"] = "<LeftReleaseNM>",
    ["\128\237\088"] = "<SgrMouse>",
    ["\128\253\052"] = "<RightRelease>",
    ["\128\253\051"] = "<RightDrag>",
    ["\128\253\044"] = "<LeftMouse>",
    ["\128\253\045"] = "<LeftDrag>",
    ["\128\253\046"] = "<LeftRelease>",
}

local function filter_cb(win_id, key)
    PR("FILTER: win_id '%d', klen %d/%d, key '%s'",
        win_id, #key, vim.fn.strchars(key), mev_map[key] or key)
    --PR(debug.traceback())
    if key == "x" then
        Popup.close(win_id, 33)
        --vim.schedule(function() Popup.close(win_id, 33) end)
        return true
    end
    return false
end

local function popup_cb(win_id, result)
    --PR(debug.traceback())
    local bnr = vim.fn.winbufnr(win_id)
    local txt = I(vim.fn.getbufline(bnr, 1, 2))
    PR("popup_cb('%s', '%s', '%s')", win_id, I(result), txt)
    --PR(os.date('!%T') .. ': CALLBACK ' .. tostring(result))
end

--local xpos = 20
local xpos = 4
local ypos = 10
local zindex = 1000
local bounds_center = 20
local bounds_offset = -2
local function Pop1Any()

    bounds_offset = bounds_offset + 2

    local bounds = { bounds_center - bounds_offset, bounds_center + bounds_offset }
    local what = {SF('bounds adj 1: %d, %d', bounds[1]+1, bounds[2]+1), 'zindex: ' .. zindex}

    local opts = {
        --focusable = true,
        --moved = bounds,
        --moved = 'any',
        moved = {xpos-2, xpos+20},
        filter = filter_cb,
        filtermode = "n",
        --close = 'button',
        close = 'click',
        minwidth = 22,
        minheight = 4,
        drag = true,
        border = {},
        --hidden = true,
        callback = popup_cb,
        col = xpos,
        line = ypos,
        zindex = zindex,
        --highlight = "WildMenu",
    }
    -- if (zindex / 100) % 2 == 1 then
    --     opts.hidden = true
    -- end
    popup_wid = Popup.create(what, opts)
    -- next popup goes here
    --xpos = xpos + 6
    xpos = xpos + 26
    ypos = ypos + 6
    zindex = zindex + 100
    what[#what+1] = SF("wid: %d", popup_wid)
    local bnr = vim.fn.winbufnr(popup_wid)
    vim.api.nvim_buf_set_lines(bnr, 0, -1, true, what)
end

local function win_state()
    local st = vim.api.nvim_win_get_config(popup_wid)
    --PR("WIN STATE: focusable: %q, mouse %q", st.focusable, st.mouse)
    PR("WIN: WxH: %dx%d, border: '%s'", st.width, st.height, I(st.border))
    --PR("    %s", I(st))
    PR(I(Popup.getpos(popup_wid)))
end

Pop1Any()
Pop1Any()
Pop1Any()

-- KEYBINDINGS
--   many of the keybindings use "popup_wid" which is the last popup created.

--vim.keymap.set('n', 'E', function() vim.fn.win_gotoid(popup_wid) end)
vim.keymap.set('n', 'E', function() vim.fn.win_gotoid(Popup.list()[1]) end)

vim.keymap.set('n', 'Z0', win_state)
vim.keymap.set('n', 'Z1', function() PR(I(vim.api.nvim_list_wins())) end)
vim.keymap.set('n', 'Z2', function() vim.api.nvim_set_current_win(popup_wid) end)
--vim.keymap.set('n', 'Z3', ":call nvim_set_current_win(" .. popup_wid .. ")<CR>")

vim.keymap.set('n', 'Z4', function() Popup.show(popup_wid) end)
vim.keymap.set('n', 'Z5', function() Popup.hide(popup_wid) end)

vim.o.tm = 5000

vim.keymap.set('n', 'Z', function() PR("popups: %s", I(Popup.list())) end)
vim.keymap.set('n', 'V', function() Popup.clear(false) end)

--filter_cb(1234, "foobar")

-- for k,v in pairs(mev_map) do
--     PR("k %s(%s), v %s(%s)",
--         I(k), type(k), I(v), type(v))
-- end
