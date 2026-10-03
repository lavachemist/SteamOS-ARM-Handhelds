const manifest = {"name":"Barry Launcher"};
const API_VERSION = 2;
const internalAPIConnection = window.__DECKY_SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED_deckyLoaderAPIInit;
if (!internalAPIConnection) {
    throw new Error('[@decky/api]: Failed to connect to the loader as as the loader API was not initialized. This is likely a bug in Decky Loader.');
}
let api;
try {
    api = internalAPIConnection.connect(API_VERSION, manifest.name);
}
catch {
    api = internalAPIConnection.connect(1, manifest.name);
}
const callable = api.callable;
const definePlugin = (fn) => (...args) => fn(...args);

const DFL = window.DFL;
const SP_REACT = window.SP_REACT;
const SP_JSX = window.SP_JSX;
const { useEffect, useState, useCallback, useRef } = SP_REACT;
const jsx = SP_JSX.jsx;
const jsxs = SP_JSX.jsxs;

// Decky callable(): arguments are passed positionally to the Python method.
const getState = callable("get_state");
const setBottomScreen = callable("set_bottom_screen");
const setDimmers = callable("set_dimmers");
const setRgbDimmer = callable("set_rgb_dimmer");
const barryKeyboardAvailable = callable("barry_keyboard_available");
const getTwoScreen = callable("get_two_screen");
const setTwoScreen = callable("set_two_screen");
const openBarryKeyboard = callable("open_barry_keyboard");
const getBarryApps = callable("get_barry_apps");
const setBarryApps = callable("set_barry_apps");

// Steam's on-screen keyboard never shows on the top screen: whenever Steam
// would open it (a text field tapped or picked with the controller, Steam+X),
// Barry Launcher's Keyboard app opens on the bottom screen instead, and
// typing there goes to the field. Every way Steam opens its keyboard goes
// through its keyboard manager's SetVirtualKeyboardShownInternal(show), which
// this wraps. While the bottom screen is off or Barry Launcher is not
// running, Steam's keyboard works as before; so it does when Barry Launcher's
// keyboard cannot be seen (a dual-screen game keeping the bottom screen).
let barryAvailable = false;
let lastOpen = 0;
let unhookKeyboard = null;

function keyboardManager() {
    const inst = window.SteamUIStore && window.SteamUIStore.ActiveWindowInstance;
    return inst ? inst.VirtualKeyboardManager || inst.m_VirtualKeyboardManager : null;
}

function showBarryKeyboard(showSteams) {
    // Steam may ask several times for one tap; bringing the app forward
    // again remaps its window, so once is enough.
    const now = Date.now();
    if (now - lastOpen < 1500) return;
    lastOpen = now;
    openBarryKeyboard()
        .then((shown) => { if (!shown) showSteams(); })
        .catch(() => showSteams());
}

function hookKeyboard() {
    const mgr = keyboardManager();
    if (!mgr) return null;
    const proto = Object.getPrototypeOf(mgr);
    const orig = proto.SetVirtualKeyboardShownInternal;
    if (typeof orig !== "function" || orig.barryWrapped) return null;
    const wrapped = function (show, ...rest) {
        if (show && barryAvailable) {
            showBarryKeyboard(() => orig.call(this, show, ...rest));
            return;
        }
        return orig.call(this, show, ...rest);
    };
    wrapped.barryWrapped = true;
    proto.SetVirtualKeyboardShownInternal = wrapped;
    return () => { proto.SetVirtualKeyboardShownInternal = orig; };
}

function steamKeyboardShowing(mgr) {
    // A subscribable value ({ Value, m_currentValue }) in current Steam builds.
    const v = mgr.IsShowingVirtualKeyboard;
    if (typeof v === "function") return !!v.call(mgr);
    if (v && typeof v === "object") return !!(v.Value !== undefined ? v.Value : v.m_currentValue);
    return !!v;
}

async function watchBarryKeyboard() {
    if (!unhookKeyboard) unhookKeyboard = hookKeyboard();
    const available = await barryKeyboardAvailable().catch(() => false);
    if (available && !barryAvailable) {
        // A Steam keyboard left up from before goes away.
        const mgr = keyboardManager();
        if (mgr && steamKeyboardShowing(mgr)) mgr.SetVirtualKeyboardHidden();
    }
    barryAvailable = available;
}

const row = (child) => jsx(DFL.PanelSectionRow, { children: child });

