local function SF(fmt, ...)
    return string.format(fmt, ...)
end
local PR = vim.schedule_wrap(function(fmt, ...)
    vim.print(SF(fmt, ...))
end)

vim.print('=== start')
local Popup = require 'popup'
-- Check the "mapping = false" option which disables key mapping when 
-- popup is active. Note that "Z1" is mapped to print the active windows.
--
-- After ":sou" this file, enter "Z1" and see that the filter printf "Z", "1".
-- Close the popup, enter "Z1", see that the mapping executes.
-- Can edit this file to comment out the "mapping = false", so default of true
-- is in effect, then ":source" this file and see that the mapping happens.

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

-- for k,v in pairs(mev_map) do
--     local s = mev_map[k]
--     local s2l = vim.fn.str2list(k)
--     l"\128\253\044"ocal l2s = vim.fn.list2str(s2l)
--     PR("DUMP: key '%s', s2l '%s', l2s '%s', mapped '%s'",
--         k, I(s2l), l2s, s)
-- end

local function filter_cb(win_id, key)
    --PR("filter_cb")
    -- local len = 0
    -- for _ in key:gmatch(".") do
    --     len = len + 1
    -- end
    -- local xxx
    -- xxx.foo = 3
    PR("FILTER: win_id '%d', klen %d/%d, key '%s'", win_id, #key, vim.fn.strchars(key), mev_map[key] or key)
    -- local s = mev_map[key]
    -- local s2l = vim.fn.str2list(key)
    -- local l2s = vim.fn.list2str(s2l)
    -- PR("FILTER: win_id '%d', key '%s', s2l '%s', l2s '%s', mapped '%s'",
    --     win_id, key, I(s2l), l2s, s)
    if key == "x" then
        Popup.close(win_id, 33)
        --vim.schedule(function() Popup.close(win_id, 33) end)
        return true
    end
    return false
end

local function popup_cb(win_id, result)
    local bnr = vim.fn.winbufnr(win_id)
    local txt = vim.inspect(vim.fn.getbufline(bnr, 1, 2))
    vim.print(string.format("popup_cb('%s', '%s', '%s')", win_id, vim.inspect(result), txt))
    --vim.print(os.date('!%T') .. ': CALLBACK ' .. tostring(result))
end
              -- -- -- Use "x" around the beginning of this line
local xpos = 40
local ypos = 10
local function Pop1Any()
    popup_wid = Popup.create({'simplex', 'twotwox'}, {
        filter = filter_cb,
        filtermode = "n",
        mapping = false,    -- don't map the characters

        close = 'button',
        drag = 'true',
        border = {},
        --hidden = true,
        callback = popup_cb,
        col = xpos,
        line = ypos,
        --focusable = true,
    })
    xpos = xpos + 3
    ypos = ypos + 3
    --local bnr = vim.fn.winbufnr(popup_wid)
    --vim.keymap.set({'n', 'i'}, '<LeftRelease>', mouse_click)
    --vim.keymap.set({'n', 'i'}, '<LeftRelease>', mouse_click, {buffer = bnr})
end
--vim.keymap.set({'n', 'i'}, '<LeftRelease>', mouse_click)

local function win_state()
    local st = vim.api.nvim_win_get_config(popup_wid)
    --vim.print(string.format("WIN STATE: focusable: %q, mouse %q", st.focusable, st.mouse))
    vim.print(string.format("WIN: WxH: %dx%d, border: '%s'", st.width, st.height, vim.inspect(st.border)))
    --vim.print(string.format("    %s", vim.inspect(st)))
    vim.print(vim.inspect(Popup.getpos(popup_wid)))
end

vim.keymap.set('n', 'Z0', win_state)
vim.keymap.set('n', 'Z1', function() vim.print(vim.inspect(vim.api.nvim_list_wins())) end)
vim.keymap.set('n', 'Z2', function() vim.api.nvim_set_current_win(popup_wid) end)
--vim.keymap.set('n', 'Z3', ":call nvim_set_current_win(" .. popup_wid .. ")<CR>")

vim.keymap.set('n', 'Z4', function() Popup.show(popup_wid) end)
vim.keymap.set('n', 'Z5', function() Popup.hide(popup_wid) end)

vim.o.tm = 5000

vim.keymap.set('n', 'Z', function() PR("popups: %s", vim.inspect(Popup.list())) end)
vim.keymap.set('n', 'V', function() Popup.clear(false) end)

Pop1Any()

--filter_cb(1234, "foobar")

-- for k,v in pairs(mev_map) do
--     vim.print(string.format("k %s(%s), v %s(%s)",
--         vim.inspect(k), type(k), vim.inspect(v), type(v)))
-- end
