#pragma once

#include <getopt.h>

#include <atomic>
#include <mutex>
#include <optional>
#include <string_view>
#include <utility>

#include "gamescope_shared.h"

extern const char *gamescope_optstring;
extern const struct option *gamescope_options;

extern std::atomic< bool > g_bRun;

extern int g_nNestedWidth;
extern int g_nNestedHeight;
extern int g_nNestedRefresh; // mHz
extern int g_nNestedUnfocusedRefresh; // mHz
extern int g_nNestedDisplayIndex;

extern uint32_t g_nOutputWidth;
extern uint32_t g_nOutputHeight;
extern bool g_bForceRelativeMouse;
extern int g_nOutputRefresh; // mHz
extern bool g_bOutputHDREnabled;
extern bool g_bForceInternal;
extern bool g_bForceInternalLocked;


extern bool g_bForceCompositionRotation;
extern uint32_t g_uOutputRotation;

extern bool g_bFullscreen;

extern bool g_bGrabbed;

extern float g_mouseSensitivity;
extern const char *g_sOutputName;
extern const char *g_sLeaseConnectorName;
extern const char *g_sDrmLeaseClientSocket;
extern bool g_bDrmLeaseYield;
extern const char *g_sIgnoreTouchDevice;

// Number of companion apps currently holding the DRM lease socket connection.
// Updated by the DRM lease socket thread. When > 0, wlserver drops touch
// events originating from devices matching --ignore-touch-device, so the
// companion exclusively owns them in Game Mode. When 0 (e.g. Desktop Mode
// where the companion isn't running), gamescope forwards touch events
// normally so the bottom touchscreen works in the Plasma session.
extern std::atomic<int> g_nActiveLeaseClients;

// Protocol-frontend holders; each is also counted in g_nActiveLeaseClients.
extern std::atomic<int> g_nProtocolLeaseHolders;

// Lease grants/releases on both frontends mutate the counters under this
// lock; reads stay lock-free.
extern std::mutex g_LeaseGrantMutex;

bool drm_lease_available();
int drm_lease_dup_fd();
int drm_lease_open_enum_fd();
const char *drm_lease_connector_name();
uint32_t drm_lease_connector_id();
void drm_lease_blank();

enum class DrmLeaseEventType : uint32_t
{
	Down = 1,
	Motion,
	Up,
	// Broker to a yielding companion: stop using the lease / take it back.
	Suspend,
	Resume,
};

struct DrmLeaseEvent
{
	DrmLeaseEventType type;
	int32_t touchId;
	uint32_t time;
	float x;
	float y;
};

void drm_lease_send_touch( DrmLeaseEventType type, double x, double y, int touchId, uint32_t time );

// Suspends a yielding companion for a protocol client; true only once it
// acknowledged that nothing of its can commit; false leaves it the holder.
bool drm_lease_companion_suspend( int nTimeoutMs );
void drm_lease_companion_resume();
// True while a connected companion may still commit to the lease.
bool drm_lease_companion_active();

// Companion side (--drm-lease-client). quiesce returns false when a
// present or the flip reader could not be stopped in time.
bool drm_lease_client_suspended();
bool drm_lease_client_quiesce();

enum class GamescopeUpscaleFilter : uint32_t
{
    LINEAR = 0,
    NEAREST,
    FSR,
    NIS,
    PIXEL,
    SGSR,

    FROM_VIEW = 0xF, // internal
};

static constexpr bool UpscaleFilterUsesSharpness( GamescopeUpscaleFilter eFilter )
{
    return eFilter == GamescopeUpscaleFilter::FSR ||
           eFilter == GamescopeUpscaleFilter::NIS ||
           eFilter == GamescopeUpscaleFilter::SGSR;
}

// cs_sgsr reads the plain sampler slot, not the YCbCr one, and thresholds in 8-bit SDR units.
static constexpr bool SgsrSupportsInput( GamescopeAppTextureColorspace eColorspace, bool bYcbcr )
{
    return !bYcbcr && ( eColorspace == GAMESCOPE_APP_TEXTURE_COLORSPACE_LINEAR || eColorspace == GAMESCOPE_APP_TEXTURE_COLORSPACE_SRGB );
}

// Sharp ran FSR before SGSR existed, so HDR keeps that rather than losing the sharpening. Neither pre-pass reads the YCbCr slot.
static constexpr GamescopeUpscaleFilter ResolveUpscaleFilter( GamescopeUpscaleFilter eFilter, GamescopeAppTextureColorspace eColorspace, bool bYcbcr )
{
    if ( eFilter != GamescopeUpscaleFilter::SGSR || SgsrSupportsInput( eColorspace, bYcbcr ) )
        return eFilter;
    return bYcbcr ? GamescopeUpscaleFilter::LINEAR : GamescopeUpscaleFilter::FSR;
}

static constexpr bool DoesHardwareSupportUpscaleFilter( GamescopeUpscaleFilter eFilter )
{
    // Could do nearest someday... AMDGPU DC supports custom tap placement to an extent.

    return eFilter == GamescopeUpscaleFilter::LINEAR;
}

enum class GamescopeUpscaleScaler : uint32_t
{
    AUTO,
    INTEGER,
    FIT,
    FILL,
    STRETCH,
};

struct UpscaleSettings_t
{
    GamescopeUpscaleFilter eFilter{};
    GamescopeUpscaleScaler eScaler{};
    int nSharpness{};
};

// XXX(misyl): This is bad! We shouldnt change the upscaler like this at all!!!
// We should move this to business logic in paint_window or something!
static constexpr UpscaleSettings_t GetUpscaleSettings(
    bool bFocusIsSteam,
    GamescopeUpscaleFilter eWantedFilter,
    GamescopeUpscaleScaler eWantedScaler,
    int nWantedSharpness )
{
    if ( bFocusIsSteam )
        return UpscaleSettings_t{ GamescopeUpscaleFilter::LINEAR, GamescopeUpscaleScaler::FIT, nWantedSharpness };

    return UpscaleSettings_t{ eWantedFilter, eWantedScaler, nWantedSharpness };
}

// One name table for the --filter option and the scaling_filter command, so the two cannot drift.
inline std::optional<GamescopeUpscaleFilter> ParseUpscaleFilter( std::string_view svName )
{
    static constexpr std::pair<std::string_view, GamescopeUpscaleFilter> k_Filters[] =
    {
        { "linear",  GamescopeUpscaleFilter::LINEAR },
        { "nearest", GamescopeUpscaleFilter::NEAREST },
        { "fsr",     GamescopeUpscaleFilter::FSR },
        { "nis",     GamescopeUpscaleFilter::NIS },
        { "pixel",   GamescopeUpscaleFilter::PIXEL },
        { "sgsr",    GamescopeUpscaleFilter::SGSR },
    };
    for ( const auto &[svFilterName, eFilter] : k_Filters )
    {
        if ( svFilterName == svName )
            return eFilter;
    }
    return std::nullopt;
}

extern GamescopeUpscaleFilter g_wantedUpscaleFilter;
extern GamescopeUpscaleScaler g_wantedUpscaleScaler;
extern int g_upscaleFilterSharpness;

extern bool g_bBorderlessOutputWindow;

extern bool g_bExposeWayland;

extern bool g_bRt;

extern int g_nXWaylandCount;
extern bool g_bNoTouchPointerEmulation;

extern uint32_t g_preferVendorID;
extern uint32_t g_preferDeviceID;