// Tab icons: outlines in the text colour, 24x24.
const svg = (children) => jsx("svg", {
    width: 22, height: 22, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
    strokeWidth: 1.6, strokeLinecap: "round", strokeLinejoin: "round", children,
});
// The Thor, open: the top screen above the hinge, the bottom screen between
// the sticks.
const ThorIcon = () => svg([
    jsx("rect", { x: 4, y: 1.5, width: 16, height: 9.5, rx: 1.5 }, "lid"),
    jsx("rect", { x: 6, y: 3.2, width: 12, height: 6.1, rx: 0.5 }, "top"),
    jsx("path", { d: "M3 12.5h18v6.5a3.5 3.5 0 0 1-3.5 3.5h-11A3.5 3.5 0 0 1 3 19z" }, "body"),
    jsx("rect", { x: 9, y: 14, width: 6, height: 5, rx: 0.5 }, "bottom"),
    jsx("circle", { cx: 6, cy: 16.5, r: 1.3 }, "ls"),
    jsx("circle", { cx: 18, cy: 16.5, r: 1.3 }, "rs"),
]);
// A stick seen from above inside its ring of light, red, green and blue.
const RgbIcon = () => svg([
    jsx("circle", { cx: 12, cy: 12, r: 4.2 }, "stick"),
    jsx("circle", { cx: 12, cy: 12, r: 1.4, fill: "currentColor" }, "cap"),
    jsx("path", { d: "M12 3.5a8.5 8.5 0 0 1 7.36 4.25", stroke: "#ff4d4d", strokeWidth: 2.2 }, "r"),
    jsx("path", { d: "M19.36 16.25A8.5 8.5 0 0 1 12 20.5", stroke: "#4dd96b", strokeWidth: 2.2 }, "g"),
    jsx("path", { d: "M4.64 16.25A8.5 8.5 0 0 1 4.64 7.75", stroke: "#4d8dff", strokeWidth: 2.2 }, "b"),
]);
// A Game Boy: screen, d-pad, A and B.
const HandheldIcon = () => svg([
    jsx("path", { d: "M6.5 1.5h11a1.5 1.5 0 0 1 1.5 1.5v15.5a4 4 0 0 1-4 4H6.5A1.5 1.5 0 0 1 5 21V3a1.5 1.5 0 0 1 1.5-1.5z" }, "body"),
    jsx("rect", { x: 7.5, y: 4, width: 9, height: 7, rx: 0.5 }, "screen"),
    jsx("path", { d: "M8.5 16.5h3M10 15v3" }, "dpad"),
    jsx("circle", { cx: 14, cy: 17.6, r: 1.15, fill: "currentColor", stroke: "none" }, "b"),
    jsx("circle", { cx: 16.6, cy: 15.6, r: 1.15, fill: "currentColor", stroke: "none" }, "a"),
]);

// Barry Launcher's home: a 2x2 grid of app tiles.
const AppsIcon = () => svg([
    jsx("rect", { x: 3, y: 3, width: 7.5, height: 7.5, rx: 2 }, "a"),
    jsx("rect", { x: 13.5, y: 3, width: 7.5, height: 7.5, rx: 2 }, "b"),
    jsx("rect", { x: 3, y: 13.5, width: 7.5, height: 7.5, rx: 2 }, "c"),
    jsx("rect", { x: 13.5, y: 13.5, width: 7.5, height: 7.5, rx: 2 }, "d"),
]);

// LB and RB: the controller's bumpers, in Steam's button numbering.
const GB = DFL.GamepadButton || {};
const BUMPER_LEFT = GB.BUMPER_LEFT != null ? GB.BUMPER_LEFT : 5;
const BUMPER_RIGHT = GB.BUMPER_RIGHT != null ? GB.BUMPER_RIGHT : 6;

// The tab shown, kept while Steam runs.
let lastTab = "screens";

function TabBar({ tabs, active, onPick }) {
    return jsx(DFL.Focusable, {
        "flow-children": "horizontal",
        style: { display: "flex", gap: "6px", padding: "0 16px 8px" },
        children: tabs.map((t) => jsx(DFL.DialogButton, {
            onClick: () => onPick(t.id),
            style: {
                flex: 1, minWidth: 0, height: "40px", padding: 0,
                display: "flex", alignItems: "center", justifyContent: "center",
                ...(t.id === active
                    ? { background: "#1a9fff", color: "#fff" }
                    : { opacity: 0.8 }),
            },
            children: jsx(t.icon, {}),
        }, t.id)),
    });
}
const note = (text) => row(jsx("div", { style: { fontSize: "12px", opacity: 0.75 }, children: text }));

// Sliders send while they move, at most this often, and the last value
// always; the periodic refresh leaves them alone until a while after.
const SEND_MS = 120;
const HOLD_MS = 2000;

function useThrottled(send) {
    const t = useRef({ at: 0, timer: null, value: null });
    return useCallback((value) => {
        const s = t.current;
        s.value = value;
        if (s.timer) return;
        const wait = Math.max(0, s.at + SEND_MS - Date.now());
        s.timer = setTimeout(() => {
            s.timer = null;
            s.at = Date.now();
            send(s.value);
        }, wait);
    }, [send]);
}

