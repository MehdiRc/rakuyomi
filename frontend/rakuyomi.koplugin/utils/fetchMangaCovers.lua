--- Utilities for fetching manga cover images and tags.
---
--- `fetchOneMangaCover(manga)` fetches details for a single manga (used by the
--- async per-item loader).
---
--- `fetchMangaCovers(mangas)` is a convenience wrapper that fetches details for
--- a whole list synchronously (used by the library view).

local Backend = require("Backend")
local logger = require("logger")

local M = {}

local function _source_id(m)
  return (m.source and m.source.id) or ""
end

--- Build the detail key used to store / look up a manga's cover & tags.
--- @param manga table  A manga object with .source.id and .id
--- @return string key  e.g. "mangadex/abc123"
function M.detailKey(manga)
  return _source_id(manga) .. "/" .. (manga.id or "")
end

--- Try to resolve cover image and tags for a single manga using ONLY local data.
--- No network requests are made. Returns nil if details aren't cached yet.
---
--- @param manga table  Manga object with .source.id and .id
--- @return table|nil detail  { cover_file = string|nil, tags = string[] } or nil if not cached
function M.fetchCachedCover(manga)
  local sid = _source_id(manga)
  local mid = manga.id or ""
  if sid == "" or mid == "" then return nil end

  local ok, detail = pcall(function()
    -- Check if we have cached details in the backend DB
    local r = Backend.cachedMangaDetails(Backend.createCancelId(), sid, mid)
    if r.type == "ERROR" or not r.body or not r.body[1] then
      return nil
    end

    local mmanga = r.body[1]
    local cover_src = mmanga.url or mmanga.cover_url
    local cover_file = nil

    if cover_src then
      if cover_src:sub(1, 7) == "file://" then
        cover_file = cover_src:gsub("^file://", "")
      else
        -- Only check if the file already exists on disk; don't download
        local coverCache_ok, coverCache = pcall(require, "utils/coverCache")
        if coverCache_ok and coverCache then
          local lfs_ok, lfs = pcall(require, "libs/libkoreader-lfs")
          if lfs_ok and lfs then
            local md5 = require("ffi/sha2").md5
            local Paths = require("Paths")
            local cache_dir = Paths.getHomeDirectory() .. "/covers"
            local key = md5(cover_src)
            -- Try common extensions
            for _, ext in ipairs({ ".jpg", ".jpeg", ".png", ".webp", ".gif" }) do
              local path = cache_dir .. "/" .. key .. ext
              if lfs.attributes(path, "mode") == "file" then
                cover_file = path
                break
              end
            end
          end
        end
      end
    end

    -- No cover file on disk — not fully cached yet
    if not cover_file then return nil end

    local tags = {}
    if mmanga.tags and type(mmanga.tags) == "table" then
      tags = mmanga.tags
    end

    return { cover_file = cover_file, tags = tags }
  end)

  if not ok then return nil end
  return detail
end

--- Fetch cover image and tags for a **single** manga.
--- Tries the local cache first; falls back to a network refresh.
---
--- @param manga table  Manga object with .source.id and .id
--- @return table|nil detail  { cover_file = string|nil, tags = string[] } or nil on failure
--- @return string|nil cover_path  The downloaded cover file path (for cleanup tracking), or nil
function M.fetchOneMangaCover(manga)
  local sid = _source_id(manga)
  local mid = manga.id or ""
  if sid == "" or mid == "" then return nil, nil end

  local ok, detail, cover_path = pcall(function()
    local coverCache_ok, coverCache = pcall(require, "utils/coverCache")
    if not coverCache_ok or not coverCache then return nil, nil end

    -- Try cached details first
    local r = Backend.cachedMangaDetails(Backend.createCancelId(), sid, mid)

    -- If no cached details, refresh from the source then retry
    if r.type == "ERROR" or not r.body or not r.body[1] then
      pcall(Backend.refreshMangaDetails, Backend.createCancelId(), sid, mid)
      r = Backend.cachedMangaDetails(Backend.createCancelId(), sid, mid)
    end

    if r.type == "ERROR" or not r.body or not r.body[1] then
      return nil, nil
    end

    local mmanga = r.body[1]
    local cover_src = mmanga.url or mmanga.cover_url
    local cover_file = nil
    local downloaded_path = nil

    if cover_src then
      if cover_src:sub(1, 7) == "file://" then
        cover_file = cover_src:gsub("^file://", "")
      else
        local ok_cp, path, was_downloaded = pcall(coverCache.getCoverPath, cover_src)
        if ok_cp and path then
          cover_file = path
          -- Only track as "downloaded" if we actually fetched a new file,
          -- not if it was already in the cache (e.g. from the library).
          if was_downloaded then
            downloaded_path = path
          end
        end
      end
    end

    local tags = {}
    if mmanga.tags and type(mmanga.tags) == "table" then
      tags = mmanga.tags
    end

    return { cover_file = cover_file, tags = tags }, downloaded_path
  end)

  if not ok then
    logger.err("fetchOneMangaCover failed for", sid, mid, ":", detail)
    return nil, nil
  end

  return detail, cover_path
end

--- Fetch covers and tags for a list of manga (synchronous convenience wrapper).
---
--- @param mangas table[] Array of manga objects (each with .source.id and .id)
--- @return table manga_details  Keyed by "source_id/manga_id"
--- @return string[] cover_files  List of downloaded cover file paths (for cleanup)
function M.fetchMangaCovers(mangas)
  local manga_details = {}
  local cover_files = {}

  for _, manga in ipairs(mangas) do
    local detail, cover_path = M.fetchOneMangaCover(manga)
    if detail then
      manga_details[M.detailKey(manga)] = detail
    end
    if cover_path then
      table.insert(cover_files, cover_path)
    end
  end

  return manga_details, cover_files
end

return M
