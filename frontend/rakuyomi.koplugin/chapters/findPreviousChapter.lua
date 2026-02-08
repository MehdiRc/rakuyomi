--- Finds the index of the given chapter on the chapter listing.
---
--- @param haystack Chapter[] The chapter listing.
--- @param needle Chapter The chapter being looked for.
--- @return number|nil The index of the chapter on the listing, or nil, if it could not be found.
--- @private
local function findChapterIndex(haystack, needle)
  local function isSameChapter(a, b)
    return a.source_id == b.source_id and a.manga_id == b.manga_id and a.id == b.id
  end

  for i, chapter in ipairs(haystack) do
    if isSameChapter(chapter, needle) then
      return i
    end
  end

  return nil
end

--- Attempts to find the previous chapter from the given chapter, comparing by chapter number.
--- If multiple candidates are found, we'll attempt to pick a chapter belonging to
--- the same scanlation group.
--- If no candidate is found, a previous chapter will be determined from the source order,
--- the chapter right before the current one.
---
--- @param chapters Chapter[] The list of chapters of the manga.
--- @param current_chapter Chapter The current chapter.
--- @return Chapter|nil chapter The previous chapter, if found, or nil.
local function findPreviousChapter(chapters, current_chapter)
  local best_candidate = nil

  for i, candidate in ipairs(chapters) do
    if candidate.chapter_num == nil or current_chapter.chapter_num == nil then
      goto continue
    end

    if candidate.chapter_num >= current_chapter.chapter_num then
      goto continue
    end

    if best_candidate == nil then
      best_candidate = candidate
    end

    if candidate.chapter_num < best_candidate.chapter_num then
      goto continue
    end

    -- Now, we either have a chapter that's before our current chapter and at or after
    -- our current best candidate. Check whether it's a better candidate:
    -- - if it's closer to the current chapter number (higher chapter_num);
    -- - if it belongs to the same scanlation group.
    if candidate.chapter_num > best_candidate.chapter_num then
      best_candidate = candidate
    elseif current_chapter.scanlator ~= nil and candidate.scanlator == current_chapter.scanlator then
      best_candidate = candidate
    end

    ::continue::
  end

  if best_candidate ~= nil then
    return best_candidate
  end

  -- If finding by the chapter number fails, try to find the chapter before this one.
  -- The previous chapter should come _after_ the current one in the `chapters` array, as the
  -- source order is from newer chapters -> older chapters.
  local index = findChapterIndex(chapters, current_chapter)
  assert(index ~= nil)

  if index < #chapters then
    return chapters[index + 1]
  end

  -- Everything failed. We have no previous chapter.
  return nil
end

return findPreviousChapter