// The user's emulators set to put their second screen in a window of its
// own, which gamescope shows on the bottom screen (the backend changes only
// their config files, and puts them back when this goes off).
function TwoScreenSection() {
    const [ts, setTs] = useState(null);
    const [busy, setBusy] = useState(false);
    const [err, setErr] = useState("");
    const load = useCallback(() => { getTwoScreen().then(setTs).catch(() => {}); }, []);
    useEffect(() => {
        load();
        const t = setInterval(load, 5000);
        return () => clearInterval(t);
    }, [load]);
    if (!ts) return null;
    const found = ts.emulators || [];
    const names = [...new Set(found.map((e) => e.name))];
    const set = [...new Set(found.filter((e) => e.twoScreens).map((e) => e.name))];
    const description = !found.length
        ? "No melonDS, Azahar, Lime3DS, Citra or Cemu settings found yet: open the emulator once, then come back."
        : ts.enabled
            ? `Two screens: ${set.join(", ") || "none"}${set.length < names.length ? ` (${names.filter((n) => !set.includes(n)).join(", ")}: once it is closed)` : ""}.`
            : `Found: ${names.join(", ")}.`;
    return jsxs(DFL.PanelSection, { title: "Emulators", children: [
        row(jsx(DFL.ToggleField, {
            label: "Two-screen emulators",
            description,
            checked: !!ts.enabled,
            disabled: busy || !found.length,
            onChange: (v) => {
                setBusy(true);
                setErr("");
                setTwoScreen(v).then((r) => {
                    if (r && !r.ok) setErr(r.error || "Could not change the emulators' settings.");
                }).catch(() => setErr("Could not change the emulators' settings.")).finally(() => {
                    setBusy(false);
                    load();
                });
            },
        })),
        err && note(err),
        ts.dsOnRetroArch > 0 && note(`${ts.dsOnRetroArch} DS game${ts.dsOnRetroArch === 1 ? "" : "s"} in Steam start${ts.dsOnRetroArch === 1 ? "s" : ""} in RetroArch, which shows both screens on the top one. To use the bottom screen, in Desktop Mode open Steam ROM Manager, turn off the RetroArch DS parser, turn on "Nintendo DS - melonDS (Standalone)" and add the games again. Copy your saves over first: they stay with RetroArch.`),
    ] });
}

// Barry Launcher's home screen: each app shown or hidden, and moved up or
// down (barry_launcher_shelld keeps them; the home screen follows within a
// second).
function AppsSection() {
    const [apps, setApps] = useState(null);
    const [err, setErr] = useState("");
    const load = useCallback(() => {
        getBarryApps().then((r) => {
            if (r && r.ok) { setApps(r.apps); setErr(""); }
            else setErr((r && r.error) || "Barry Launcher isn't answering.");
        }).catch(() => setErr("Barry Launcher isn't answering."));
    }, []);
    useEffect(load, [load]);
    const save = (next) => {
        setApps(next);
        setBarryApps(next.map((a) => a.id), next.filter((a) => a.hidden).map((a) => a.id))
            .then((r) => { if (r && r.ok) setApps(r.apps); else setErr((r && r.error) || "Could not save."); })
            .catch(() => setErr("Could not save."));
    };
    const move = (i, by) => {
        const j = i + by;
        if (!apps || j < 0 || j >= apps.length) return;
        const next = apps.slice();
        [next[i], next[j]] = [next[j], next[i]];
        save(next);
    };
    const button = (label, onClick, disabled) => jsx(DFL.DialogButton, {
        onClick, disabled,
        style: { minWidth: "36px", width: "36px", height: "32px", padding: 0, marginLeft: "4px" },
        children: label,
    });
    return jsxs(DFL.PanelSection, { title: "Apps", children: [
        err && note(err),
        ...(apps || []).map((a, i) => row(jsxs(DFL.Focusable, {
            "flow-children": "horizontal",
            style: { display: "flex", alignItems: "center" },
            children: [
                jsx("div", { style: { flex: 1, opacity: a.hidden ? 0.5 : 1 }, children: a.name }),
                button("▲", () => move(i, -1), i === 0),
                button("▼", () => move(i, 1), i === apps.length - 1),
                jsx("div", { style: { marginLeft: "10px" }, children: jsx(DFL.Toggle, {
                    value: !a.hidden,
                    onChange: (v) => save(apps.map((b) => (b.id === a.id ? { ...b, hidden: !v } : b))),
                }) }),
            ],
        }), )),
        apps && note("Switch: shown on Barry Launcher's home screen. ▲ ▼: its place there."),
    ] });
}

