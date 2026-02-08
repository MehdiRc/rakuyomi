local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local ImageWidget = require("ui/widget/imagewidget")
local Screen = Device.screen
local MenuItem = require("MenuItem")

local function getCachedCoverSize(img_w, img_h, max_img_w, max_img_h)
  local scale_factor
  local width = math.floor(max_img_h * img_w / img_h + 0.5)
  if max_img_w >= width then
    max_img_w = width
    scale_factor = max_img_w / img_w
  else
    max_img_h = math.floor(max_img_w * img_h / img_w + 0.5)
    scale_factor = max_img_h / img_h
  end
  return max_img_w, max_img_h, scale_factor
end

local LibraryCoverMenuItem = MenuItem:extend {}

function LibraryCoverMenuItem:genCover(wleft_width, wleft_height)
  local border_size = (Size.border and Size.border.thin) or 1
  local scale_by_size = Screen:scaleBySize(1000000) * (1 / 1000000)

  if self.entry.cover_file then
    local ok, wimage = pcall(ImageWidget.new, ImageWidget, {
      file = self.entry.cover_file,
    })
    if ok and wimage then
      local load_ok = pcall(function() wimage:_loadfile() end)
      if load_ok then
        local image_size = wimage:getSize()
        if image_size and image_size.w and image_size.h and image_size.w > 0 and image_size.h > 0 then
          local _, _, scale_factor = getCachedCoverSize(image_size.w, image_size.h, wleft_width, wleft_height)
          wimage = ImageWidget:new {
            file = self.entry.cover_file,
            scale_factor = scale_factor,
          }
          pcall(function() wimage:_render() end)
          image_size = wimage:getSize()
          if image_size and image_size.w and image_size.h then
            local wleft = CenterContainer:new {
              dimen = Geom:new { w = wleft_width, h = wleft_height },
              FrameContainer:new {
                width = image_size.w + 2 * border_size,
                height = image_size.h + 2 * border_size,
                margin = 0,
                padding = 0,
                bordersize = border_size,
                wimage,
              },
            }
            if self.menu then self.menu._has_cover_images = true end
            self._has_cover_image = true
            return wleft
          end
        end
      end
    end
  end

  local function _fontSize(nominal, max)
    local h = (self.dimen and self.dimen.h) or 64
    local font_size = math.floor(nominal * h * (1 / 64) / scale_by_size)
    if max and font_size >= max then
      return max
    end
    return math.max(10, font_size)
  end
  local fake_cover_w = wleft_width - border_size * 2
  local fake_cover_h = wleft_height - border_size * 2
  return CenterContainer:new {
    dimen = Geom:new { w = wleft_width, h = wleft_height },
    FrameContainer:new {
      width = fake_cover_w + 2 * border_size,
      height = fake_cover_h + 2 * border_size,
      margin = 0,
      padding = 0,
      bordersize = border_size,
      dim = true,
      CenterContainer:new {
        dimen = Geom:new { w = fake_cover_w, h = fake_cover_h },
        TextWidget:new {
          text = "\u{26F6}",
          face = Font:getFace("cfont", _fontSize(20)),
        },
      },
    },
  }
end

