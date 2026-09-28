// The AYN Thor bottom screen's base window during Game Mode: the first
// window of the bottom session, under everything else. gamescope shows the
// most recently shown window, so when an overlay such as the dashboard
// hides, the screen falls back to this instead of freezing on the overlay's
// last frame. Plain black for now (pixels off on the AMOLED panel).
import QtQuick
import QtQuick.Window

Window {
    title: "Bottom Screen"
    color: "black"
    visibility: Window.FullScreen
    visible: true
}
