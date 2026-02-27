--- popup.lua
---
--- Wrapper to make the popup api from vim in neovim.
--- Hope to get this part merged in at some point in the future.
---
--- Please make sure to update "POPUP.md" with any changes and/or notes.

-- TODO: CLEANUP
--      get rid of dummy_filter

-- TODO: Is there a way to do this without "full path"?
local utils = require "popup.utils"

local function SF(fmt, ...)
    return string.format(fmt, ...)
end
local PR = vim.schedule_wrap(function(fmt, ...)
    vim.print(SF(fmt, ...))
end)

-- Some debug print/output helpers
--require "plenary.popup.my_log"

-- TODO: local bit = require("bit")

-- TODO: determine/use extras.hidden instead of vim.api.nvim_win_get_config(win_id).hide

local if_nil = vim.F.if_nil

local popup = {}
-- Use the following for local functions to avoid forward reference
-- and better popup descriptions with normal mode "K".
local L = {}

local function log_dispatch(s, ...)
  --PR(s, ...)
end

local function llog(s, ...)
  PR(s, ...)
end

-- debug options
popup._debug = {
  show_mev = false
}

-- translate vim's "pos" to neovim's "anchor".
-- Include x/y (col/row) adjust becacuse nvim's anchor is a point, not a cell.
popup._pos_map = {
  topleft = {"NW", 0, 0},
  topright = {"NE", 1, 0},
  botleft = {"SW", 0, 1},
  botright = {"SE", 1, 1},
}

local neovim_passthru = {
  "title",
  "title_pos", -- nevim only
  "footer", -- nevim only
  "footer_pos", -- nevim only
}

----------------------------------------------------------------------------------
-- TODO:  Some state is saved when set through this interface.                  --
--        NeedToDocument: changes made to window parameters not throught popup  --
--        may interfere with correct operation.                                 --
----------------------------------------------------------------------------------

-- TODO: OPTIM: get rid of pup.extras and just put the stuff in pup?

-- State info of each active popup; each entry is a table for the given popup.
-- Use win_id as key to check if win_id is an active popup.

---@alias WinOpts {} options passed to nvim_open_win

-- TODO: define the neovim window options
-- TODO: where applicable, define string literals that are valid
-- VimOpts could be superclass of options for popup_setoptions()
--{} popup create/config options
---@class PopupOptsVim
---@field line integer
---@field col integer
---@field pos string
---@field maxheight integer
---@field minheight integer
---@field maxwidth integer
---@field minwidth integer
---@field _width integer        -- used internally
---@field _height integer       -- used internally
---@field hidden boolean
---@field wrap boolean
---@field drag boolean
---@field dragall boolean
---@field close string
---@field highlight string
---@field padding integer[]
---@field border string|integer[]
---@field borderchars string[]
---@field zindex integer
---@field time integer
---@field moved string|integer[]
---@field mousemoved string|integer[]
---@field cursorline boolean
---@field filter function
---@field mapping boolean
---@field filtermode string
---@field callback function

---These options are defined by |nvim_open_win|
---@class PopupOptsNeovim: PopupOptsVim
---@field noautocmd boolean
---@field enter boolean
---@field focusable boolean 

---PosBounds is [lnum, start_col, end_col]
---@alias PosBounds [integer, integer, integer]

---@class (exact) Extras
---@field line_count integer    TODO: this probably needs to be dynamic
---@field border_thickness [integer, integer, integer, integer]
---@field padding [integer, integer, integer, integer]
---@field button_close_pad integer for checking if mouse on "X" button
---@field filter function popup's filter, may be "dummy_filter"
---@field moved_bounds PosBounds
---@field mousemoved_bounds PosBounds
---@field mapping boolean

---@class (exact) Pup
---@field win_id integer self reference, used to index popup._popups
---@field vim_options PopupOptsVim popup create/config options
---@field result any value passed to close callback
---@field extras Extras
---@field callback nil|function(id?:integer, result?:any)

---@alias PopupId integer The window id of a popup
---@type table<PopupId, Pup>
popup._popups = {}
-- TODO:  Currently _popups only key with win_id, but there's "if type(win_id) == "number";
--        get rid of the unneeded test.

local on_key_ns_id      ---@type integer?
local sorted_visible_popup_list = {}    ---@type integer[]
local maps = {}

--TODO: REMOVE FUNCTION
local function run_pup(win_id, fn)
  local pup = popup._popups[win_id]
  if pup then
    fn(pup)
  end
  return pup
end

---@param bounds PosBounds
---@return boolean true if bounds
local function is_bounds(bounds)
  return bounds ~= nil
    and (type(bounds) ~= "table" or bounds[1] ~= 0 or bounds[2] ~= 0 or bounds[3] ~= 0)
end

---@param bounds PosBounds
local function is_nil_bounds(bounds)
  return not is_bounds(bounds)
  -- return bounds == nil
  --   or type(bounds) == "table" and bounds[1] == 0 and bounds[2] == 0 and bounds[3] == 0
end

--TODO: REMOVE FUNCTION
---@param win_id integer
---@param key string
---@return boolean constant false, key is not discarded
local function dummy_filter(win_id, key)
  _,_ = win_id,key
  --llog("dummy filter: dummy")
  return false
end

-- TODO: may want to set a re_filter flag indicating a new filter should be constructed
-- TODO: does this need to be "scheduled"?

-- This is called after a popup is created or changed. Information is
-- re-created as needed.
--          - re-create list of visible popup sorted by zindex (primarily for filtering)
--          - turn 'mousemoveevent' on/off with adjust_need_mouse_move
--          - create/destroy vim.on_key() as needed
--          - create filter trampoline for specified win_id
---@param win_id integer? The config of the specified popup is changed
local function significant_popup_change(win_id)
  if win_id then
    local pup = popup._popups[win_id]
    local vim_options = pup.vim_options

    --pup.extras.filter = dummy_filter
    pup.extras.filter = nil

    -- Only a visible popup needs a filter. Note must use popup.hide/show.
    local hidden = vim.api.nvim_win_get_config(win_id).hide

    pup.extras.mapping = true
    if not hidden and vim_options.filter then
      local mapping = not (vim_options.mapping == false)
      pup.extras.mapping = mapping
      pup.extras.filter = L.create_bounce_to_filter(pup, mapping)
    end
  end

  local need_mousemev
  local disable_mapping
  sorted_visible_popup_list = popup.list()
  --llog("SORT-PRE: %s", I(sorted_visible_popup_list))
  local idx = 1
  while idx <= #sorted_visible_popup_list do
    local idx_win_id = sorted_visible_popup_list[idx]
    local pup = popup._popups[idx_win_id]
    if is_bounds(pup.extras.mousemoved_bounds) then
      need_mousemev = true
    end
    local hidden = vim.api.nvim_win_get_config(idx_win_id).hide
    if hidden then
      table.remove(sorted_visible_popup_list, idx)
    else
      -- if pup.vim_options.filter then
      --   need_on_key = true
      -- end
      -- a visible popup with a filter
      if not pup.extras.mapping then
        disable_mapping = true
      end
      idx = idx + 1
    end
  end
  L.adjust_need_mouse_move(need_mousemev)

  -- Ensure there's an on_key handler if there is any popup.
  -- TODO: OPTIM minor: An active popup may not require a key handler; but too messy.
  if #sorted_visible_popup_list > 0 then
    --llog("on_key Dispatcher: ON: %s, n active %d", on_key_ns_id, vim.on_key())
    local opts = disable_mapping and { mapping = false} or {}
    --if not on_key_ns_id then
    --  on_key_ns_id = vim.on_key(L.on_key_local_dispatch, nil, opts)
    --end
    on_key_ns_id = vim.on_key(L.on_key_local_dispatch, on_key_ns_id, opts)
  else
    --llog("on_key Dispatcher: OFF: %s, n active %d", on_key_ns_id, vim.on_key())
    vim.on_key(nil, on_key_ns_id)
    on_key_ns_id = nil
  end

  if #sorted_visible_popup_list > 1 then
    table.sort(sorted_visible_popup_list, function(win_a, win_b)
      return popup._popups[win_a].vim_options.zindex > popup._popups[win_b].vim_options.zindex
    end)
  end
  --llog("SORT: %s", I(sorted_visible_popup_list))
  if not win_id then
    return
  end


  -- local pup = popup._popups[win_id]
  -- local vim_options = pup.vim_options

  -- pup.extras.filter = dummy_filter

  -- -- Only a visible popup needs a filter. Note must use popup.hide/show.
  -- local hidden = vim.api.nvim_win_get_config(win_id).hide

  -- if not hidden and vim_options.filter then
  --   local allow_mapping = not (vim_options.mapping == false)
  --   pup.extras.filter = L.create_bounce_to_filter(pup, allow_mapping)
  -- end
