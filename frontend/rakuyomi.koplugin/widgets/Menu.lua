local BaseMenu = require("ui/widget/menu")
local Blitbuffer = require("ffi/blitbuffer")
local NetworkMgr = require("ui/network/manager")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext+")

local Icons = require("Icons")

local Menu = BaseMenu:extend {
  with_context_menu = false,
}

function Menu:init()
  if self.with_context_menu then
    self.align_baselines = true
  end

  self:updateOfflineSubtitle(true)

  BaseMenu.init(self)
end

function Menu:updateItems(select_number)
  for _, item in ipairs(self.item_table or {}) do
    if self.with_context_menu and item.select_enabled ~= false then
      -- Save the original mandatory on first call so we don't keep appending the icon
      if item._orig_mandatory == nil then
        item._orig_mandatory = item.mandatory or ""
      end
      item.mandatory = (item._orig_mandatory ~= "" and (item._orig_mandatory .. " ") or "") .. Icons.FA_ELLIPSIS_VERTICAL
    end
  end

  -- Cover mode: apply user-configured items per page
  if self.display_mode == "cover" then
    self.items_per_page = G_reader_settings:readSetting("rakuyomi_items_per_page_cover") or 4
  end

  -- Step 1: Let BaseMenu do the full layout (pagination, item_dimen, page_info etc.)
  local base_ok, base_err = pcall(BaseMenu.updateItems, self, select_number)
  if not base_ok then
    logger.err("Menu.updateItems: BaseMenu.updateItems failed:", base_err)
    return
  end

  -- Step 2: If cover mode, replace the standard items with LibraryCoverMenuItem.
  -- Guard: only when the menu is fully initialised (item_group + valid item_dimen).
  if self.display_mode ~= "cover" then
    return
  end
  if not self.item_table or #self.item_table < 1 then
    return
  end
  if not self.item_group or type(self.item_group.clear) ~= "function" then
    return
  end
  if not self.item_dimen or not self.item_dimen.w or self.item_dimen.w < 1
      or not self.item_dimen.h or self.item_dimen.h < 1 then
    return
  end

  local ok, err = pcall(function()
    local LibraryCoverMenuItem = require("LibraryCoverMenuItem")

    local old_dimen = self.dimen and self.dimen:copy()
    self.layout = {}
    self.item_group:clear()

    local items_nb = self.perpage or 14
    if items_nb < 1 then items_nb = 14 end
    local idx_offset = (self.page - 1) * items_nb

    for idx = 1, items_nb do
      local index = idx_offset + idx
      local item = self.item_table[index]
      if item == nil then break end
      item.idx = index
      if index == self.itemnumber then
        select_number = idx
      end
      local item_shortcut, shortcut_style
      if self.is_enable_shortcut then
        item_shortcut = self.item_shortcuts[idx]
        shortcut_style = (idx < 11 or idx > 20) and "square" or "grey_square"
      end

      local item_tmp = LibraryCoverMenuItem:new {
        idx = index,
        show_parent = self.show_parent,
        bold = self.item_table.current == index,
        font_size = self.font_size or 22,
        infont_size = self.items_mandatory_font_size or (self.font_size and (self.font_size - 4)) or 18,
        dimen = self.item_dimen:copy(),
        shortcut = item_shortcut,
        shortcut_style = shortcut_style,
        entry = item,
        menu = self,
        linesize = self.linesize or Size.line.medium,
        single_line = self.single_line,
        line_color = self.line_color or Blitbuffer.COLOR_DARK_GRAY,
        items_padding = self.items_padding or Size.padding.fullscreen,
        handle_hold_on_hold_release = self.handle_hold_on_hold_release,
        text = item.text,
        post_text = item.post_text,
        mandatory = item.mandatory,
      }
      table.insert(self.item_group, item_tmp)
      table.insert(self.layout, { item_tmp })
    end

    self:updatePageInfo(select_number)
    self:mergeTitleBarIntoLayout()

    UIManager:setDirty(self.show_parent, function()
      local refresh_dimen = old_dimen and old_dimen:combine(self.dimen) or self.dimen
      return "ui", refresh_dimen
    end)
  end)
  if not ok then
    logger.err("Menu.updateItems: cover replace failed:", err)
  end
end

function Menu:onMenuSelect(entry, pos)
  if entry.select_enabled == false then
    return true
  end

  local selected_context_menu = pos ~= nil and pos.x > 0.8

  if selected_context_menu then
    self:onContextMenuChoice(entry, pos)
  else
    self:onPrimaryMenuChoice(entry, pos)
  end
end

function Menu:onMenuHold(entry, pos)
  self:onContextMenuChoice(entry, pos)
end

--- Defaults to calling the entry's callback.
--- Override this function to change the behavior.
function Menu:onPrimaryMenuChoice(entry, pos)
  if entry.callback then
    entry.callback()
  end

  return true
end

function Menu:onContextMenuChoice(entry, pos)
end

---@private
function Menu:onNetworkConnected()
  logger.info("Menu:onNetworkConnected()")

  self:updateOfflineSubtitle()
end

---@private
function Menu:onNetworkDisconnected()
  logger.info("Menu:onNetworkDisconnected()")

  self:updateOfflineSubtitle()
end

---@private
function Menu:updateOfflineSubtitle(skip_reinit)
  if NetworkMgr:isConnected() then
    self.subtitle = nil
  else
    self.subtitle = Icons.WIFI_OFF .. " " .. _("Offline mode")
  end

  if not skip_reinit then
    BaseMenu.init(self)
  end
end

return Menu
