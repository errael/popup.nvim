vim.print('=== start')
-- Exercise Popup.move on a timer.
local Popup = require 'popup'

local winnr = vim.fn.winnr
local msgs = {}
local function add_msg(msg)
    table.insert(msgs, os.date('!%T') .. ': ' .. msg)
end
--              |      | | |
--              |      | | |
--              |      | | |
--              |      | | |
--              |      | | |
--              |      | | |
--              |      | | |
--              |      | | |

local popup_wid


local wnr = winnr()

local function get_mp(tag)
    local mp = vim.fn.getmousepos()
    vim.print(string.format("MOUSE %s: line %d, col %d, wid %d, winrow %d, wincol %d",
              tag, mp.screenrow, mp.screencol, mp.winid, mp.winrow, mp.wincol))
    return mp
end

local callback_result
local popup_cb
local mouse_click

local xpos = 20
local ypos = 10
local function Pop1Any()
    local popup_opts = {
	--moved = 'any',
	focusable = false,
	close = 'click',
	callback = popup_cb,
        minwidth = 30,
        minheight = 4,
	col = xpos,
	line = ypos,
        drag = true,
        --dragall = true,
        border = {1, 0, 0, 0},
        padding = {2, 2, 2, 2},
    }

    popup_wid = Popup.create({'simple', 'onetwo'}, popup_opts)
    vim.api.nvim_buf_set_lines(vim.api.nvim_win_get_buf(popup_wid), 0, -1, true,
                                {'simple', '=' .. tostring(popup_wid) .. '='})
    return popup_wid
end
--vim.keymap.set({'n', 'i'}, '<LeftRelease>', function() mouse_click("CLICK") end)
vim.o.tm = 5000
vim.keymap.set('n', 'YYY', ':echom "ABC"<CR>')

Pop1Any()
--SFP("getpos: %s", I(Popup.getpos(popup_wid)))

popup_cb = function(win_id, result)
    local bnr = vim.fn.winbufnr(win_id)
    local txt = vim.inspect(vim.fn.getbufline(bnr, 1, 2))
    vim.print(string.format("popup_cb('%s', '%s', '%s')", win_id, vim.inspect(result), txt))
    get_mp('callback mp')
    --vim.print(os.date('!%T') .. ': CALLBACK ' .. tostring(result))
    callback_result = result
    popup_wid = nil
end

mouse_click = function(tag)
    local mp = get_mp(tag)
    if tag == "buffer" then
	local ok, msg = pcall(Popup.close, mp.winid)
	if not ok then
	    vim.print(vim.inspect(msg))
	end
    end
end

local current_pos = vim.api.nvim_win_get_position(popup_wid)
--vim.print(string.format("current_pos: %s", vim.inspect(current_pos)))

local timer = vim.uv.new_timer()
timer:start(
    1000,
    1000,
    vim.schedule_wrap(function()
        --if true then timer:stop() return end
        if popup_wid then
            ypos = ypos + 2
            --Popup.move(popup_wid, {line = ypos,})
            xpos = xpos + 2
            Popup.move(popup_wid, {col = xpos, line = ypos,})
        else
            timer:stop()
        end
    end)
)


add_msg('Exit ' .. vim.inspect(callback_result))
--vim.print(vim.inspect(msgs))