end

-- ===========================================================================
--
-- popup mouse event handling
--

---@type boolean? (tristate) nil - popup not using; saved state without popup
local mouse_mev
---@type integer
local mev_au_id

---Turns &mousemoveevent on/off; track external changes.
---
---@param need boolean
function L.adjust_need_mouse_move(need)
  --llog("adjust_need_mouse_move: need %s, mouse_mev: %s", need, mouse_mev)
  if need then
    -- only save if nothing has been saved
    if mouse_mev == nil then
      mouse_mev = vim.o.mousemoveevent
      vim.o.mousemoveevent = true
      -- track any changes made outside of popup
      mev_au_id = vim.api.nvim_create_autocmd("OptionSet", {
        pattern = "mousemoveevent",
        callback = function()
          local new_mev = vim.v.option_new
          --llog("MevAU change: mouse_mev: %s, new_val: %s, id %d", mouse_mev, new_mev, mev_au_id)
          assert(mouse_mev ~= nil, "mouse_mev should not be nil")
          mouse_mev = new_mev ~= 0 and new_mev ~= false
          -- make sure it's on
          if new_mev == false then
            vim.schedule(function() vim.api.nvim_cmd({
              cmd = "set", args = { "mousemoveevent" }, mods = { noautocmd = true, }
            }, {}) end)
          end
        end,
      })
      --llog("MevAU start: mouse_mev: %s, id %d", mouse_mev, mev_au_id)
    end
    --vim.o.mousemoveevent = true
  else
    if mouse_mev ~= nil then
      local mev = mouse_mev
      local id = mev_au_id
      vim.schedule(function()
        --llog("MevAU end: mouse_mev: %s, id %d", mev, id)
        vim.api.nvim_del_autocmd(id)
        vim.o.mousemoveevent = mev
      end)
      mouse_mev = nil
    end
  end
end

-- which buttons are pressed
local pressed_buttons = {}
local function adjust_pressed_buttons(event)
  local btn_event = maps.mouse_events[event]
  if not btn_event then
    return
  end
  if not btn_event.is_drag then
    if btn_event.is_click then
      pressed_buttons[btn_event.button] = true
    else
      pressed_buttons[btn_event.button] = nil
    end
  end
end

local function count_pressed_buttons()
  local n = 0
  for _ in pairs(pressed_buttons) do
    n = n + 1
  end
  return n
end

-- The id of the popup window that has the mouse locked.
local mouse_win_id
local count_mousemoved = 0

-- Assign mouse events to a window, then send it on.
-- Ignore keystrokes that are not mouse related.
-- Discovers "fresh_click"s; a click when no buttons are currently pressed.
-- A fresh_click establishes a "current_popup" using getmousepos(), and all mouse
-- events are sent to that popup until the next fresh_click.

