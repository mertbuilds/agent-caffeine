import os

app = os.environ["DMG_APP_PATH"]
appname = os.path.basename(app)

files = [app]
symlinks = {"Applications": "/Applications"}

# Icons centered at y=270 in a 400px-tall window. The background image's
# arrow + headline live above this line; labels render below it. Push the
# DMG's own bookkeeping files (.background.tiff, .DS_Store, etc.) far off
# the visible canvas so users with "show hidden files" enabled don't see
# them in the install window.
icon_locations = {
    appname: (175, 270),
    "Applications": (425, 270),
    ".background.tiff": (5000, 5000),
    ".DS_Store": (5000, 5000),
    ".fseventsd": (5000, 5000),
    ".Trashes": (5000, 5000),
    ".VolumeIcon.icns": (5000, 5000),
}

format = "UDZO"
filesystem = "HFS+"
size = None

window_rect = ((200, 120), (600, 400))
icon_size = 100
text_size = 12

background = os.environ.get("DMG_BACKGROUND", "scripts/dmg-background.png")
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 180
show_icon_preview = False
include_icon_view_settings = "auto"
include_list_view_settings = "auto"
arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)
label_pos = "bottom"
default_view = "icon-view"
