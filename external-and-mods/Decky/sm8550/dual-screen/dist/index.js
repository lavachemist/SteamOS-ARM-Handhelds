const manifest = {"name":"Dual Screen"};
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
const openBarryKeyboard = callable("open_barry_keyboard");

// Steam's on-screen keyboard never shows on the top screen: whenever Steam
// would open it (a text field tapped or picked with the controller, Steam+X),
// Barry Launcher's Keyboard app opens on the bottom screen instead, and
// typing there goes to the field. Every way Steam opens its keyboard goes
// through its keyboard manager's SetVirtualKeyboardShownInternal(show), which
// this wraps. While the bottom screen is off or Barry Launcher is not
// running, Steam's keyboard works as before.
let barryAvailable = false;
let lastOpen = 0;
let unhookKeyboard = null;

function keyboardManager() {
    const inst = window.SteamUIStore && window.SteamUIStore.ActiveWindowInstance;
    return inst ? inst.VirtualKeyboardManager || inst.m_VirtualKeyboardManager : null;
}

function showBarryKeyboard() {
    // Steam may ask several times for one tap; bringing the app forward
    // again remaps its window, so once is enough.
    const now = Date.now();
    if (now - lastOpen < 1500) return;
    lastOpen = now;
    openBarryKeyboard().catch(() => {});
}

function hookKeyboard() {
    const mgr = keyboardManager();
    if (!mgr) return null;
    const proto = Object.getPrototypeOf(mgr);
    const orig = proto.SetVirtualKeyboardShownInternal;
    if (typeof orig !== "function" || orig.barryWrapped) return null;
    const wrapped = function (show, ...rest) {
        if (show && barryAvailable) {
            showBarryKeyboard();
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

function Content() {
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
    return jsxs(SP_REACT.Fragment, { children: [jsxs(DFL.PanelSection, { title: "Screens", children: [
        row(jsx(DFL.ToggleField, {
            label: "Bottom screen",
            description: st.on
                ? "On."
                : "Off: dark and ignoring touch until you turn it back on.",
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
    st.rgbDimmer != null && jsxs(DFL.PanelSection, { title: "Stick lights", children: [
        slider("Lights dimmer", st.rgbDimmer, 20, (v) => {
            movedAt.current = Date.now();
            setSt((s) => ({ ...s, rgbDimmer: v }));
            sendRgb(v);
        }),
        note("The dashboard's 100% lights button is this bright; 25% and 50% are shares of it."),
    ] }),
    ] });
}

var index = definePlugin(() => {
    const timer = setInterval(watchBarryKeyboard, 2000);
    watchBarryKeyboard();
    return {
        name: "Dual Screen",
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
