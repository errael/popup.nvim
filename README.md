# popup.nvim

A `Neovim` API that is compatible with the vim `popup_*` APIs.

## Install and Use

Installation using Lazy.
```
$ cat ~/.config/nvim/lua/plugins/popup.lua
return {
    { 'errael/popup.nvim', dev = false },
}
```
Check out [examples](examples) for usage.

Use vim's documentation for now.

Almost the entire vim popup API has been implemented; see following to identify the few missing pieces.

## Goals

After stablization and any required features are merged into Neovim, can
upstream this and expose the API in vimL to create better compatibility.

# Popup Status and Features

[WIP] An implementation of the Popup API from vim in Neovim.

## Notices
- **2024-09-19:** change `enter` default to false to follow Vim.
- **2021-08-19:** we now follow Vim's default to `noautocmd` on popup creation. This can be overriden with `vim_options.noautocmd=false`

## List of Neovim Features Required

- [x] Key handlers (used for `popup_filter`)
    - [x] filter https://github.com/neovim/neovim/pull/30939 (integrated)
    - [ ] mapping https://github.com/neovim/neovim/issues/30741 (open)
- [ ] scrollbar for floating windows
    - [ ] firstline
    - [ ] scrollbar
    - [ ] scrollbarhighlight
    - [ ] thumbhighlight

Optional:

- [ ] Add forced transparency to a floating window.
    - [ ] mask
        - Apparently overrides text?

Unlikely (due to technical difficulties):

- [ ] Add `textprop` wrappers?
    - [ ] textprop
    - [ ] textpropwin
    - [ ] textpropid

Unlikely (due to not sure if people are using):
- [ ] tabpage

## Progress

### Suported Functions

Creating a popup window:
- [x] popup.create
- [ ] a bunch of specialized popups; basically preset options

Manipulating a popup window:
- [x] popup.hide
- [x] popup.show
- [x] popup.move
- [ ] popup.setoptions

Closing popup windows:
- [x] popup.close
- [x] popup.clear

Filter functions:

Other:
- [ ] popup.getoptions
- [x] popup.getpos
- [ ] popup.locate
- [x] popup.list


### Suported Features

- [x] what
    - string
    - list of strings
    - bufnr
- [x] popup_create-arguments
    - [x] line
    - [x] col
    - [x] pos
    - [x] posinvert
    - [ ] fixed
    - [x] {max,min}{height,width}
    - [x] hidden
    - [x] title
    - [x] wrap
    - [x] drag
    - [x] dragall
    - [ ] resize
    - [x] close
        - [x] "button"
        - [x] "click"
        - [x] "none"
    - [x] highlight
    - [x] padding
    - [x] border
    - [ ] borderhighlight
    - [x] borderchars
    - [x] zindex
    - [x] time
    - [x] moved
        - [x] "any"
        - [x] { i, j }, { i, j, k } (list options)
        - [ ] "word", "WORD", "expr"
    - [x] mousemoved
        - [x] "any"
        - [x] { i, j }, { i, j, k } (list options)
        - [ ] "word", "WORD", "expr"
    - [x] cursorline
    - [x] filter
    - [x] mapping
    - [x] filtermode
    - [x] callback


### Additional Features from `neovim`

- [x] enter
- [x] focusable
- [x] noautocmd
- [x] finalize_callback
- [x] title_pos
- [x] footer
- [x] footer_pos

## All known unimplemented vim features at the moment

- fixed
- borderhighlight
- resize
- flip (not implemented in vim yet)
- scrollbar related: firstline, scrollbar, scrollbarhighlight, thumbhighlight

## Functions not planned

- popup_beval
