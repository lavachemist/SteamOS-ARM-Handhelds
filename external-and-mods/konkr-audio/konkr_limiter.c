// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * konkr_limiter: stereo-linked look-ahead peak limiter (LADSPA) for the
 * KONKR Pocket FIT speakers.
 *
 * Applies make-up gain, then keeps both channels at or below the ceiling
 * without clipping: the signal is delayed by the look-ahead time D, and the
 * gain for each output sample is the average of D sliding-window minima,
 * each of which already covers that sample. Every term is therefore at most
 * the gain the sample needs, so the output can never exceed the ceiling,
 * while the gain still moves smoothly over D samples instead of stepping.
 * Release is a one-pole rise that is never allowed above that bound.
 *
 * Latency: D samples (reported on the "latency" port for PipeWire).
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

/* Minimal LADSPA 1.1 ABI (types and constants as in ladspa.h). */
typedef float LADSPA_Data;
typedef void *LADSPA_Handle;
typedef struct {
	int HintDescriptor;
	LADSPA_Data LowerBound;
	LADSPA_Data UpperBound;
} LADSPA_PortRangeHint;
typedef struct LADSPA_Descriptor {
	unsigned long UniqueID;
	const char *Label;
	int Properties;
	const char *Name;
	const char *Maker;
	const char *Copyright;
	unsigned long PortCount;
	const int *PortDescriptors;
	const char *const *PortNames;
	const LADSPA_PortRangeHint *PortRangeHints;
	void *ImplementationData;
	LADSPA_Handle (*instantiate)(const struct LADSPA_Descriptor *, unsigned long);
	void (*connect_port)(LADSPA_Handle, unsigned long, LADSPA_Data *);
	void (*activate)(LADSPA_Handle);
	void (*run)(LADSPA_Handle, unsigned long);
	void (*run_adding)(LADSPA_Handle, unsigned long);
	void (*set_run_adding_gain)(LADSPA_Handle, LADSPA_Data);
	void (*deactivate)(LADSPA_Handle);
	void (*cleanup)(LADSPA_Handle);
} LADSPA_Descriptor;

#define PORT_INPUT 0x1
#define PORT_OUTPUT 0x2
#define PORT_CONTROL 0x4
#define PORT_AUDIO 0x8
#define HINT_BOUNDED_BELOW 0x1
#define HINT_BOUNDED_ABOVE 0x2
#define HINT_DEFAULT_MIDDLE 0xC0
#define HINT_DEFAULT_LOW 0x80
#define HINT_DEFAULT_0 0x200
#define PROP_HARD_RT_CAPABLE 0x4

enum { IN_L, IN_R, OUT_L, OUT_R, GAIN_DB, CEIL_DB, RELEASE_MS, LATENCY, N_PORTS };

#define LOOKAHEAD_S 0.005

typedef struct {
	LADSPA_Data *port[N_PORTS];
	unsigned long rate;
	unsigned D;       /* look-ahead in samples, >= 1 */
	unsigned long n;  /* sample counter */
	float *dl, *dr;   /* delay lines, size D */
	unsigned dpos;
	/* monotonic deque of (index, value) for the sliding minimum over D+1 */
	unsigned long *qi;
	float *qv;
	unsigned qcap, qhead, qlen;
	float *h;         /* last D window minima (boxcar) */
	unsigned hpos;
	double hsum;
	float r;          /* released gain */
} Limiter;

static LADSPA_Handle instantiate(const LADSPA_Descriptor *d, unsigned long rate)
{
	(void)d;
	Limiter *l = calloc(1, sizeof(*l));
	if (!l)
		return NULL;
	l->rate = rate;
	l->D = (unsigned)lrint(LOOKAHEAD_S * rate);
	if (l->D < 1)
		l->D = 1;
	l->qcap = l->D + 2;
	l->dl = calloc(l->D, sizeof(float));
	l->dr = calloc(l->D, sizeof(float));
	l->h = calloc(l->D, sizeof(float));
	l->qi = calloc(l->qcap, sizeof(unsigned long));
	l->qv = calloc(l->qcap, sizeof(float));
	if (!l->dl || !l->dr || !l->h || !l->qi || !l->qv) {
		free(l->dl); free(l->dr); free(l->h); free(l->qi); free(l->qv); free(l);
		return NULL;
	}
	return l;
}

static void connect_port(LADSPA_Handle h, unsigned long port, LADSPA_Data *data)
{
	if (port < N_PORTS)
		((Limiter *)h)->port[port] = data;
}

static void activate(LADSPA_Handle h)
{
	Limiter *l = h;
	memset(l->dl, 0, l->D * sizeof(float));
	memset(l->dr, 0, l->D * sizeof(float));
	for (unsigned i = 0; i < l->D; i++)
		l->h[i] = 1.0f;
	l->hsum = l->D;
	l->dpos = l->hpos = 0;
	l->qhead = l->qlen = 0;
	l->n = 0;
	l->r = 1.0f;
}

static float control(Limiter *l, int p, float def, float lo, float hi)
{
	float v = l->port[p] ? *l->port[p] : def;
	if (!(v >= lo)) /* also catches NaN */
		v = lo;
	return v > hi ? hi : v;
}

