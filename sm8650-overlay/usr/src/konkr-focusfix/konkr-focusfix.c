/*
 * konkr-focusfix — give games their controls back after the Steam overlay.
 *
 * Opening Quick Access / the Steam menu moves X focus to Steam's window;
 * closing it moves focus back to the game, but Proton's winex11 never
 * re-activates the game (no WM_TAKE_FOCUS), so games that ignore input while
 * inactive stay dead until a click (touchscreen) activates them.
 * This watches the X focus on gamescope's Xwayland and, whenever it returns
 * to the window gamescope has focused (a game, not Steam), repeats what a
 * window manager would do for a WM_TAKE_FOCUS client: send it WM_TAKE_FOCUS.
 *
 * Games in exclusive fullscreen also minimize themselves when the overlay
 * takes focus (as on Windows): Wine marks the window Iconic, gamescope stops
 * showing it, and the screen stays black after the overlay closes until
 * Steam's "resume game". So when focus comes back to an Iconic game, its
 * WM_STATE goes back to Normal first, which Wine takes as "restore". Seen
 * only on the AYN Thor, so only there: other devices keep the old behavior.
 *
 *   konkr-focusfix [:0]
 * Build: cc -O2 -o konkr-focusfix konkr-focusfix.c -lX11
 */
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define STEAM_APPID 769

static unsigned long card(Display *d, Window w, Atom a)
{
	Atom t; int f; unsigned long n, r, v = 0; unsigned char *p = NULL;
	if (XGetWindowProperty(d, w, a, 0, 1, False, AnyPropertyType, &t, &f, &n, &r, &p) == Success
	    && p && n && f == 32)
		v = *(unsigned long *)p;
	if (p)
		XFree(p);
	return v;
}

static int ignore_errors(Display *d, XErrorEvent *e) { (void)d; (void)e; return 0; }

/* The device tree's compatible list names the board ("ayn,thor"). */
static int is_ayn_thor(void)
{
	char buf[512];
	FILE *f = fopen("/sys/firmware/devicetree/base/compatible", "rb");
	if (!f)
		return 0;
	size_t n = fread(buf, 1, sizeof(buf), f);
	fclose(f);
	for (size_t i = 0; i < n; i += strnlen(buf + i, n - i) + 1)
		if (strncmp(buf + i, "ayn,thor", n - i) == 0)
			return 1;
	return 0;
}

int main(int argc, char **argv)
{
	const char *name = argc > 1 ? argv[1] : NULL;
	Display *d;
	while (!(d = XOpenDisplay(name)))
		sleep(2);
	XSetErrorHandler(ignore_errors);   /* game windows come and go */
	Window root = DefaultRootWindow(d);
	Atom gs_win = XInternAtom(d, "GAMESCOPE_FOCUSED_WINDOW", False);
	Atom gs_app = XInternAtom(d, "GAMESCOPE_FOCUSED_APP", False);
	Atom proto = XInternAtom(d, "WM_PROTOCOLS", False);
	Atom take = XInternAtom(d, "WM_TAKE_FOCUS", False);
	Atom wm_state = XInternAtom(d, "WM_STATE", False);
	const int restore_minimized = is_ayn_thor();
	fprintf(stderr, "konkr-focusfix: watching%s\n",
	        restore_minimized ? "; restoring games that minimize behind the overlay (AYN Thor)" : "");
	Window last = None;

	for (;;) {
		usleep(250 * 1000);
		Window focus; int rev;
		XGetInputFocus(d, &focus, &rev);
		Window game = card(d, root, gs_win);
		unsigned long app = card(d, root, gs_app);
		if (game && focus == game && last != game && last != None
		    && app && app != STEAM_APPID) {
			usleep(100 * 1000);   /* let Steam finish handing focus back */
			if (restore_minimized && card(d, game, wm_state) == IconicState) {
				long normal[2] = { NormalState, None };
				XChangeProperty(d, game, wm_state, wm_state, 32, PropModeReplace,
				                (unsigned char *)normal, 2);
				fprintf(stderr, "konkr-focusfix: restored minimized 0x%lx (app %lu)\n", game, app);
			}
			/* WM_TAKE_FOCUS only: Wine then activates the window and sets X focus
			 * itself. Also forcing XSetInputFocus + _NET_ACTIVE_WINDOW made Wine
			 * re-grab/warp the pointer -> endless camera spin in Dying Light. */
			XEvent e = { 0 };
			e.xclient.type = ClientMessage;
			e.xclient.window = game;
			e.xclient.message_type = proto;
			e.xclient.format = 32;
			e.xclient.data.l[0] = take;
			e.xclient.data.l[1] = CurrentTime;
			XSendEvent(d, game, False, NoEventMask, &e);
			XFlush(d);
			fprintf(stderr, "konkr-focusfix: re-activated 0x%lx (app %lu)\n", game, app);
		}
		last = focus;
	}
}
