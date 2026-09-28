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
const { useEffect, useState, useCallback, useRef } = SP_REACT;
const jsx = SP_JSX.jsx;
const jsxs = SP_JSX.jsxs;

// Decky callable(): arguments are passed positionally to the Python method.
const getState = callable("get_state");
const setTop = callable("set_top");
const setBottom = callable("set_bottom");
const match = callable("match");

const row = (child) => jsx(DFL.PanelSectionRow, { children: child });
const note = (text) => row(jsx("div", { style: { fontSize: "12px", opacity: 0.75 }, children: text }));

function Content() {
    const [st, setSt] = useState(null);
    // Don't let the periodic refresh jump a slider the user is dragging.
    const lastMove = useRef(0);
    const refresh = useCallback(() => {
        if (Date.now() - lastMove.current < 1500) return;
        getState().then(setSt).catch(() => {});
    }, []);
    useEffect(() => {
        refresh();
        const t = setInterval(refresh, 2000);
        return () => clearInterval(t);
    }, [refresh]);

    if (!st) return jsx(DFL.PanelSection, { children: note("Loading…") });
    if (!st.supported) return jsx(DFL.PanelSection, { children: note("This plugin is for the AYN Thor (two screens).") });

    const move = (key, fn) => (v) => {
        lastMove.current = Date.now();
        setSt((s) => ({ ...s, [key]: v }));
        fn(v).catch(() => {});
    };

    return jsxs(DFL.PanelSection, { title: "Brightness", children: [
        row(jsx(DFL.SliderField, {
            label: "Top screen",
            value: st.top, min: 1, max: 100, step: 1, showValue: true, valueSuffix: "%",
            onChange: move("top", setTop),
        })),
        row(jsx(DFL.SliderField, {
            label: "Bottom screen",
            value: st.bottom, min: 1, max: 100, step: 1, showValue: true, valueSuffix: "%",
            onChange: move("bottom", setBottom),
        })),
        row(jsx(DFL.ButtonItem, {
            layout: "below",
            onClick: () => match().then(() => { lastMove.current = 0; refresh(); }),
            children: "Match bottom to top",
        })),
        note("Steam's brightness slider sets both screens to the same level. These sliders change one screen until you use Steam's slider again."),
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
