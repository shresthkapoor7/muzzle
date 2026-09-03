import os.path

application = defines["app"]
app_name = os.path.basename(application)

format = "UDZO"
files = [application]
symlinks = {"Applications": "/Applications"}
hide = [".background.png"]

background = defines["background"]
window_rect = ((100, 100), (960, 600))
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
show_icon_preview = False

arrange_by = None
grid_offset = (0, 0)
grid_spacing = 96
icon_size = 112
text_size = 14
label_pos = "bottom"
icon_locations = {
    app_name: (260, 308),
    "Applications": (700, 308),
}