---@return boolean true to discard key
local function mouse_dispatch(typed)

  -- TODO: take care of multi-click events? vim doesn't

  if typed:byte() ~= 128 then
    return false
  end

  local mouse_event = maps.key2mouse[typed]
  --log_dispatch("popup: mouse_dispatch: typed '%s', mouse_event: '%s'", typed, mouse_event)
  if not mouse_event then
    --log_dispatch("mouse_dispatch: not mouse_event, typed %s, ret false",  typed)
    return false
  end

  -- TODO: put this at top of fn, compare: typed == "\128\253\100"
  if popup._debug.show_mev and mouse_event == "<MouseMove>" then
    count_mousemoved = count_mousemoved + 1
    llog("<MouseMove> %d: mouse_mev %s", count_mousemoved, mouse_mev)
  end
  if mouse_mev ~= nil and mouse_event == "<MouseMove>" then
    local mp
    local close_these
    for win_id, _ in pairs(popup._popups) do
      if type(win_id) == "number" then
        local bounds = popup._popups[win_id].extras.mousemoved_bounds
        --if not is_bounds(bounds) then
        --  llog("MOUSE OOB NIL-BOUNDS: bounds = %s, current l=%s, c=%s", I(bounds), vim.fn.getmousepos().winrow, vim.fn.getmousepos().wincol)
        --end

        if is_bounds(bounds) then
          mp = mp or vim.fn.getmousepos()
          if bounds == "prime" then
            local pup = popup._popups[win_id]
            bounds = L.parse_moved_option(
              pup.vim_options.mousemoved, mp.winrow, mp.wincol, true)
            pup.extras.mousemoved_bounds = bounds
            --llog("MOUSE OOB INIT-BOUNDS: bounds = %s, current l=%s, c=%s", I(bounds), mp.winrow, mp.wincol)
          end
          local lnum = mp.winrow
          local col = mp.wincol
          --llog("MOUSE OOB: l=%s, minc=%s, maxc=%s, current l=%s, c=%s", bounds[1], bounds[2], bounds[3], lnum, col)
          if lnum ~= bounds[1] or col < bounds[2] or col > bounds[3] then
            if not close_these then
              close_these = { win_id }
            else
              close_these[#close_these+1] = win_id
            end
          end
        end
      end
    end
    if close_these then
      for _,win_id in ipairs(close_these) do
        popup.close(win_id)
      end
    end
  end

  local fresh_click = count_pressed_buttons() == 0
  adjust_pressed_buttons(mouse_event)
  --log_dispatch("popup: mouse_dispatch: %s: n_pressed %d, btns %s, fresh %s",
  --  mouse_event, count_pressed_buttons(), vim.inspect(pressed_buttons, {newline=""}), fresh_click)
  local mp
  if fresh_click then
    mp = vim.fn.getmousepos()
    --log_dispatch("popup: mouse_dispatch: %s: fresh:  mp %s", mouse_event, I(mp))
    mouse_win_id = mp.winid
  end

  if not popup._popups[mouse_win_id] then
    log_dispatch("mouse_dispatch: no pup, id %s, event %s, ret false", mouse_win_id, mouse_event)
    mouse_win_id = nil
    return false
  end
  if not mp then
    mp = vim.fn.getmousepos()
  end

  --log_dispatch("popup: mouse_dispatch: %s: n_pressed %d, btns %s, fresh %s",
  --  mouse_event, count_pressed_buttons(), vim.inspect(pressed_buttons, {newline=""}), fresh_click)

  local ret = L.mouse_cb(mouse_win_id, mouse_event, mp, fresh_click)
  --log_dispatch("mouse_dispatch: id %d, event %s, cb_ret %s, ret %s", mouse_win_id, mouse_event, ret, not ret)
  return not ret

  --retrn not mouse_cb(mouse_win_id, mouse_event, mp, fresh_click)
end

---First dispatch mouse events to popups and then keys to popup filters.
---It's like a window manager. Only when "use_local_dispatch" is true.
---
---@param key string
---@param typed string
---@return string? # use empty string to discard the key (see on_key proposed extension)
L.on_key_local_dispatch = function(key, typed)
  local discard = nil
  -- TODO: take into account "disable_mapping". Set a global in significant_popup_change.
  --local mouse_event = maps.key2mouse[key]
  local special_key = key:byte() == 0x80
  llog("ON_KEY_LOCAL_DISPATCH %s, %s, %s", key, typed, I(special_key))
  if special_key then
    llog("ON_KEY_LOCAL_DISPATCH: mouse_dispatch")
    --discard = mouse_dispatch(typed)
    if mouse_dispatch(typed) then
      discard = ""
    end
  end
  --TODO: currently if key starts with 0x80,
  --      not passed to filter even if not consumed or not discarded
  -- don't need "and not discard" in following
  -- if not discard then
  --TODO/BUG/TEST: check against vim's popup-filter help
  --        "mouse click arrives as <LeftMouse>"
  --        "Keys coming from a :normal command do not pass..."
  --        "Keys coming from feedkeys()..."
  --        "If the filter function can't be called...close"
  --        and more
  if not special_key then
    llog("ON_KEY_LOCAL_DISPATCH: filter_dispatch")
    -- discard = L.filter_dispatch(key, typed) and ""
    if L.filter_dispatch(key, typed) then
      discard = ""
    end
  end
  return discard
end


local mp_press  -- mousepos when press
local drag_start_win_x
local drag_start_win_y
local window_drag_ok = nil   -- set by "<LeftMouse>"
local is_window_drag = nil   -- nil no drag events; false not dragging a popup

---The mouse event is associated with a popup.
---Could be a fresh click or locked to a popup.
---
---@param win_id_press integer
---@param event string
---@param mp table
---@param fresh_click boolean
---@return boolean true to propogate/continue event/processing (see nvim_open_win)
function L.mouse_cb(win_id_press, event, mp, fresh_click)
  local msg = ""
  local function output_msg(msgx)
    if not msgx then msgx = msg end
    --llog("popup: mouse_cb: %s: '%s'", event, msgx)
  end

  local pup

  -- is the mouse press on a border
  local function on_border()
    -- Need to check each edge separately
    local win_pos = popup.getpos(win_id_press)
    local on_edge = {} -- do in top/left/bot/right
    on_edge[#on_edge+1] = mp_press.screenrow == win_pos.line
    on_edge[#on_edge+1] = mp_press.screencol == win_pos.col + win_pos.width - 1
    on_edge[#on_edge+1] = mp_press.screenrow == win_pos.line + win_pos.height - 1
    on_edge[#on_edge+1] = mp_press.screencol == win_pos.col
    local thickness = pup.extras.border_thickness
    local border_drag_ok = false
    for i = 1, 4 do
      if on_edge[i] and thickness[i] ~= 0 then
        border_drag_ok = true
        break;
      end
    end
    --llog("border_drag_ok %s. edge %s, border %s",
    --    border_drag_ok, I(on_edge), I(pup.extras.border_thickness))
    return border_drag_ok
  end

  --local mp = vim.fn.getmousepos()

  if event == "<LeftMouse>" then
    -- Note that only consume if draggable. The idea is that click/release might
    -- be used by other things. At the time of the click, don't know if the popup
    -- would use it.
    window_drag_ok = false
    if fresh_click then
      --win_id_press = mp.winid
      pup = popup._popups[win_id_press]
      mp_press = mp
      is_window_drag = nil

      if pup.vim_options.dragall or pup.vim_options.drag and on_border() then
        window_drag_ok = true
      end

      output_msg(SF("fresh-1: id_press %d, drag_ok %s, %s", win_id_press, window_drag_ok, I({mp.screencol, mp.screenrow})))
      -- popup: mouse_cb: <LeftMouse>: '{ 30, 16 }'
      local xx = popup.getpos(win_id_press)
      output_msg(SF("fresh-2: x,y (%d,%d) w,h (%d,%d)",xx.col, xx.line, xx.width, xx.height))
      -- popup: mouse_cb: <LeftMouse>: 'x,y (20,10) w,h (11,7)'
    else
      msg = "ignoring LeftMouse because not fresh_click"
    end

    output_msg("consume")
    return false -- don't propogate, consume
    --return not window_drag_ok -- propogate if not draggable, otherwise consume

  elseif win_id_press then
    pup = popup._popups[win_id_press]
  end

  if not pup then
    output_msg("propogate")
    return true   -- propogate, don't consume
  end

  if event == "<LeftRelease>" then
    -- If is_window_drag is nil then the mouse hasn't moved since the mouse press.
    if is_window_drag == nil then
      if pup.vim_options.close == "click" then
        popup.close(pup.win_id, -2)
      elseif pup.vim_options.close == "button" and pup.extras.button_close_pad ~= nil
            and mp.winrow == 1
            and mp.wincol == (vim.api.nvim_win_get_width(pup.win_id)
                          + pup.extras.button_close_pad) then
        popup.close(pup.win_id, -2)
      end
    end
      --llog("popup: button: %s: %d %d",
      --    event, mp.wincol, vim.api.nvim_win_get_width(pup.win_id))

    -- cautious
    window_drag_ok = nil
    is_window_drag = nil
    output_msg("propogate")
    -- return false
    return true   -- propogate
  end

  -- (x,y) distance from "loc" to mouse pos; loc default to mp_press
  ---@param loc? table as returned from mousepos, only screencol/screenrow used
  local function delta(loc)
    loc = loc or mp_press
    if loc == nil then
      return 123456, 123456
    else
      return mp.screencol - loc.screencol, mp.screenrow - loc.screenrow
    end
  end

  -- note: win_id_press should be something
  if event == "<LeftDrag>" then
    if is_window_drag == nil then
      -- first drag event since press
      -- if pup.vim_options.dragall or pup.vim_options.drag and on_border() then
      if window_drag_ok then
        is_window_drag = true
        drag_start_win_x,drag_start_win_y = popup._getxy(win_id_press)
      else
        is_window_drag = false
      end
    end
    output_msg(SF("is_window_drag %s", is_window_drag))
    if is_window_drag == false then
      output_msg("propogate")
      return true
    end
    local x,y = delta()
    popup.move(win_id_press, {col = x + drag_start_win_x, line = y + drag_start_win_y})
    output_msg(SF("(%d,%d) (%d, %d) %d", x, y,
                        x + drag_start_win_x, y + drag_start_win_y, mp.winid))
    output_msg("consume")
    return false
  end
  output_msg("consume")
  return false
end

-- ===========================================================================
--
-- popup filter handling
--

---Iterate through popups (assumed in zindex order) and invoke
---their filter (may be a dummy filter). Stop if key is discarded.
---
---@param key string
---@param typed string
---@return boolean true to discard the key (see on_key proposed extension)
function L.filter_dispatch(key, typed)

  -- TODO: loop on the characters
  -- TODO: see rupt.vim, note that the filter gets the result of
  --        the mapped characters, not the typed characters
  --        unless mapping is false.

  local discard = false
  -- send the typed key to filters, check in z order
  local pups = sorted_visible_popup_list
  for _, win_id in ipairs(pups) do
    --local pup = popup._popups[win_id]
    --discard = pup.extras.filter(key, typed)
    local filter = popup._popups[win_id].extras.filter
    discard = filter and filter(key, typed)
    --llog("filter_dispatch: not mouse_event, win_id %d, key %s, typed %s, discard %s", win_id, key, L.k2m(typed), discard)
    if discard then
      break
    end
  end
  return discard
end

-- This is about creating an efficient function to look at state when a key
-- is pressed and see if the popup's filter should be called.
-- Note that there is only one on_key handler; see filter_dispatch.

-- Check if current mode is specified in filtermode
--    1. Convert the return of "mode()" to a single char mode as used in filtermode.
--    2. If single char found check against filtermode 
--    3.    Check if found
local function mode_match(filtermode_match)
  local current_mode = vim.fn.mode()
  -- string.find(xxx, current_mode) == 1
  local short_mode = maps.mode_to_short_mode[current_mode]
  -- TODO: Not sure there's a good fix for the possibility that new modes may b added.
  -- If it's a new mode not handled then just use the first character.
  short_mode = short_mode or current_mode:sub(1,1)
  return filtermode_match:find(short_mode) ~= nil
end

---Convert a filtermode designation, to unique modes.
---Basically, if filtermode has an "v", then add "x" and "s" to the mode
---@param filtermode string specified by popup configuration
---@return string filtermode to check for filter dispatch
local function convert_to_mode_match_string(filtermode)
  return filtermode .. (filtermode:find("v") and "xs" or "")
end

---Create a filter dispatcher that takes "on_key" arguments and if conditions
---are appropriate, invoke the popup's filter.
---@param pup Pup
---@param mapping boolean
---@return fun(key:string, typed:string):boolean #may forward on_key cb to popup's filter
function L.create_bounce_to_filter (pup, mapping)
  local win_id = pup.win_id
  local filter = pup.vim_options.filter
  local filtermode = pup.vim_options.filtermode
  -- TODO: could have 4 cases since "mapping" is constant while on_key fn lives.
  -- TODO: I think construct string and then "loadstring" for optimal...
  if not filtermode or string.find(filtermode, "a") then
    -- Since all modes, just invoke the filter.
    return function(key, typed)
      local filter_key = mapping and key or typed
      if #filter_key ~= 0 then
        return filter(win_id, filter_key)
      else
        return false
      end
    end
  else
    local filtermode_match = convert_to_mode_match_string(filtermode)
    -- Only invoke the filter if the right mode.
    return function(key, typed)
      local filter_key = mapping and key or typed
      if mode_match(filtermode_match) and #filter_key ~= 0 then
        return filter(win_id, filter_key)
      else
        return false
      end
    end
  end
end

local function dict_default(options, key, default)
  if options[key] == nil then
    return default[key]
  else
    return options[key]
  end
end

-- ===========================================================================
--
-- popup close handling
--

-- TODO: OPTIM: have a single cursor move aucmd and search the popups???

-- Convert vim_options.[mouse]moved to PosBounds.
-- The "adj" values for the cursor column index bounds
-- are determined by observation so works like vim.
---@return PosBounds
function L.parse_moved_option(opt_val, cur_row, cur_col, is_mousemoved)
  -- initialize to no bounds
  local bounds = { 0, 0, 0 }
  if not is_nil_bounds(opt_val) then
    local adj = is_mousemoved and 3 or 1

    local ok
    if opt_val == "any" then
      bounds = { cur_row, cur_col, cur_col }
      ok = true
    elseif type(opt_val) == "table" then
      if #opt_val == 2 then
        bounds = { cur_row, opt_val[1] + adj, opt_val[2] + adj }
        ok = true
      elseif #opt_val == 3 then
        bounds = { opt_val[1], opt_val[2] + adj, opt_val[3] + adj }
        ok = true
      end
    end
    assert(ok, string.format("invalid argument: %s", vim.inspect(opt_val)))
  end
  return bounds
end

local function do_close_window_for_cursor_aucmd(win_id)
  local augroup = "popup_window_" .. win_id
  pcall(vim.api.nvim_del_augroup_by_name, augroup)
  popup.close(win_id, -1)
end

--- Closes the popup window
--- Adapted from vim.lsp.util.close_preview_autocmd
---
---@param win_id integer window id of popup window
---@param bufnrs table|nil optional list of ignored buffers
local function close_window_for_aucmd(win_id, bufnrs)
  vim.schedule(function()
    -- exit if we are in one of ignored buffers
    if bufnrs and vim.list_contains(bufnrs, vim.api.nvim_get_current_buf()) then
      return
    end

    do_close_window_for_cursor_aucmd(win_id)
  end)
end

local function close_window_for_aucmd_if_cursor_out_of_bounds(win_id, cursor_win_id)
  vim.schedule(function()
    local pup = popup._popups[win_id]
    if not pup then
      return
    end
    -- NOTE: nil bounds should never have an autocmd to get in here.
    local bounds = pup.extras.moved_bounds
    -- close the window if out of bounds
    local lnum, col = unpack(vim.fn.getcursorcharpos(cursor_win_id), 2, 3)
    --llog("CURSOR OOB: l=%s, minc=%s, maxc=%s, current l=%s, c=%s", bounds[1], bounds[2], bounds[3], lnum, col)
    if lnum ~= bounds[1] or col < bounds[2] or col > bounds[3] then
      do_close_window_for_cursor_aucmd(win_id)
    end
  end)
end

--- Creates autocommands to close a popup window when events happen.
---
---@param events table list of events
---@param win_id integer window id of popup window
---@param bufnrs table list of buffers where the popup window will remain visible, {popup, parent}
---@see autocmd-events
local function close_window_autocmd(events, win_id, bufnrs, cursor_win_id)
  local augroup = vim.api.nvim_create_augroup("popup_window_" .. win_id, {
    clear = true,
  })

  -- close the popup window when entered a buffer that is not
  -- the floating window buffer or the buffer that spawned it
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function()
      close_window_for_aucmd(win_id, bufnrs)
    end,
  })

  if #events > 0 then
    vim.api.nvim_create_autocmd(events, {
      group = augroup,
      buffer = bufnrs[2],
      callback = function()
        --close_window_for_aucmd(win_id)
        close_window_for_aucmd_if_cursor_out_of_bounds(win_id, cursor_win_id)
      end,
    })
  end
end
--- End of code adapted from vim.lsp.util.close_preview_autocmd

--- Only used from 'WinClosed' autocommand
--- Cleanup after popup window closes.
---@param win_id integer window id of popup window
local function popup_win_closed(win_id)
  -- Invoke the callback with the win_id and result.
  local pup = popup._popups[win_id]
  if pup.callback then
    pcall(pup.callback, win_id, pup.result)
  end
  -- Forget about this popup.
  popup._popups[win_id] = nil
  significant_popup_change()
end

-- ===========================================================================
--
-- popup positioning
--

-- Convert the positional {vim_options} to compatible neovim options and add them to {win_opts}
-- If an option is not given in {vim_options}, fall back to {default_opts}
---@param vim_options PopupOptsVim
local function add_position_config(win_opts, vim_options, default_opts)
  default_opts = default_opts or {}

  local cursor_relative_pos = function(pos_str, dim)
    assert(string.find(pos_str, "^cursor"), "Invalid value for " .. dim)
    win_opts.relative = "cursor"
    local line = 0
    if (pos_str):match "cursor%+(%d+)" then
      line = line + tonumber((pos_str):match "cursor%+(%d+)")
    elseif (pos_str):match "cursor%-(%d+)" then
      line = line - tonumber((pos_str):match "cursor%-(%d+)")
    end
    return line
  end

  -- Feels like maxheight, minheight, maxwidth, minwidth will all be related
  --
  -- maxheight  Maximum height of the contents, excluding border and padding.
  -- minheight  Minimum height of the contents, excluding border and padding.
  -- maxwidth  Maximum width of the contents, excluding border, padding and scrollbar.
  -- minwidth  Minimum width of the contents, excluding border, padding and scrollbar.
  local width = if_nil(vim_options._width, default_opts.width)
  local height = if_nil(vim_options._height, default_opts.height)
  win_opts.width = utils.bounded(width, vim_options.minwidth, vim_options.maxwidth)
  win_opts.height = utils.bounded(height, vim_options.minheight, vim_options.maxheight)

  if vim_options.line and vim_options.line ~= 0 then
    if type(vim_options.line) == "string" then
      win_opts.row = cursor_relative_pos(vim_options.line, "row")
    else
      win_opts.row = vim_options.line - 1
    end
  else
    -- center "y"
    win_opts.row = math.floor((vim.o.lines - win_opts.height) / 2)
  end

  if vim_options.col and vim_options.col ~= 0 then
    if type(vim_options.col) == "string" then
      win_opts.col = cursor_relative_pos(vim_options.col, "col")
    else
      win_opts.col = vim_options.col - 1
    end
  else
    -- center "x"
    win_opts.col = math.floor((vim.o.columns - win_opts.width) / 2)
  end

  -- TODO:  BUG? in FOLLOWING code, if "center", sets line/col to 0/0,
  --        in ABOVE code if line or col is 0, then that gets centered.
  --        Looks like it's OUT OF ORDER.
  --        Also, if "center" need to move the row/col to account for the anchor.

  -- pos
  --
  -- The "pos" field defines what corner of the popup "line" and "col" are used
  -- for. When not set "topleft" behaviour is used. "center" positions the popup
  -- in the center of the Neovim window and "line"/"col" are ignored.
  if vim_options.pos then
    if vim_options.pos == "center" then
      vim_options.line = 0
      vim_options.col = 0
      win_opts.anchor = "NW"
    else
      local pos = popup._pos_map[vim_options.pos]
      win_opts.anchor = pos[1]
      -- Neovim uses a point, not a cell. Adjust col/row so the anchor corner
      -- covers the indicated cell.
      win_opts.col = win_opts.col + pos[2]
      win_opts.row = win_opts.row + pos[3]
    end
  else
    win_opts.anchor = "NW" -- This is the default, but makes `posinvert` easier to implement
  end

  -- , fixed    When FALSE (the default), and:
  -- ,      - "pos" is "botleft" or "topleft", and
  -- ,      - "wrap" is off, and
  -- ,      - the popup would be truncated at the right edge of
  -- ,        the screen, then
  -- ,     the popup is moved to the left so as to fit the
  -- ,     contents on the screen.  Set to TRUE to disable this.
end

-- ===========================================================================
--
-- popup border handling
--

--- Convert a vim border spec into a nvim border spec.
--- If no borderchars, then border is directly passed to window configuration,
--- so can use the full neovim border spec.

---
--- @param vim_options PopupOptsVim
--- @param win_opts { }
--- @param extras { }
local function translate_border(win_opts, vim_options, extras)
  win_opts.border = 'none'
  if not vim_options.border or vim_options.border == "none" then
    extras.border_thickness = { 0, 0, 0, 0}
    return
  end
  if type(vim_options.border) == "string" then
    -- TODO: convert to border chars instead of string, then "X" close can work.
    win_opts.border = vim_options.border  -- allow neovim border style name
    extras.border_thickness = { 1, 1, 1, 1}
    return
  end

  local win_border

  -- set border_thickness if border is an array of 4 or less numbers
  -- If border is an array of 4 numbers or less, then it's vim's border thickness
  local border_thickness = { 1, 1, 1, 1}

  if vim_options.border and type(vim_options.border) == "table" then
    local next_idx = 1  -- first thickness value goes here
    for idx, thick in pairs(vim_options.border) do
      if type(idx) ~= "number" or type(thick) ~= "number" or idx ~= next_idx then
        border_thickness = { 0, 0, 0, 0}
        break
      end
      border_thickness[idx] = thick
      if idx == 4 then
        break
      end
      next_idx = next_idx + 1
    end
  end
  extras.border_thickness = border_thickness

  -- Use "borderchars" to build 8 char array. Want all 8 characters since it
  -- is adjusted when a border_thickness is zero to turn off an edge.
  if vim_options.borderchars then
    win_border = {}
    -- neovim: the array specifies the eight chars building up the border in
    -- a clockwise fashion starting with the top-left corner. The double box
    -- style could be specified as: [ "╔", "═" ,"╗", "║", "╝", "═", "╚", "║" ].
    if #vim_options.borderchars == 1 then
      -- use the same char for everything, list of length 1
      for i = 1, 8 do
        win_border[i] = vim_options.borderchars[1]
      end
    elseif #vim_options.borderchars == 2 then
      -- vim: [ borders, corners ]; neovim: repeat [ corner, border ]
      for i = 0, 3 do
        win_border[(i*2)+1] = vim_options.borderchars[2]
        win_border[(i*2)+2] = vim_options.borderchars[1]
      end
    elseif #vim_options.borderchars == 4 then
      -- vim: top/right/bottom/left border. Default corners.
      local corners = { "╔", "╗", "╝", "╚" }
      for i = 1, 4 do
        win_border[#win_border+1] = corners[i]
        win_border[#win_border+1] = vim_options.borderchars[i]
      end
    elseif #vim_options.borderchars == 8 then
      -- vim: top/right/bottom/left / topleft/topright/botright/botleft
      win_border[1] = vim_options.borderchars[5]
      win_border[2] = vim_options.borderchars[1]
      win_border[3] = vim_options.borderchars[6]
      win_border[4] = vim_options.borderchars[2]
      win_border[5] = vim_options.borderchars[7]
      win_border[6] = vim_options.borderchars[3]
      win_border[7] = vim_options.borderchars[8]
      win_border[8] = vim_options.borderchars[4]
    else
      assert(false, string.format("Invalid number of 'borderchars': '%s'",
          I(vim_options.borderchars)))
    end
  else
    win_border = { "╔", "═" ,"╗", "║", "╝", "═", "╚", "║" }
  end

  -- Turn off the borderchars for any side that has 0 thickness.
  -- In "win_border", a side's index start at 1, 3, 5, 7 and is 3 characters.
  for idx, is_border_present in ipairs(border_thickness) do
    if is_border_present == 0 then
      -- start_char is zero based so simplify the wraparound logic
      local start_char = (idx - 1) * 2
      for i = start_char, start_char + 2 do
        win_border[(i % 8) + 1] = ""
      end
    end
  end

  win_opts.border = win_border
end

-- ===========================================================================
--
-- popup API
--

---@param what number|string[]
---@param vim_options PopupOptsNeovim
function popup.create(what, vim_options)
  vim_options = vim.deepcopy(vim_options)
  local win_opts = {}
  local extras = {}

  local bufnr
  if type(what) == "number" then
    bufnr = what
    extras.line_count = vim.api.nvim_buf_line_count(bufnr)
  else
    bufnr = vim.api.nvim_create_buf(false, true)
    assert(bufnr, "Failed to create buffer")

    vim.api.nvim_set_option_value("bufhidden", "wipe", {buf = bufnr})
    vim.api.nvim_set_option_value("modifiable", true, {buf = bufnr})

    -- TODO: Handle list of lines
    if type(what) == "string" then
      what = { what }
    else
      assert(type(what) == "table", '"what" must be a table')
    end
    extras.line_count = #what

    -- padding    List with numbers, defining the padding
    --     above/right/below/left of the popup (similar to CSS).
    --     An empty list uses a padding of 1 all around.  The
    --     padding goes around the text, inside any border.
    --     Padding uses the 'wincolor' highlight.
    --     Example: [1, 2, 1, 3] has 1 line of padding above, 2
    --     columns on the right, 1 line below and 3 columns on
    --     the left.
    if vim_options.padding then
      local pad_top, pad_right, pad_below, pad_left
      if vim.tbl_isempty(vim_options.padding) then
        pad_top = 1
        pad_right = 1
        pad_below = 1
        pad_left = 1
      else
        local padding = vim_options.padding
        pad_top = padding[1] or 0
        pad_right = padding[2] or 0
        pad_below = padding[3] or 0
        pad_left = padding[4] or 0
      end
      extras.padding = { pad_top, pad_right, pad_below, pad_left }

      local left_padding = string.rep(" ", pad_left)
      local right_padding = string.rep(" ", pad_right)
      for index = 1, #what do
        what[index] = string.format("%s%s%s", left_padding, what[index], right_padding)
      end

      for _ = 1, pad_top do
        table.insert(what, 1, "")
      end

      for _ = 1, pad_below do
        table.insert(what, "")
      end
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, what)
  end
  if not extras.padding then
    extras.padding = { 0, 0, 0, 0 }
  end


  local option_defaults = {
    posinvert = true,
    zindex = 50,
  }

  vim_options._width = if_nil(vim_options._width, 1)
  if type(what) == "number" then
    vim_options._height = vim.api.nvim_buf_line_count(what)
  else
    for _, v in ipairs(what) do
      vim_options._width = math.max(vim_options._width, #v)
    end
    vim_options._height = #what
  end

  win_opts.relative = "editor"
  win_opts.style = "minimal"

  -- Some neovim fields are simply copied. like title/footer.
  for _, field in ipairs(neovim_passthru) do
    win_opts[field] = vim_options[field]
  end

  win_opts.hide = vim_options.hidden

  -- noautocmd, undocumented vim default per https://github.com/vim/vim/issues/5737
  win_opts.noautocmd = if_nil(vim_options.noautocmd, true)

  -- focusable - neovim only
  -- vim popups are not focusable windows
  win_opts.focusable = if_nil(vim_options.focusable, false)

  -- add positional and sizing config to win_opts
  add_position_config(win_opts, vim_options, { width = 1, height = 1 })

  -- -- Set up the border.
  translate_border(win_opts, vim_options, extras)

  -- set up for "close == button"
  if vim_options.close == "button" then
    -- TODO: at some point win_opts.border will have been converted to array
    -- With neovim style borders can't just change a border.
    if type(win_opts.border) ~= "string" then
      if win_opts.border and win_opts.border[3] ~= "" then
        -- There's a top-right border corner.
        win_opts.border[3] = "X"
        -- Need to add left+right border to column column size for checking.
        extras.button_close_pad = extras.border_thickness[2] + extras.border_thickness[4]
      elseif extras.border_thickness[1] == 0 and extras.border_thickness[2] == 0 then
        -- There's no border on top or right, overlay the buffer.
        vim.api.nvim_buf_set_extmark(bufnr, vim.api.nvim_create_namespace(""), 0, 0, {
          virt_text = { { "X", "" } },
          virt_text_pos = "right_align",
        })
        extras.button_close_pad = 0
      end
      -- NOTE: if extras.button_close_pad is nil, then "button" can't be handled.
    end
  end


  -- posinvert, When FALSE the value of "pos" is always used.  When
  -- ,   TRUE (the default) and the popup does not fit
  -- ,   vertically and there is more space on the other side
  -- ,   then the popup is placed on the other side of the
  -- ,   position indicated by "line".
  if dict_default(vim_options, "posinvert", option_defaults) then
    if win_opts.anchor == "NW" or win_opts.anchor == "NE" then
      if win_opts.row + win_opts.height > vim.o.lines and win_opts.row * 2 > vim.o.lines then
        -- Don't know why, but this is how vim adjusts it
        win_opts.row = win_opts.row - win_opts.height - 2
      end
    elseif win_opts.anchor == "SW" or win_opts.anchor == "SE" then
      if win_opts.row - win_opts.height < 0 and win_opts.row * 2 < vim.o.lines then
        -- Don't know why, but this is how vim adjusts it
        win_opts.row = win_opts.row + win_opts.height + 2
      end
    end
  end

  -- textprop, When present the popup is positioned next to a text
  -- ,   property with this name and will move when the text
  -- ,   property moves.  Use an empty string to remove.  See
  -- ,   |popup-textprop-pos|.
  -- related:
  --   textpropwin
  --   textpropid

  -- zindex, Priority for the popup, default 50.  Minimum value is
  -- ,   1, maximum value is 32000.
  local zindex = dict_default(vim_options, "zindex", option_defaults)
  win_opts.zindex = utils.bounded(zindex, 1, 32000)
  vim_options.zindex = win_opts.zindex -- save this for sorting

  -- So `getmousepos()` works with popup windows.
  win_opts.mouse = true

  local win_id = vim.api.nvim_open_win(bufnr, false, win_opts)

  -- Set the default result. The table keys also indicate active popups.
  -- Also keep track of all the options; they may be used for other functions.
  ---@type Pup
  local pup = {
    win_id = win_id,    -- for convenience
    result = -1,
    extras = extras,
    vim_options = vim_options,
    callback = nil,
  }
  popup._popups[win_id] = pup

  ----- Always catch the popup's close
  -----local augroup = vim.api.nvim_create_augroup("popup_close_" .. win_id, {
  -----  clear = true,
  -----})
  vim.api.nvim_create_autocmd("WinClosed", {
    -----group = augroup,
    pattern = tostring(win_id),
    callback = function()
      -----pcall(vim.api.nvim_del_augroup_by_name, augroup)
      popup_win_closed(win_id)
      return true
    end,
  })

  -- If the buffer's deleted close the window.
  vim.api.nvim_create_autocmd("BufDelete", {
    once = true,
    nested = true,
    buffer = bufnr,
    callback = function()
      popup.close(win_id, -1)
    end,
  })

  -- Moved, handled after since we need the window ID
  if vim_options.moved then
    local pos = vim.fn.getcursorcharpos()
    extras.moved_bounds = L.parse_moved_option(vim_options.moved, pos[2], pos[3])
    if not is_nil_bounds(extras.moved_bounds) then
      close_window_autocmd({ "CursorMoved", "CursorMovedI" }, win_id,
                           { bufnr, vim.fn.bufnr() }, vim.api.nvim_get_current_win())
    end
  end

  -- MouseMoved
  extras.mousemoved_bounds = { 0, 0, 0 }
  if vim_options.mousemoved then
    -- TODO: would like to capture current mouse pos, but doesn't work first time
    extras.mousemoved_bounds = "prime"
    --local mp = vim.fn.getmousepos() -- assume this will be needed
    --extras.mousemoved_bounds = L.parse_moved_option(
    --  vim_options.mousemoved, mp.winrow, mp.wincol, true)
  end

  if vim_options.time then
    local timer = vim.uv.new_timer()
    timer:start(
      vim_options.time,
      0,
      -- TODO: investigate the wrap
      vim.schedule_wrap(function()
          popup.close(win_id)
      end)
    )
  end

  -- Window and Buffer Options

  if vim_options.cursorline then
    vim.api.nvim_set_option_value("cursorline", true, { win = win_id })
  end

  -- Window's "wrap" defaults to true, nothing to do if no "wrap" option.
  if vim_options.wrap ~= nil then
    -- set_option wrap should/will trigger autocmd, see https://github.com/neovim/neovim/pull/13247
    if vim_options.noautocmd then -- neovim only
      vim.cmd(string.format("noautocmd lua vim.api.nvim_set_option(%s, wrap, %s)", win_id, vim_options.wrap))
    else
      vim.api.nvim_set_option_value("wrap", vim_options.wrap, { win = win_id })
    end
  end

  -- ===== Not Implemented Options =====
  -- See POPUP.md
  --
  -- flip: not implemented in vim at the time of writing
  --    resize: mouses are hard
  --
  -- scrollbar
  -- scrollbarhighlight
  -- thumbhighlight

  -- tabpage: seems useless


  -- ---------------------------------------- TODO: highlight handling

  -- TODO: borderhighlight

  -- borderhighlight List of highlight group names to use for the border.
  --                 When one entry it is used for all borders, otherwise
  --                 the highlight for the top/right/bottom/left border.
  --                 Example: ['TopColor', 'RightColor', 'BottomColor,
  --                 'LeftColor']

  -- border_options.highlight = vim_options.borderhighlight
  --               and string.format("Normal:%s", vim_options.borderhighlight)
  -- border_options.titlehighlight = vim_options.titlehighlight

  -- ---------------------------------------- TODO: highlight handling

  if vim_options.highlight then
    -- TODO: use neovim's "vim.o.xxx"
    vim.api.nvim_set_option_value(
      "winhl",
      string.format("Normal:%s,EndOfBuffer:%s", vim_options.highlight, vim_options.highlight),
      { win = win_id }
    )
  end

  -- enter - neovim only

  if vim_options.enter then
    -- set focus after border creation so that it's properly placed (especially
    -- in relative cursor layout)
    if vim_options.noautocmd then
      vim.cmd("noautocmd lua vim.api.nvim_set_current_win(" .. win_id .. ")")
    else
      vim.api.nvim_set_current_win(win_id)
    end
  end

  -- callback
  if vim_options.callback then
    pup.callback = vim_options.callback
  end

  significant_popup_change(win_id)

  return win_id
end

--- Close the specified popup window; the "result" is available through callback.
--- Do nothing if there is no such popup with the specified id.
---
---@param win_id integer window id of popup window
---@param result any? value to return in a callback
function popup.close(win_id, result)
  -- Only save the result if there is a popup with that window id.
  local pup = popup._popups[win_id]
  if pup == nil then
    return
  end
  -- update the result as specified
  if result == nil then
    result = 0
  end

  pup.result = result
  pcall(vim.api.nvim_win_close, win_id, true)
end

-- TODO: returned list in z-order; keep a list in z-order.
--- Return list of window id of existing popups
---
---@return integer[]
function popup.list()
  local ids = {}
  for win_id, _ in pairs(popup._popups) do
    if type(win_id) == 'number' then
      ids[#ids+1] = win_id
    end
  end
  return ids
end

--- Close all popup windows
---
--- @param force? boolean
function popup.clear(force)
  local cur_win_id = vim.fn.win_getid()
  if popup._popups[cur_win_id] and not force then
    assert(false, "Not allowed in a popup window")
    return
  end
  for win_id, _ in pairs(popup._popups) do
    if type(win_id) == "number" then
      local pup = popup._popups[win_id]
      -- no callback when clear
      pup.callback = nil
      pcall(vim.api.nvim_win_close, win_id, true)
    end
  end
end


--- Hide the popup.
--- If win_id does not exist nothing happens.  If win_id
--- exists but is not a popup window an error is given.
---
---@param win_id integer window id of popup window
function popup.hide(win_id)
  if not vim.api.nvim_win_is_valid(win_id) then
    return
  end
  local pup = popup._popups[win_id]
  assert(pup ~= nil, "popup.hide: not a popup window")
  vim.api.nvim_win_set_config(win_id, { hide = true })
  significant_popup_change(win_id)
end

--- Show the popup.
--- Do nothing if non-existent window or window not a popup.
---
---@param win_id integer show the popup with this win_id
function popup.show(win_id)
  local pup = popup._popups[win_id]
  if not vim.api.nvim_win_is_valid(win_id) or not pup then
    return
  end
  vim.api.nvim_win_set_config(win_id, { hide = false })
  significant_popup_change(win_id)
end

-- Move popup with window id {win_id} to the position specified with {vim_options}.
-- {vim_options} may contain the following items that determine the popup position/size:
-- - line
-- - col
-- - pos
-- - height
-- - width
-- - max/min width/height
-- Unspecified options correspond to the current values for the popup.
--
-- Unimplemented vim options here include: fixed
--
---@param win_id PopupId
---@param vim_options PopupOptsNeovim
function popup.move(win_id, vim_options)
  local pup = popup._popups[win_id]
  if not pup then
    return
  end
  vim_options = vim.deepcopy(vim_options)
  local cur_vim_options = pup.vim_options

  -- Create win_options
  local win_opts = {}
  win_opts.relative = "editor"

  -- width/height can not be set with "popup_move", use current values
  vim_options._width = vim.api.nvim_win_get_width(win_id)
  vim_options._height = vim.api.nvim_win_get_height(win_id)

  local current_pos = vim.api.nvim_win_get_position(win_id)
  vim_options.line = vim_options.line or (current_pos[1] + 1)
  vim_options.col = vim_options.col or (current_pos[2] + 1)

  -- Use specified option if set; otherwise the current value; save to current.
  local function fixopt(field)
    vim_options[field] = vim_options[field] or cur_vim_options[field]
    cur_vim_options[field] = vim_options[field]
  end
  fixopt("minheight")
  fixopt("maxheight")
  fixopt("minwidth")
  fixopt("maxwidth")

  -- Add positional and sizing config to win_opts
  add_position_config(win_opts, vim_options)

  -- Update content window
  vim.api.nvim_win_set_config(win_id, win_opts)
end

-- TODO:  "popup.setoptions" is tricky, need to refactor some of popup.create.
--
--        Consider changing padding
--
--function popup.setoptions(win_id)
--end


--
-- Notice
--       vim-win     == neovim + border
--       vim-core    == neovim - padding
--
--       neovim + border ==  vim-win
--       neovim          ==  vim-core + padding
--

---@return integer x
---@return integer y
function popup._getxy(win_id)
  local position = vim.api.nvim_win_get_position(win_id)
  return position[2] + 1, position[1] + 1
end

--- The "core_*" fields are the original text boundaries without padding or border.
--- The width/height fields include border and padding. nvim_win_get_config does
--- not include border.
--- Positional values are converted to 1 based.
---
function popup.getpos(win_id)
  local pup = popup._popups[win_id]
  if not pup then
    return {}
  end
  local extras = pup.extras
  --local win_opts = pup.win_opts
  local config = vim.api.nvim_win_get_config(win_id)
  local position = vim.api.nvim_win_get_position(win_id)
  local col = position[2] + 1
  local line = position[1] + 1
  local ret = {
    col = col,
    line = line,
    -- width/height include the border in the "popup in screen cells"
    width = config.width + extras.border_thickness[2] + extras.border_thickness[4],
    height = config.height + extras.border_thickness[1] + extras.border_thickness[3],

    -- offset "core_col" by border/padding on the left
    core_col = col + extras.border_thickness[4] + extras.padding[4],
    -- offset "core_line" by border/padding on the top
    core_line = line + extras.border_thickness[1] + extras.padding[1],
    -- core_width/core_height do not include padding
    core_width = config.width - extras.padding[2] - extras.padding[4],
    core_height = config.height - extras.padding[1] - extras.padding[3],

    visible = not config.hide,

    -- TODO: just throw some stuff in for scrollbar/first/last
    scrollbar = false,
    firstline = 1,
    lastline = extras.line_count,
  }
  return ret
end

maps.key2mouse = {
    ["\128\253\044"] = "<LeftMouse>",
    ["\128\253\045"] = "<LeftDrag>",
    ["\128\253\046"] = "<LeftRelease>",
    ["\128\253\047"] = "<MiddleMouse>",
    ["\128\253\048"] = "<MiddleDrag>",
    ["\128\253\049"] = "<MiddleRelease>",
    ["\128\253\050"] = "<RightMouse>",
    ["\128\253\051"] = "<RightDrag>",
    ["\128\253\052"] = "<RightRelease>",

    ["\128\253\089"] = "<X1Mouse>",
    ["\128\253\090"] = "<X1Drag>",
    ["\128\253\091"] = "<X1Release>",
    ["\128\253\092"] = "<X2Mouse>",
    ["\128\253\093"] = "<X2Drag>",
    ["\128\253\094"] = "<X2Release>",

    ["\128\253\100"] = "<MouseMove>",

    ["\128\252\032"] = "<2Click>",
    ["\128\252\064"] = "<3Click>",
    ["\128\252\096"] = "<4Click>",

    -- ["\128\253\069"] = "<LeftMouseNM>",
    -- ["\128\253\070"] = "<LeftReleaseNM>",

    -- ["\128\236\088"] = "<SgrMouseRelease>",
    -- ["\128\237\088"] = "<SgrMouse>",
}

maps.mouse2key = {
    ["<LeftMouse>"] =          "\128\253\044",
    ["<LeftDrag>"] =           "\128\253\045",
    ["<LeftRelease>"] =        "\128\253\046",
    ["<MiddleMouse>"] =        "\128\253\047",
    ["<MiddleDrag>"] =         "\128\253\048",
    ["<MiddleRelease>"] =      "\128\253\049",
    ["<RightMouse>"] =         "\128\253\050",
    ["<RightDrag>"] =          "\128\253\051",
    ["<RightRelease>"] =       "\128\253\052",

    ["<X1Mouse>"] =            "\128\253\089",
    ["<X1Drag>"] =             "\128\253\090",
    ["<X1Release>"] =          "\128\253\091",
    ["<X2Mouse>"] =            "\128\253\092",
    ["<X2Drag>"] =             "\128\253\093",
    ["<X2Release>"] =          "\128\253\094",

    ["<MouseMove>"] =          "\128\253\100",

    ["<2Click>"] =             "\128\252\032",
    ["<3Click>"] =             "\128\252\064",
    ["<4Click>"] =             "\128\252\096",

    ["<LeftMouseNM>"] =        "\128\253\069",
    ["<LeftReleaseNM>"] =      "\128\253\070",

    ["<SgrMouseRelease>"] =    "\128\236\088",
    ["<SgrMouse>"] =           "\128\237\088",
}

maps.mouse_events = {
  ["<LeftMouse>"]     = { button = "LEFT",     is_click = true,   is_drag = false },
  ["<LeftDrag>"]      = { button = "LEFT",     is_click = false,  is_drag = true },
  ["<LeftRelease>"]   = { button = "LEFT",     is_click = false,  is_drag = false },
  ["<MiddleMouse>"]   = { button = "MIDDLE",   is_click = true,   is_drag = false },
  ["<MiddleDrag>"]    = { button = "MIDDLE",   is_click = false,  is_drag = true },
  ["<MiddleRelease>"] = { button = "MIDDLE",   is_click = false,  is_drag = false },
  ["<RightMouse>"]    = { button = "RIGHT",    is_click = true,   is_drag = false },
  ["<RightDrag>"]     = { button = "RIGHT",    is_click = false,  is_drag = true },
  ["<RightRelease>"]  = { button = "RIGHT",    is_click = false,  is_drag = false },
  ["<X1Mouse>"]       = { button = "X1",       is_click = true,   is_drag = false },
  ["<X1Drag>"]        = { button = "X1",       is_click = false,  is_drag = true },
  ["<X1Release>"]     = { button = "X1",       is_click = false,  is_drag = false },
  ["<X2Mouse>"]       = { button = "X2",       is_click = true,   is_drag = false },
  ["<X2Drag>"]        = { button = "X2",       is_click = false,  is_drag = true },
  ["<X2Release>"]     = { button = "X2",       is_click = false,  is_drag = false },
}

maps.mode_to_short_mode = {
  ["n"]        = "n",

  ["no"]       = "o",
  ["nov"]      = "o",
  ["noV"]      = "o",
  ["noCTRL-V"] = "o",

  ["niI"]      = "n",
  ["niR"]      = "n",
  ["niV"]      = "n",
  ["nt"]       = "n",
  ["ntT"]      = "n",

  ["v"]        = "x",
  ["vs"]       = "x",
  ["V"]        = "x",
  ["Vs"]       = "x",
  ["CTRL-V"]   = "x",
  ["CTRL-Vs"]  = "x",

  ["s"]        = "s",
  ["S"]        = "s",
  ["CTRL-S"]   = "s",

  ["i"]        = "i",
  ["ic"]       = "i",
  ["ix"]       = "i",
  ["R"]        = "i",
  ["Rc"]       = "i",
  ["Rx"]       = "i",
  ["Rv"]       = "i",
  ["Rvc"]      = "i",
  ["Rvx"]      = "i",

  ["c"]        = "c",
  ["cr"]       = "c",
  ["cv"]       = "c",
  ["cvr"]      = "c",
  ["r"]        = "c",
  ["rm"]       = "c",
  ["r?"]       = "c",
  ["!"]        = "c",

  ["t"]        = "l",
}


-- "Programming in Lua" 13.4 Read-only tables
local function read_only (t)
  local proxy = {}
  local mt = {       -- create metatable
    __index = t,
    __newindex = function (_,_,_)
      error("attempt to update a read-only table", 2)
    end
  }
  setmetatable(proxy, mt)
  return proxy
end

popup._key2mouse = read_only(maps.key2mouse)
popup._mouse2key = read_only(maps.mouse2key)
popup._mouse_events = read_only(maps.mouse_events)

function L.k2m(key)
  return maps.key2mouse[key] or key
end

---Split a string with multiple characters into an array of strings.
---If a string starts with an "<80>"/"128", then collect 3 chars as a
---single string. Expensive to call if there's only one character.
---
---@param keys string
---@return string[]? of key/mouse events
function popup._split_keys(keys)
  -- TODO: probably don't need this function.
  if #keys == 0 then
    return {}
  end

  local outp_list = {}
  local inp_idx = 1
  while inp_idx <= #keys do
    local s
    if keys:byte(inp_idx) == 128 then
      s = keys:sub(inp_idx, inp_idx+2)
      inp_idx = inp_idx + 3
    else
      --s = keys:byte(inp_idx)
      s = keys:sub(inp_idx, inp_idx)
      inp_idx = inp_idx + 1
    end
    outp_list[#outp_list+1] = s
  end

  --local inp_keys = vim.fn.str2list(keys)
  --while inp_idx <= #inp_keys do
  --  if inp_keys[inp_idx] == 128 then
  --    s = vim.fn.list2str(vim.fn.slice(inp_keys, inp_idx, inp_idx+3))
  --    inp_idx = inp_idx + 3
  --  else
  --  end
  --end

  return outp_list
end

---Convert list elements to mouse event names and concat them to single string.
---Can use directly with output of popup._split_keys().
---@param klist string[]
---@return string
function popup._combine(klist)
    local s = ""
    for _,k in ipairs(klist) do
        s = s .. L.k2m(k)
    end
    return s
end

return popup
