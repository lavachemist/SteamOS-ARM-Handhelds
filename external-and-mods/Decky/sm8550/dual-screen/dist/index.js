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
const { useEffect, useState, useCallback } = SP_REACT;
const jsx = SP_JSX.jsx;
const jsxs = SP_JSX.jsxs;

// Decky callable(): arguments are passed positionally to the Python method.
const getState = callable("get_state");
const setBottomScreen = callable("set_bottom_screen");
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

function Content() {
    const [st, setSt] = useState(null);
    const refresh = useCallback(() => {
        getState().then(setSt).catch(() => {});
    }, []);
    useEffect(() => {
        refresh();
        const t = setInterval(refresh, 3000);
        return () => clearInterval(t);
    }, [refresh]);

    if (!st) return jsx(DFL.PanelSection, { children: note("Loading…") });
    if (!st.supported) return jsx(DFL.PanelSection, { children: note("This plugin is for the AYN Thor (two screens).") });

    return jsxs(DFL.PanelSection, { children: [
        row(jsx(DFL.ToggleField, {
            label: "Bottom screen",
            description: st.on
                ? "On, at the same brightness as the top screen."
                : "Off: dark and ignoring touch until you turn it back on.",
            checked: !!st.on,
            onChange: (v) => {
                setSt((s) => ({ ...s, on: v }));
                setBottomScreen(v).then(refresh).catch(refresh);
            },
        })),
        note("Steam's brightness slider sets both screens."),
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