function Content() {
    const [tab, setTab] = useState(lastTab);
    const pick = (id) => { lastTab = id; setTab(id); };
    const [st, setSt] = useState(null);
    // The "both screens" slider: where it was last put, or the common level.
    const [both, setBoth] = useState(null);
    const movedAt = useRef(0);
    const refresh = useCallback(() => {
        if (Date.now() - movedAt.current < HOLD_MS) return;
        getState().then((s) => {
            if (Date.now() - movedAt.current < HOLD_MS) return;
            setSt(s);
            if (s && s.dimmers && s.dimmers.top === s.dimmers.bottom) setBoth(s.dimmers.top);
        }).catch(() => {});
    }, []);
    const sendDimmers = useThrottled(useCallback((d) => { setDimmers(d.top, d.bottom).catch(() => {}); }, []));
    const sendRgb = useThrottled(useCallback((v) => { setRgbDimmer(v).catch(() => {}); }, []));
    const dim = (top, bottom) => {
        movedAt.current = Date.now();
        setSt((s) => ({ ...s, dimmers: { top, bottom } }));
        sendDimmers({ top, bottom });
    };
    useEffect(() => {
        refresh();
        const t = setInterval(refresh, 3000);
        return () => clearInterval(t);
    }, [refresh]);

    if (!st) return jsx(DFL.PanelSection, { children: note("Loading…") });
    if (!st.supported) return jsx(DFL.PanelSection, { children: note("This plugin is for the AYN Thor (two screens).") });

    const d = st.dimmers || { top: 100, bottom: 100 };
    const slider = (label, value, min, onChange, extra) => row(jsx(DFL.SliderField, {
        label: `${label} (${value}%)`, value, min, max: 100, step: 5, onChange, ...extra,
    }));
    const tabs = [
        { id: "screens", icon: ThorIcon },
        { id: "apps", icon: AppsIcon },
        ...(st.rgbDimmer != null ? [{ id: "lights", icon: RgbIcon }] : []),
        { id: "emulators", icon: HandheldIcon },
    ];
    const shown = tabs.some((t) => t.id === tab) ? tab : "screens";
    const step = (by) => {
        const i = tabs.findIndex((t) => t.id === shown);
        pick(tabs[(i + by + tabs.length) % tabs.length].id);
    };
    return jsxs(DFL.Focusable, {
        onButtonDown: (evt) => {
            const b = evt && evt.detail && evt.detail.button;
            if (b === BUMPER_LEFT) step(-1);
            else if (b === BUMPER_RIGHT) step(1);
        },
        children: [jsx(TabBar, { tabs, active: shown, onPick: pick }),
    shown === "screens" && jsxs(DFL.PanelSection, { title: "Dual Screen", children: [
        row(jsx(DFL.ToggleField, {
            label: "Bottom screen",
            description: st.on ? undefined : "Off: dark and ignoring touch until you turn it back on.",
            checked: !!st.on,
            onChange: (v) => {
                setSt((s) => ({ ...s, on: v }));
                setBottomScreen(v).then(refresh).catch(refresh);
            },
        })),
        slider("Top screen dimmer", d.top, 10, (v) => dim(v, d.bottom)),
        slider("Bottom screen dimmer", d.bottom, 10, (v) => dim(d.top, v), { disabled: !st.on }),
        slider("Both screens", both != null ? both : Math.max(d.top, d.bottom), 10, (v) => {
            setBoth(v);
            dim(v, v);
        }),
        note("Steam's brightness slider moves both screens together, each at its own setting here."),
    ] }),
    shown === "lights" && jsxs(DFL.PanelSection, { title: "RGB Lighting", children: [
        slider("Lights dimmer", st.rgbDimmer, 20, (v) => {
            movedAt.current = Date.now();
            setSt((s) => ({ ...s, rgbDimmer: v }));
            sendRgb(v);
        }),
        note("The dashboard's 100% lights button is this bright; 25% and 50% are shares of it."),
    ] }),
    shown === "apps" && jsx(AppsSection, {}),
    shown === "emulators" && jsx(TwoScreenSection, {}),
    ] });
}

var index = definePlugin(() => {
    const timer = setInterval(watchBarryKeyboard, 2000);
    watchBarryKeyboard();
    return {
        name: "Barry Launcher",
        content: jsx(Content, {}),
        icon: jsx("div", { style: { fontWeight: 800 }, children: "☀" }),
        alwaysRender: false,
        onDismount() {
            clearInterval(timer);
            if (unhookKeyboard) unhookKeyboard();
            unhookKeyboard = null;
            barryAvailable = false;
        },
    };
});

export { index as default };
