# dmgbuild settings for the Claude HUD disk image (used by scripts/package-release.sh).
# dmgbuild writes the window layout itself, so no Finder scripting is needed.
app = defines["app"]

files = [app]
symlinks = {"Applications": "/Applications"}
icon_locations = {
    "Claude HUD.app": (165, 200),
    "Applications": (495, 200),
    # People who show hidden files would otherwise see these; park them below the window.
    ".background.tiff": (165, 900),
    ".DS_Store": (495, 900),
}
hide_extensions = ["Claude HUD.app"]

background = defines["background"]          # retina TIFF (1x + 2x)
window_rect = ((200, 140), (660, 508))   # 480 pt of content + the title bar
default_view = "icon-view"
icon_size = 112
text_size = 12
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

format = "UDZO"
