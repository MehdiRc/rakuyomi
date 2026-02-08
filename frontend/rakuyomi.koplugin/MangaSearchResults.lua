local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Trapper = require("ui/trapper")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext+")

local Backend = require("Backend")
local ErrorDialog = require("ErrorDialog")
local Menu = require("widgets/Menu")
local LoadingDialog = require("LoadingDialog")
local ChapterListing = require("ChapterListing")
local Testing = require("testing")
local Icons = require("Icons")
local MangaInfoWidget = require("MangaInfoWidget")
local calcLastReadText = require("utils/calcLastReadText")

--- @class MangaSearchResults: { [any]: any }
--- @field results Manga[]
--- @field on_return_callback fun(): nil
local MangaSearchResults = Menu:extend {
  name = "manga_search_results",
  is_enable_shortcut = false,
  is_popout = false,
  title = _("Search results..."),
  with_context_menu = true,

  -- list of mangas
  results = nil,
  -- callback to be called when pressing the back button
  on_return_callback = nil,
}

function MangaSearchResults:init()
  self.results = self.results or {}
  self.manga_details = self.manga_details or {}
  self.display_mode = self.display_mode or "list"
  self.width = Screen:getWidth()
  self.height = Screen:getHeight()

  -- Apply user-configured items per page
  if self.display_mode == "cover" then
    self.items_per_page = G_reader_settings:readSetting("rakuyomi_items_per_page_cover") or 4
  else
    local list_per_page = G_reader_settings:readSetting("rakuyomi_items_per_page_list")
    if list_per_page then
      self.items_per_page = list_per_page
    end
  end

  local page = self.page
  Menu.init(self)
  self.page = page

  -- see `ChapterListing` for an explanation on this
  -- FIXME we could refactor this into a single class
  self.paths = { 0 }
  self.on_return_callback = nil

  self:updateItems()
end

function MangaSearchResults:onClose()
  -- Cancel any in-flight async cover fetches
  self._async_cover_gen = (self._async_cover_gen or 0) + 1

  -- Clean up cover images that were downloaded during this search session,
  -- unless ownership was transferred to a new instance (e.g. after Details).
  if not self._skip_cover_cleanup then
    self:_cleanupCoverFiles()
  end

  UIManager:close(self)
  if self.on_return_callback then
    self.on_return_callback()
  end
end

--- Removes all cover files downloaded during this search session.
--- Skips files for manga that are currently in the library.
--- @private
function MangaSearchResults:_cleanupCoverFiles()
  if not self._search_cover_files or #self._search_cover_files == 0 then
    return
  end

  -- Build a set of cover paths belonging to library manga so we don't delete them
  local library_paths = {}
  if self.manga_details then
    for _, manga in ipairs(self.results or {}) do
      if manga.in_library then
        local key = ((manga.source and manga.source.id) or "") .. "/" .. (manga.id or "")
        local detail = self.manga_details[key]
        if detail and detail.cover_file then
          library_paths[detail.cover_file] = true
        end
      end
    end
  end

  for _, path in ipairs(self._search_cover_files) do
    if not library_paths[path] then
      pcall(os.remove, path)
    end
  end
  self._search_cover_files = {}
end

--- Updates the menu item contents with the manga information.
--- In cover mode, the page is displayed immediately with placeholders,
--- then covers are loaded asynchronously one at a time.
--- @private
function MangaSearchResults:updateItems()
  self.item_table = self:generateItemTableFromSearchResults(self.results)

  Menu.updateItems(self)

  -- After the page is rendered, kick off async cover loading
  if self.display_mode == "cover" and #self.results > 0 then
    self:_asyncLoadCovers()
  end
end