static void run(LADSPA_Handle h, unsigned long count)
{
	Limiter *l = h;
	const float gain = powf(10.0f, control(l, GAIN_DB, 0.0f, -24.0f, 24.0f) / 20.0f);
	const float ceil = powf(10.0f, control(l, CEIL_DB, -1.0f, -24.0f, 0.0f) / 20.0f);
	const float rel_ms = control(l, RELEASE_MS, 80.0f, 1.0f, 2000.0f);
	const float rel = 1.0f - expf(-1000.0f / (rel_ms * (float)l->rate));
	const LADSPA_Data *inl = l->port[IN_L], *inr = l->port[IN_R];
	LADSPA_Data *outl = l->port[OUT_L], *outr = l->port[OUT_R];
	const unsigned D = l->D;

	if (l->port[LATENCY])
		*l->port[LATENCY] = (LADSPA_Data)D;
	if (!inl || !inr || !outl || !outr)
		return;

	for (unsigned long i = 0; i < count; i++, l->n++) {
		const float xl = inl[i] * gain, xr = inr[i] * gain;
		float pk = fmaxf(fabsf(xl), fabsf(xr));
		float g = pk > ceil ? ceil / pk : 1.0f;

		/* sliding minimum of g over the last D+1 samples */
		while (l->qlen) {
			unsigned back = (l->qhead + l->qlen - 1) % l->qcap;
			if (l->qv[back] < g)
				break;
			l->qlen--;
		}
		unsigned slot = (l->qhead + l->qlen) % l->qcap;
		l->qi[slot] = l->n;
		l->qv[slot] = g;
		l->qlen++;
		if (l->n >= D && l->qi[l->qhead] < l->n - D) {
			l->qhead = (l->qhead + 1) % l->qcap;
			l->qlen--;
		}
		const float m = l->qv[l->qhead];

		/* boxcar over the last D minima */
		l->hsum += (double)m - l->h[l->hpos];
		l->h[l->hpos] = m;
		l->hpos = (l->hpos + 1) % D;
		float s = (float)(l->hsum / D);
		if (s > 1.0f)
			s = 1.0f;

		/* release: rise toward s, never above it */
		l->r = s < l->r ? s : l->r + (s - l->r) * rel;

		/* delayed output */
		const float dl = l->dl[l->dpos], dr = l->dr[l->dpos];
		l->dl[l->dpos] = xl;
		l->dr[l->dpos] = xr;
		l->dpos = (l->dpos + 1) % D;
		float yl = dl * l->r, yr = dr * l->r;
#ifndef KONKR_LIMITER_NO_CLAMP
		/* float rounding only; the gain above already guarantees this */
		yl = fminf(fmaxf(yl, -ceil), ceil);
		yr = fminf(fmaxf(yr, -ceil), ceil);
#endif
		outl[i] = yl;
		outr[i] = yr;
	}
	/* keep the running sum exact over long runs */
	if ((l->n & 0xFFFF) < count) {
		double s = 0;
		for (unsigned k = 0; k < D; k++)
			s += l->h[k];
		l->hsum = s;
	}
}

static void cleanup(LADSPA_Handle h)
{
	Limiter *l = h;
	free(l->dl); free(l->dr); free(l->h); free(l->qi); free(l->qv); free(l);
}

static const int port_desc[N_PORTS] = {
	PORT_INPUT | PORT_AUDIO, PORT_INPUT | PORT_AUDIO,
	PORT_OUTPUT | PORT_AUDIO, PORT_OUTPUT | PORT_AUDIO,
	PORT_INPUT | PORT_CONTROL, PORT_INPUT | PORT_CONTROL,
	PORT_INPUT | PORT_CONTROL, PORT_OUTPUT | PORT_CONTROL,
};
static const char *const port_names[N_PORTS] = {
	"In L", "In R", "Out L", "Out R",
	"Gain (dB)", "Ceiling (dB)", "Release (ms)", "latency",
};
static const LADSPA_PortRangeHint port_hints[N_PORTS] = {
	{0, 0, 0}, {0, 0, 0}, {0, 0, 0}, {0, 0, 0},
	{HINT_BOUNDED_BELOW | HINT_BOUNDED_ABOVE | HINT_DEFAULT_0, -24.0f, 24.0f},
	{HINT_BOUNDED_BELOW | HINT_BOUNDED_ABOVE | HINT_DEFAULT_MIDDLE, -24.0f, 0.0f},
	{HINT_BOUNDED_BELOW | HINT_BOUNDED_ABOVE | HINT_DEFAULT_LOW, 1.0f, 2000.0f},
	{0, 0, 0},
};

static const LADSPA_Descriptor descriptor = {
	.UniqueID = 0x4b4c4d31, /* "KLM1" */
	.Label = "konkr_limiter",
	.Properties = PROP_HARD_RT_CAPABLE,
	.Name = "KONKR stereo look-ahead limiter",
	.Maker = "SteamOS-ARM-SM8650",
	.Copyright = "GPL-2.0-or-later",
	.PortCount = N_PORTS,
	.PortDescriptors = port_desc,
	.PortNames = port_names,
	.PortRangeHints = port_hints,
	.instantiate = instantiate,
	.connect_port = connect_port,
	.activate = activate,
	.run = run,
	.cleanup = cleanup,
};

const LADSPA_Descriptor *ladspa_descriptor(unsigned long index)
{
	return index == 0 ? &descriptor : NULL;
}
