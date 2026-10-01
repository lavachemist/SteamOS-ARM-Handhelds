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
const barryKeyboardOpen = callable("barry_keyboard_open");

// While Barry Launcher's Keyboard app is open on the bottom screen, Steam's
// own on-screen keyboard stays down on the top one: every way Steam opens it
// goes through its keyboard manager's SetVirtualKeyboardShownInternal(show),
// which this wraps. A keyboard already up when the app opens is put away.
let barryKeys = false;
let unhookKeyboard = null;

function keyboardManager() {
    const inst = window.SteamUIStore && window.SteamUIStore.ActiveWindowInstance;
    return inst ? inst.VirtualKeyboardManager || inst.m_VirtualKeyboardManager : null;
}

function hookKeyboard() {
    const mgr = keyboardManager();
    if (!mgr) return null;
    const proto = Object.getPrototypeOf(mgr);
    const orig = proto.SetVirtualKeyboardShownInternal;
    if (typeof orig !== "function" || orig.barryWrapped) return null;
    const wrapped = function (show, ...rest) {
        if (show && barryKeys) return;
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
    const open = await barryKeyboardOpen().catch(() => false);
    if (open && !barryKeys) {
        const mgr = keyboardManager();
        if (mgr && steamKeyboardShowing(mgr)) mgr.SetVirtualKeyboardHidden();
    }
    barryKeys = open;
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
    const timer = setInterval(watchBarryKeyboard, 500);
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
            barryKeys = false;
        },
    };
});

export { index as default };
