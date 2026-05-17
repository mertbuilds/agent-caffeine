import os

app = os.environ["DMG_APP_PATH"]
appname = os.path.basename(app)

files = [app]
symlinks = {"Applications": "/Applications"}

icon_locations = {
    appname: (175, 200),
    "Applications": (425, 200),
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