--- Loads covers for the results on the current page.
--- Phase 1: resolves already-cached covers synchronously (no placeholder flash).
--- Phase 2: fetches remaining covers asynchronously one at a time via nextTick.
--- @private
function MangaSearchResults:_asyncLoadCovers()
  local coverCovers = require("utils/fetchMangaCovers")
  local perpage = self.perpage or self.items_per_page or 14
  local page = self.page or 1
  local start_idx = (page - 1) * perpage + 1
  local end_idx = math.min(start_idx + perpage - 1, #self.results)

  self.manga_details = self.manga_details or {}

  -- Phase 1: resolve already-cached covers instantly (no network, no nextTick)
  local need_network = {}
  local resolved_count = 0
  for i = start_idx, end_idx do
    local m = self.results[i]
    if m then
      local key = coverCovers.detailKey(m)
      if not self.manga_details[key] then
        local cached = coverCovers.fetchCachedCover(m)
        if cached then
          self.manga_details[key] = cached
          resolved_count = resolved_count + 1
        else
          table.insert(need_network, m)
        end
      end
    end
  end

  -- If we resolved any NEW cached covers, rebuild items so they show immediately
  if resolved_count > 0 then
    self.item_table = self:generateItemTableFromSearchResults(self.results)
    Menu.updateItems(self)
  end

  if #need_network == 0 then return end

  -- Phase 2: fetch remaining covers asynchronously (these need network requests)
  self._async_cover_gen = (self._async_cover_gen or 0) + 1
  local gen = self._async_cover_gen
  local view = self

  local idx = 1
  local function fetchNext()
    if view._async_cover_gen ~= gen then return end
    if idx > #need_network then
      view.item_table = view:generateItemTableFromSearchResults(view.results)
      Menu.updateItems(view)
      return
    end

    local manga = need_network[idx]
    idx = idx + 1

    local detail, cover_path = coverCovers.fetchOneMangaCover(manga)
    if detail then
      view.manga_details[coverCovers.detailKey(manga)] = detail
    end
    if cover_path then
      view._search_cover_files = view._search_cover_files or {}
      table.insert(view._search_cover_files, cover_path)
    end

    UIManager:nextTick(fetchNext)
  end

  UIManager:nextTick(fetchNext)
end

--- Generates the item table for displaying the search results.
--- @private
--- @param results Manga[]
--- @return table
function MangaSearchResults:generateItemTableFromSearchResults(results)
  local item_table = {}
  local source_id_fn = function(m) return (m.source and m.source.id) or "" end
  for _, manga in ipairs(results) do
    local mandatory = (manga.last_read and calcLastReadText(manga.last_read) .. " " or "")

    if manga.unread_chapters_count ~= nil and manga.unread_chapters_count > 0 then
      mandatory = (mandatory or "") .. Icons.FA_BELL .. manga.unread_chapters_count
    end

    if manga.in_library then
      mandatory = (mandatory or "") .. Icons.COD_LIBRARY
    end

    local item = {
      manga = manga,
      text = manga.title,
      post_text = manga.source.name,
      mandatory = mandatory,
    }

    -- Cover mode: add cover_file and tags_text from cached manga details
    if self.display_mode == "cover" and self.manga_details then
      local key = source_id_fn(manga) .. "/" .. (manga.id or "")
      local details = self.manga_details[key]
      if details then
        item.cover_file = details.cover_file
        if details.tags and #details.tags > 0 then
          item.tags_text = table.concat(details.tags, ", ")
        else
          item.tags_text = ""
        end
      else
        item.cover_file = nil
        item.tags_text = ""
      end
    end

    table.insert(item_table, item)
  end

  return item_table
end

--- @private
function MangaSearchResults:onReturn()
  table.remove(self.paths)

  self:onClose()
end

--- @param errors SearchError[]
local function formatSearchErrors(errors)
  if not errors or #errors == 0 then
    return _("No errors")
  end

  local max_items = 5
  local lines = {}

  for i = 1, math.min(#errors, max_items) do
    local err = errors[i]
    table.insert(lines, string.format(
      "%s | %s",
      err.source_id,
      err.reason
    ))
  end

  if #errors > max_items then
    table.insert(lines, string.format(_("… and %d more errors"), #errors - max_items))
  end

  return table.concat(lines, "\n")
end
--- Searches for mangas and shows the results.
--- @param search_text string The text to be searched for.
--- @param exclude string[]
--- @param onReturnCallback any
--- @return boolean

function MangaSearchResults:searchAndShow(search_text, exclude, onReturnCallback)
  local cancel_id = Backend.createCancelId()
  local response, cancelled = LoadingDialog:showAndRun(
    _("Searching for") .. " \"" .. search_text .. "\"",
    function() return Backend.searchMangas(cancel_id, search_text, exclude) end,
    function()
      Backend.cancel(cancel_id)
      local InfoMessage = require("ui/widget/infomessage")

      local cancelledMessage = InfoMessage:new {
        text = _("Search cancelled."),
      }
      UIManager:show(cancelledMessage)
    end
  )

  if cancelled then
    return false
  end

  if response.type == 'ERROR' then
    ErrorDialog:show(response.message)

    return false
  end

  local results = response.body[1]

  -- Read display mode setting
  local display_mode = G_reader_settings:readSetting("rakuyomi_library_display_mode")
  if not display_mode then
    local settings_response = Backend.getSettings()
    if settings_response.type ~= 'ERROR' and settings_response.body then
      display_mode = settings_response.body.library_display_mode
    end
  end
  display_mode = display_mode or "list"

  -- Cover details are fetched lazily per page inside updateItems(),
  -- so we don't block here.

  local ui = MangaSearchResults:new {
    results = results,
    display_mode = display_mode,
    manga_details = {},
    on_return_callback = onReturnCallback,
    covers_fullscreen = true, -- hint for UIManager:_repaint()
    page = self.page
  }
  ui.on_return_callback = onReturnCallback
  UIManager:show(ui)
  if #response.body[2] > 0 then
    UIManager:show(InfoMessage:new {
      text = formatSearchErrors(response.body[2])
    })
  end

  Testing:emitEvent("manga_search_results_shown")

  return true
end

--- @private
function MangaSearchResults:onPrimaryMenuChoice(item)
  Trapper:wrap(function()
    --- @type Manga
    local manga = item.manga

    -- Capture state before closing — we'll need to build a fresh instance on return
    -- because UIManager:close frees image data in child widgets (LibraryCoverMenuItem).
    local saved_return_callback = self.on_return_callback
    local saved_cover_files = self._search_cover_files

    local onReturnCallback = function()
      local ui = MangaSearchResults:new {
        results = self.results,
        display_mode = self.display_mode,
        manga_details = self.manga_details,
        _search_cover_files = saved_cover_files,
        covers_fullscreen = true,
        page = self.page
      }
      ui.on_return_callback = saved_return_callback
      UIManager:show(ui)
    end

    if ChapterListing:fetchAndShow(manga, onReturnCallback) then
      -- Cancel in-flight async cover fetches and skip cleanup
      self._async_cover_gen = (self._async_cover_gen or 0) + 1
      self._skip_cover_cleanup = true
      UIManager:close(self)
    end
  end)
end

--- @private
function MangaSearchResults:onContextMenuChoice(item)
  --- @type Manga
  local manga = item.manga

  local dialog
  local buttons = {
    {
      {
        text_func = function()
          if manga.in_library then
            return Icons.FA_BELL .. " " .. _("Remove from Library")
          end

          return Icons.FA_BELL .. " " .. _("Add to Library")
        end,
        callback = function()
          UIManager:close(dialog)

          --- @type ErrorResponse
          local err = nil
          if manga.in_library then
            err = Backend.removeMangaFromLibrary(manga.source.id, manga.id)
          else
            err = Backend.addMangaToLibrary(manga.source.id, manga.id)
          end

          if err.type == 'ERROR' then
            ErrorDialog:show(err)

            return
          end

          local added = manga.in_library
          manga.in_library = not added
          self:updateItems()

          Testing:emitEvent(added and "manga_removed_from_library" or "manga_added_to_library", {
            source_id = manga.source.id,
            manga_id = manga.id,
          })
        end
      },
    },
    {
      {
        text = Icons.INFO .. " " .. _("Details"),
        callback = function()
          UIManager:close(dialog)

          Trapper:wrap(function()
            -- Capture the return callback before we close self
            local saved_return_callback = self.on_return_callback
            local saved_cover_files = self._search_cover_files

            local onReturnCallback = function()
              -- Invalidate cached details for this manga so covers refresh if needed
              local sid = (manga.source and manga.source.id) or ""
              local mid = manga.id or ""
              if self.manga_details and sid ~= "" and mid ~= "" then
                self.manga_details[sid .. "/" .. mid] = nil
              end
              local ui = MangaSearchResults:new {
                results = self.results,
                display_mode = self.display_mode,
                manga_details = self.manga_details,
                _search_cover_files = saved_cover_files,
                covers_fullscreen = true, -- hint for UIManager:_repaint()
                page = self.page
              }
              -- Set after new() because init() resets on_return_callback to nil
              ui.on_return_callback = saved_return_callback
              UIManager:show(ui)
            end
            if MangaInfoWidget:fetchAndShow(manga, onReturnCallback) then
              -- Only close search results if Details was actually shown;
              -- cancel async cover fetches and skip cover cleanup —
              -- the new instance inherits our cover files
              self._async_cover_gen = (self._async_cover_gen or 0) + 1
              self._skip_cover_cleanup = true
              UIManager:close(self)
            end
          end)
        end
      }
    },
  }

  dialog = ButtonDialog:new {
    buttons = buttons,
  }

  UIManager:show(dialog)
end

return MangaSearchResults
