const manifest = {"name":"KONKR Control"};
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
const toaster = api.toaster;
const definePlugin = (fn) => (...args) => fn(...args);

const DFL = window.DFL;
const SP_REACT = window.SP_REACT;
const SP_JSX = window.SP_JSX;
const { useEffect, useState, useCallback } = SP_REACT;
const jsx = SP_JSX.jsx;
const jsxs = SP_JSX.jsxs;

// Decky callable(): arguments are passed positionally to the Python method.
const getState = callable("get_state");
const setProfile = callable("set_profile");
const setRgb = callable("set_rgb");
const setMcu = callable("set_mcu");
const setFan = callable("set_fan");
const setButton = callable("set_button");
const setPowerLed = callable("set_power_led");
const setButtonsMode = callable("set_buttons_mode");

const PROFILES = [
    { data: "silent", label: "Silent", desc: "Quiet fan, GPU capped at 75%, no game boost" },
    { data: "balanced", label: "Balanced", desc: "Full clocks on demand, game threads on the big cores" },
    { data: "turbo", label: "Turbo", desc: "Big cores held high, GPU floor raised, fan aggressive" },
];
const RGB_PRESETS = [
    { label: "Ember", mode: "static", color: "ff3c00" },
    { label: "Ice", mode: "static", color: "00b4ff" },
    { label: "Violet", mode: "static", color: "a000ff" },
    { label: "White", mode: "static", color: "ffffff" },
    { label: "Breathe", mode: "breath", color: "ff0040" },
    { label: "Off", mode: "off", color: "000000" },
];
const ACTIONS = [
    { data: "rgb-next", label: "Cycle stick lighting" },
    { data: "sticks-toggle", label: "Stick lighting on/off" },
    { data: "profile-next", label: "Cycle performance profile" },
    { data: "fan-boost", label: "Fan boost on/off" },
    { data: "none", label: "Do nothing" },
];

const row = (child) => jsx(DFL.PanelSectionRow, { children: child });
// Separate lines in a field description.
const lines = (...items) => jsx("div", { children: items.map((t, i) => jsx("div", { children: t }, i)) });
const note = (text) => row(jsx("div", { style: { fontSize: "12px", opacity: 0.75 }, children: text }));