function LibraryCoverMenuItem:init()
  -- Defensive defaults (base menu may not set all of these)
  self.linesize = self.linesize or Size.line.medium
  self.font = self.font or "smallinfofont"
  self.infont = self.infont or "infont"
  self.line_color = self.line_color or Blitbuffer.COLOR_DARK_GRAY
  self.font_size = self.font_size or 22
  self.infont_size = self.infont_size or (self.font_size - 4)
  self.items_padding = self.items_padding or Size.padding.fullscreen
  if not self.dimen or not self.dimen.w or not self.dimen.h then
    -- Cannot build widget without valid dimen; use minimal placeholder
    self[1] = FrameContainer:new { bordersize = 0, padding = 0, TextWidget:new { text = "", face = Font:getFace("cfont", 12) } }
    return
  end

  self.content_width = self.dimen.w - 2 * Size.padding.fullscreen

  self.ges_events = {
    TapSelect = {
      GestureRange:new {
        ges = "tap",
        range = self.dimen,
      },
    },
    HoldSelect = {
      GestureRange:new {
        ges = self.handle_hold_on_hold_release and "hold_release" or "hold",
        range = self.dimen,
      },
    },
  }

  local max_item_height = self.dimen.h - 2 * self.linesize
  if max_item_height < 1 then max_item_height = 1 end
  -- Use full row height for the cover (capped to row height, not a fixed pixel limit)
  local img_height = max_item_height
  if img_height < 1 then img_height = 1 end
  -- Manga cover aspect ratio ~2:3 (width:height)
  local img_width = math.max(1, math.floor(img_height * 2 / 3))
  local screen_width = Screen:getWidth()
  local gap_width = Screen:scaleBySize(10)
  local text_width = screen_width - gap_width - img_width - 2 * Size.padding.fullscreen
  if text_width < 1 then text_width = 1 end

  -- Count how many text lines we'll show: title(1) + tags(1) + source(1) = up to 3
  local has_tags = self.entry.tags_text and self.entry.tags_text ~= ""
  local has_post = self.entry.post_text and self.entry.post_text ~= ""
  local text_lines = 1 + (has_tags and 1 or 0) + (has_post and 1 or 0)
  if text_lines < 1 then text_lines = 1 end

  -- Scale font sizes to fit all text lines within the available row height
  local max_font_size = TextBoxWidget:getFontSizeToFitHeight(max_item_height, text_lines)
  if self.font_size > max_font_size then
    self.font_size = max_font_size
  end
  -- Info font should be smaller than main font, but also fit
  local max_infont_size = math.min(max_font_size, self.infont_size)
  self.infont_size = max_infont_size

  self.face = Font:getFace(self.font, self.font_size)
  self.info_face = Font:getFace(self.infont, self.infont_size)
  self.post_text_face = Font:getFace(self.font, self.infont_size)

  local mandatory = self.mandatory_func and self.mandatory_func() or self.mandatory or ""
  local mandatory_widget = TextWidget:new {
    text = mandatory,
    face = self.info_face,
    bold = self.bold,
  }
  local mandatory_w = mandatory_widget:getWidth()

  -- Title line: title on left, mandatory (time + bell) on right, same row
  local title_mandatory_padding = Size.span.horizontal_default
  local title_available_width = math.max(1, text_width - mandatory_w - title_mandatory_padding)
  local title_widget = TextWidget:new {
    text = self.entry.text or "",
    face = self.face,
    fgcolor = self.dim and Blitbuffer.COLOR_DARK_GRAY or nil,
    max_width = title_available_width,
  }
  local title_height = math.max(title_widget:getSize().h, mandatory_widget:getSize().h)
  local title_line = OverlapGroup:new {
    dimen = Geom:new { w = text_width, h = title_height },
    LeftContainer:new {
      dimen = Geom:new { w = text_width, h = title_height },
      title_widget,
    },
    RightContainer:new {
      dimen = Geom:new { w = text_width, h = title_height },
      mandatory_widget,
    },
  }

  -- Calculate remaining height after the title for tags + source
  local remaining_height = max_item_height - title_height
  local vertical_children = { title_line }
  if has_tags then
    -- Cap tags height so it doesn't overflow
    local tags_max_height = remaining_height
    if has_post then
      -- Leave room for the source name line
      local post_line_height = TextWidget:new { text = "X", face = self.post_text_face }:getSize().h
      tags_max_height = math.max(1, remaining_height - post_line_height)
    end
    if tags_max_height > 0 then
      table.insert(vertical_children, TextBoxWidget:new {
        text = self.entry.tags_text,
        width = text_width,
        face = self.info_face,
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        height = tags_max_height,
        height_adjust = true,
        height_overflow_show_ellipsis = true,
      })
    end
  end
  if has_post and remaining_height > 0 then
    table.insert(vertical_children, TextWidget:new {
      text = self.entry.post_text,
      face = self.post_text_face,
      fgcolor = Blitbuffer.COLOR_DARK_GRAY,
      max_width = text_width,
    })
  end

  local vg = { align = "left" }
  for i, c in ipairs(vertical_children) do
    vg[i] = c
  end
  local text_container = LeftContainer:new {
    dimen = Geom:new { w = self.content_width, h = self.dimen.h },
    HorizontalGroup:new {
      self:genCover(img_width, img_height),
      HorizontalSpan:new { width = gap_width },
      VerticalGroup:new(vg),
    },
  }

  self._underline_container = UnderlineContainer:new {
    color = self.line_color,
    linesize = 0,
    vertical_align = "center",
    padding = 0,
    dimen = Geom:new {
      x = 0, y = 0,
      w = self.content_width,
      h = self.dimen.h
    },
    HorizontalGroup:new {
      align = "center",
      text_container,
    },
  }

  local hgroup = HorizontalGroup:new {
    align = "center",
    HorizontalSpan:new { width = self.items_padding or Size.padding.fullscreen },
  }
  table.insert(hgroup, self._underline_container)
  table.insert(hgroup, HorizontalSpan:new { width = Size.padding.fullscreen })

  self[1] = FrameContainer:new {
    bordersize = 0,
    padding = 0,
    hgroup,
  }
end

return LibraryCoverMenuItem
