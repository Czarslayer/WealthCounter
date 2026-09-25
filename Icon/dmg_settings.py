# dmgbuild layout for WealthCounter.dmg. Coordinates match Icon/make_dmg_background.swift.
app = defines.get("app", "/Applications/RealTimeCounter.app")  # noqa: F821 (provided by dmgbuild)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = "Icon/AppIcon.icns"                   # volume icon on the desktop
background = ".build/dmg-background.png"     # @2x sibling is picked up for Retina

window_rect = ((200, 120), (640, 480))  # 450pt of content + title and bottom bars
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 13
icon_locations = {
    "RealTimeCounter.app": (160, 230),
    "Applications": (480, 230),
}
