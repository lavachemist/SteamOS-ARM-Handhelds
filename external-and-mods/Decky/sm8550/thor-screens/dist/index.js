const manifest = {"name":"Thor Screens"};
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
    return {
        name: "Thor Screens",
        content: jsx(Content, {}),
        icon: jsx("div", { style: { fontWeight: 800 }, children: "☀" }),
        alwaysRender: false,
    };
});

export { index as default };
