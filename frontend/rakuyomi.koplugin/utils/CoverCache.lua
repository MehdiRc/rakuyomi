local Paths = require("Paths")
local getUrlContent = require("utils/urlContent")
local md5 = require("ffi/sha2").md5

local lfs_ok, lfs = pcall(require, "libs/libkoreader-lfs")
if not lfs_ok then
  lfs = nil
end

local M = {}

local function getCacheDir()
  if not lfs then return nil end
  local dir = Paths.getHomeDirectory() .. "/covers"
  if lfs.attributes(dir, "mode") ~= "directory" then
    lfs.mkdir(dir)
  end
  return dir
end

--- Get file extension from URL (default .jpg).
--- @param url string
--- @return string
local function extensionFromUrl(url)
  local ext = url:match("%.(%w+)(?:%?|$)")
  if ext and (ext == "jpg" or ext == "jpeg" or ext == "png" or ext == "webp" or ext == "gif") then
    return "." .. ext
  end
  return ".jpg"
end

--- Returns a local file path for the cover image, downloading to cache if needed.
--- @param url string Cover URL (http/https) or file:// path
--- @return string|nil Local file path, or nil on failure
--- @return boolean was_downloaded  true if the file was freshly downloaded, false if it was already cached
function M.getCoverPath(url)
  if not url or url == "" then
    return nil, false
  end
  if url:sub(1, 7) == "file://" then
    return url:gsub("^file://", ""), false
  end
  local cache_dir = getCacheDir()
  if not cache_dir or not lfs then
    return nil, false
  end
  local key = md5(url)
  local ext = extensionFromUrl(url)
  local path = cache_dir .. "/" .. key .. ext
  if lfs.attributes(path, "mode") == "file" then
    return path, false
  end
  local ok, content = getUrlContent(url, 15, 45)
  if not ok then return nil, false end
  if type(content) ~= "string" or #content == 0 then
    return nil, false
  end
  local f = io.open(path, "wb")
  if not f then
    return nil, false
  end
  f:write(content)
  f:close()
  return path, true
end

--- Removes a cached cover image for the given URL.
--- @param url string Cover URL (http/https) or file:// path
function M.removeCover(url)
  if not url or url == "" then
    return
  end
  -- Don't delete file:// covers (those are not ours to manage)
  if url:sub(1, 7) == "file://" then
    return
  end
  local cache_dir = getCacheDir()
  if not cache_dir or not lfs then
    return
  end
  local key = md5(url)
  local ext = extensionFromUrl(url)
  local path = cache_dir .. "/" .. key .. ext
  if lfs.attributes(path, "mode") == "file" then
    os.remove(path)
  end
end

return M