function Content() {
    const [st, setSt] = useState(null);
    const refresh = useCallback(() => {
        getState().then(setSt).catch(() => {});
    }, []);
    useEffect(() => {
        refresh();
        const t = setInterval(refresh, 2000);
        return () => clearInterval(t);
    }, [refresh]);

    if (!st) {
        return jsx(DFL.PanelSection, { children: row("Loading…") });
    }
    const prof = PROFILES.find((p) => p.data === st.profile) || PROFILES[1];
    const fan = st.fan || { mode: "auto", fixed: 50, boost: false };
    const buttons = st.buttons || {};
    const steamButtons = (st.buttons_mode || "steam") === "steam";
    const status = [
        st.temp_c != null ? `${st.temp_c} °C` : null,
        st.fan_rpm != null ? `fan ${st.fan_rpm} rpm (${Math.round((st.fan_pwm || 0) / 2.55)}%)` : null,
        st.gpu_mhz != null ? `GPU ${st.gpu_mhz} MHz` : null,
    ].filter(Boolean).join(" · ");

    return jsxs(SP_JSX.Fragment, { children: [
        jsxs(DFL.PanelSection, { title: "Performance", children: [
            row(jsx(DFL.DropdownItem, {
                label: "Profile",
                description: prof.desc,
                rgOptions: PROFILES.map((p) => ({ data: p.data, label: p.label })),
                selectedOption: st.profile,
                onChange: (o) => setProfile(o.data).then(refresh),
            })),
            note(st.daemon ? status : "konkrd is not running"),
        ] }),
        jsxs(DFL.PanelSection, { title: "Fan", children: [
            row(jsx(DFL.DropdownItem, {
                label: "Mode",
                description: fan.mode === "fixed"
                    ? "Fixed speed (switches back to automatic above 90 °C)"
                    : "Automatic, follows the profile's temperature curve",
                rgOptions: [{ data: "auto", label: "Automatic" }, { data: "fixed", label: "Fixed speed" }],
                selectedOption: fan.mode,
                onChange: (o) => setFan(o.data, fan.fixed, fan.boost).then(refresh),
            })),
            fan.mode === "fixed" ? row(jsx(DFL.SliderField, {
                label: "Speed",
                value: fan.fixed, min: 0, max: 100, step: 5, showValue: true, valueSuffix: "%",
                onChange: (v) => setFan("fixed", v, fan.boost),
            })) : row(jsx(DFL.ToggleField, {
                label: "Boost",
                description: "Use the Turbo fan curve with any profile",
                checked: !!fan.boost,
                onChange: (v) => setFan(fan.mode, fan.fixed, v).then(refresh),
            })),
        ] }),
        jsxs(DFL.PanelSection, { title: "Lighting", children: [
            row(jsx(DFL.DropdownItem, {
                label: "Stick lighting",
                disabled: !st.sticks_led,
                description: st.sticks_led ? "" : "Needs the controller MCU link (below)",
                rgOptions: RGB_PRESETS.map((p, i) => ({ data: i, label: p.label })),
                selectedOption: Math.max(0, RGB_PRESETS.findIndex((p) => p.mode === st.rgb.mode && p.color === st.rgb.color)),
                onChange: (o) => {
                    const p = RGB_PRESETS[o.data];
                    setRgb(p.mode, p.color, st.rgb.brightness || 160).then(refresh);
                },
            })),
            row(jsx(DFL.SliderField, {
                label: "Stick brightness",
                value: st.rgb.brightness || 160, min: 10, max: 255, step: 5,
                disabled: !st.sticks_led || st.rgb.mode !== "static",
                onChange: (v) => setRgb(st.rgb.mode, st.rgb.color, v),
            })),
            row(jsx(DFL.ToggleField, {
                label: "Power LED",
                description: "Charging / full / low-battery colours and profile flashes",
                checked: st.power_led !== false,
                onChange: (v) => setPowerLed(v).then(refresh),
            })),
        ] }),
        jsxs(DFL.PanelSection, { title: "Buttons", children: [
            row(jsx(DFL.ToggleField, {
                label: "Steam Remap",
                description: steamButtons
                    ? lines("Custom Function = Left Trackpad Click", "K = Right Trackpad Click", "Bind them in controller settings.")
                    : "Off: buttons map to actions selected below",
                checked: steamButtons,
                onChange: (v) => setButtonsMode(v ? "steam" : "system").then(() => {
                    toaster.toast({ title: "KONKR Control", body: "Buttons switched, controller reconnects" });
                    refresh();
                }),
            })),
            row(jsx(DFL.DropdownItem, {
                label: "Custom Function",
                disabled: steamButtons,
                rgOptions: ACTIONS,
                selectedOption: buttons.F14 || "profile-next",
                onChange: (o) => setButton("F14", o.data).then(refresh),
            })),
            row(jsx(DFL.DropdownItem, {
                label: "K",
                disabled: steamButtons,
                rgOptions: ACTIONS,
                selectedOption: buttons.F13 || "rgb-next",
                onChange: (o) => setButton("F13", o.data).then(refresh),
            })),
            note("Navigation → Steam · = → Quick Access · Power: tap to sleep, hold for the power menu"),
        ] }),
        jsxs(DFL.PanelSection, { title: "Hardware", children: [
            row(jsx(DFL.ToggleField, {
                label: "Controller MCU link",
                description: "Needed for the KONKR, Performance and Quick Access buttons and stick lighting",
                checked: st.mcu_enabled,
                onChange: (v) => setMcu(v).then(() => {
                    toaster.toast({ title: "KONKR Control", body: v ? "MCU link enabled" : "MCU link disabled" });
                    refresh();
                }),
            })),
        ] }),
    ] });
}

// Toast whenever the profile or fan boost changes (K / Custom Function, konkrctl or
// this panel), like Android's on-screen mode switch. Registered at plugin
// load, so it works with Quick Access closed and over games.
const MODE_TOAST = {
    silent: { title: "🌙  Silent", body: "Quiet fan, GPU capped" },
    balanced: { title: "⚖️  Balanced", body: "Full clocks on demand" },
    turbo: { title: "⚡  Turbo", body: "Maximum performance, fan aggressive" },
};
function onMode(profile, boost, profileChanged) {
    const t = profileChanged
        ? MODE_TOAST[profile] || { title: profile, body: "" }
        : { title: boost ? "🌀  Fan boost on" : "🌀  Fan boost off", body: (MODE_TOAST[profile] || {}).title || "" };
    toaster.toast({ title: t.title, body: t.body, duration: 2000, playSound: false, critical: true });
}

var index = definePlugin(() => {
    api.addEventListener("konkr_mode", onMode);
    return {
        name: "KONKR Control",
        content: jsx(Content, {}),
        icon: jsx("div", { style: { fontWeight: 800 }, children: "K" }),
        alwaysRender: false,
        onDismount() {
            api.removeEventListener("konkr_mode", onMode);
        },
    };
});

export { index as default };
