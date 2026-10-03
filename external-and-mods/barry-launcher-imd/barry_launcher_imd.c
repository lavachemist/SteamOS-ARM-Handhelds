/*
 * barry_launcher_imd: Barry Launcher's keyboard as KWin's input method
 * (Plasma Desktop Mode on the AYN Thor).
 *
 * KWin starts this as its virtual keyboard (kwinrc [Wayland] InputMethod,
 * a .desktop entry with X-KDE-Wayland-VirtualKeyboard=true) on a private
 * Wayland connection (WAYLAND_SOCKET). It speaks input-method-unstable-v1:
 * KWin says when a text field is activated and what text surrounds the
 * cursor; this types into that field. Barry Launcher's keyboard is its own
 * window on the bottom screen that never takes focus, so it drives this
 * over a local socket ($XDG_RUNTIME_DIR/barry_launcher_im.sock), one line
 * per message.
 *
 * To Barry (JSON, one per line):
 *   {"event":"activate"}  {"event":"deactivate"}  {"event":"reset"}
 *   {"event":"surrounding","text":"...","cursor":N,"anchor":N}  (bytes)
 *   {"event":"content_type","hint":N,"purpose":N}
 * From Barry:
 *   COMMIT <text>      type text
 *   BACK <n>[ <text>]  delete n characters before the cursor, then type text
 *   KEY <name>         Return BackSpace Tab Escape Left Right Up Down Home
 *                      End Delete space
 * A new connection replaces the old one; on connecting it is told whether a
 * field is active.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>

#include "input-method-unstable-v1-client-protocol.h"

static struct wl_display *display;
static struct zwp_input_method_v1 *input_method;
static struct zwp_input_method_context_v1 *context;
static uint32_t serial;
static char *surrounding;  /* last surrounding text, NULL if none */
static uint32_t cursor_pos;
static int listen_fd = -1, client_fd = -1;
static char line[8192];
static size_t line_len;

static void say(const char *json)
{
	if (client_fd < 0)
		return;
	size_t len = strlen(json);
	if (write(client_fd, json, len) != (ssize_t)len || write(client_fd, "\n", 1) != 1) {
		close(client_fd);
		client_fd = -1;
	}
}

/* text as a JSON string, quotes included */
static char *json_string(const char *text)
{
	size_t n = strlen(text);
	char *out = malloc(n * 6 + 3), *p = out;
	if (!out)
		return NULL;
	*p++ = '"';
	for (const unsigned char *s = (const unsigned char *)text; *s; s++) {
		if (*s == '"' || *s == '\\') {
			*p++ = '\\';
			*p++ = *s;
		} else if (*s < 0x20) {
			p += sprintf(p, "\\u%04x", *s);
		} else {
			*p++ = *s;
		}
	}
	*p++ = '"';
	*p = 0;
	return out;
}

static void say_surrounding(void)
{
	if (!surrounding)
		return;
	char *s = json_string(surrounding);
	if (!s)
		return;
	char *msg;
	if (asprintf(&msg, "{\"event\":\"surrounding\",\"text\":%s,\"cursor\":%u,\"anchor\":%u}",
		     s, cursor_pos, cursor_pos) >= 0) {
		say(msg);
		free(msg);
	}
	free(s);
}

static void ctx_surrounding_text(void *data, struct zwp_input_method_context_v1 *c,
				 const char *text, uint32_t cursor, uint32_t anchor)
{
	(void)data; (void)c; (void)anchor;
	free(surrounding);
	surrounding = strdup(text);
	cursor_pos = cursor <= strlen(text) ? cursor : strlen(text);
	say_surrounding();
}

static void ctx_reset(void *data, struct zwp_input_method_context_v1 *c)
{
	(void)data; (void)c;
	say("{\"event\":\"reset\"}");
}

static void ctx_content_type(void *data, struct zwp_input_method_context_v1 *c,
			     uint32_t hint, uint32_t purpose)
{
	(void)data; (void)c;
	char msg[96];
	snprintf(msg, sizeof msg, "{\"event\":\"content_type\",\"hint\":%u,\"purpose\":%u}", hint, purpose);
	say(msg);
}

static void ctx_invoke_action(void *data, struct zwp_input_method_context_v1 *c,
			      uint32_t button, uint32_t index)
{
	(void)data; (void)c; (void)button; (void)index;
}

static void ctx_commit_state(void *data, struct zwp_input_method_context_v1 *c, uint32_t s)
{
	(void)data; (void)c;
	serial = s;
}

static void ctx_preferred_language(void *data, struct zwp_input_method_context_v1 *c,
				   const char *language)
{
	(void)data; (void)c; (void)language;
}

static const struct zwp_input_method_context_v1_listener context_listener = {
	.surrounding_text = ctx_surrounding_text,
	.reset = ctx_reset,
	.content_type = ctx_content_type,
	.invoke_action = ctx_invoke_action,
	.commit_state = ctx_commit_state,
	.preferred_language = ctx_preferred_language,
};

static void forget_context(void)
{
	if (context)
		zwp_input_method_context_v1_destroy(context);
	context = NULL;
	free(surrounding);
	surrounding = NULL;
	cursor_pos = 0;
}

static void im_activate(void *data, struct zwp_input_method_v1 *im,
			struct zwp_input_method_context_v1 *id)
{
	(void)data; (void)im;
	forget_context();
	context = id;
	serial = 0;
	zwp_input_method_context_v1_add_listener(context, &context_listener, NULL);
	say("{\"event\":\"activate\"}");
}

static void im_deactivate(void *data, struct zwp_input_method_v1 *im,
			  struct zwp_input_method_context_v1 *c)
{
	(void)data; (void)im;
	if (c == context) {
		forget_context();
		say("{\"event\":\"deactivate\"}");
	} else {
		zwp_input_method_context_v1_destroy(c);
	}
}

static const struct zwp_input_method_v1_listener input_method_listener = {
	.activate = im_activate,
	.deactivate = im_deactivate,
};

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
			    const char *interface, uint32_t version)
{
	(void)data; (void)version;
	if (strcmp(interface, zwp_input_method_v1_interface.name) == 0) {
		input_method = wl_registry_bind(registry, name, &zwp_input_method_v1_interface, 1);
		zwp_input_method_v1_add_listener(input_method, &input_method_listener, NULL);
	}
}

static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name)
{
	(void)data; (void)registry; (void)name;
}

static const struct wl_registry_listener registry_listener = {
	.global = registry_global,
	.global_remove = registry_global_remove,
};

static uint32_t now_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

static uint32_t keysym_for(const char *name)
{
	static const struct { const char *name; uint32_t sym; } keys[] = {
		{ "Return", 0xff0d }, { "BackSpace", 0xff08 }, { "Tab", 0xff09 },
		{ "Escape", 0xff1b }, { "Left", 0xff51 }, { "Up", 0xff52 },
		{ "Right", 0xff53 }, { "Down", 0xff54 }, { "Home", 0xff50 },
		{ "End", 0xff57 }, { "Delete", 0xffff }, { "space", 0x20 },
	};
	for (size_t i = 0; i < sizeof keys / sizeof keys[0]; i++)
		if (strcmp(name, keys[i].name) == 0)
			return keys[i].sym;
	return 0;
}

static void tap_key(uint32_t sym)
{
	uint32_t t = now_ms();
	zwp_input_method_context_v1_keysym(context, serial, t, sym, WL_KEYBOARD_KEY_STATE_PRESSED, 0);
	zwp_input_method_context_v1_keysym(context, serial, t, sym, WL_KEYBOARD_KEY_STATE_RELEASED, 0);
}

/* Bytes taken by the n characters before the cursor, or -1 if the
 * surrounding text does not reach that far back. */
static long bytes_before_cursor(long n)
{
	if (!surrounding)
		return -1;
	long i = cursor_pos;
	while (n > 0 && i > 0) {
		i--;
		while (i > 0 && ((unsigned char)surrounding[i] & 0xc0) == 0x80)
			i--;
		n--;
	}
	return n > 0 ? -1 : (long)cursor_pos - i;
}

static void command(char *cmd)
{
	if (!context)
		return;
	if (strncmp(cmd, "COMMIT ", 7) == 0) {
		zwp_input_method_context_v1_commit_string(context, serial, cmd + 7);
	} else if (strncmp(cmd, "BACK ", 5) == 0) {
		char *rest;
		long n = strtol(cmd + 5, &rest, 10);
		const char *text = *rest == ' ' ? rest + 1 : "";
		if (n < 0 || n > 1000)
			return;
		long bytes = bytes_before_cursor(n);
		if (bytes >= 0) {
			if (bytes)
				zwp_input_method_context_v1_delete_surrounding_text(context, -(int)bytes, (uint32_t)bytes);
			zwp_input_method_context_v1_commit_string(context, serial, text);
		} else {
			/* No surrounding text from this field: backspace keys. */
			for (long i = 0; i < n; i++)
				tap_key(0xff08);
			if (*text)
				zwp_input_method_context_v1_commit_string(context, serial, text);
		}
	} else if (strncmp(cmd, "KEY ", 4) == 0) {
		uint32_t sym = keysym_for(cmd + 4);
		if (sym)
			tap_key(sym);
	}
	wl_display_flush(display);
}

static void read_client(void)
{
	char buf[4096];
	ssize_t n = read(client_fd, buf, sizeof buf);
	if (n <= 0) {
		close(client_fd);
		client_fd = -1;
		line_len = 0;
		return;
	}
	for (ssize_t i = 0; i < n; i++) {
		if (buf[i] == '\n') {
			line[line_len] = 0;
			command(line);
			line_len = 0;
		} else if (line_len < sizeof line - 1) {
			line[line_len++] = buf[i];
		}
	}
}

static int open_socket(void)
{
	const char *dir = getenv("XDG_RUNTIME_DIR");
	if (!dir)
		return -1;
	struct sockaddr_un addr = { .sun_family = AF_UNIX };
	snprintf(addr.sun_path, sizeof addr.sun_path, "%s/barry_launcher_im.sock", dir);
	unlink(addr.sun_path);
	int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return -1;
	mode_t old = umask(0077);
	int ok = bind(fd, (struct sockaddr *)&addr, sizeof addr) == 0 && listen(fd, 2) == 0;
	umask(old);
	if (!ok) {
		close(fd);
		return -1;
	}
	return fd;
}

int main(void)
{
	signal(SIGPIPE, SIG_IGN);
	display = wl_display_connect(NULL);
	if (!display) {
		fprintf(stderr, "barry_launcher_imd: no Wayland display\n");
		return 1;
	}
	struct wl_registry *registry = wl_display_get_registry(display);
	wl_registry_add_listener(registry, &registry_listener, NULL);
	wl_display_roundtrip(display);
	if (!input_method) {
		fprintf(stderr, "barry_launcher_imd: the compositor offers no zwp_input_method_v1\n");
		return 1;
	}
	listen_fd = open_socket();
	if (listen_fd < 0) {
		perror("barry_launcher_imd: socket");
		return 1;
	}
	fprintf(stderr, "barry_launcher_imd: ready\n");

	for (;;) {
		while (wl_display_prepare_read(display) != 0)
			wl_display_dispatch_pending(display);
		wl_display_flush(display);
		struct pollfd fds[3] = {
			{ .fd = wl_display_get_fd(display), .events = POLLIN },
			{ .fd = listen_fd, .events = POLLIN },
			{ .fd = client_fd, .events = POLLIN },
		};
		if (poll(fds, client_fd >= 0 ? 3 : 2, -1) < 0) {
			wl_display_cancel_read(display);
			if (errno == EINTR)
				continue;
			return 1;
		}
		if (fds[0].revents & POLLIN) {
			if (wl_display_read_events(display) < 0)
				return 1;
		} else {
			wl_display_cancel_read(display);
		}
		if (wl_display_dispatch_pending(display) < 0)
			return 1;
		if (fds[0].revents & (POLLERR | POLLHUP))
			return 1;
		if (fds[1].revents & POLLIN) {
			int fd = accept4(listen_fd, NULL, NULL, SOCK_CLOEXEC);
			if (fd >= 0) {
				if (client_fd >= 0)
					close(client_fd);
				client_fd = fd;
				line_len = 0;
				say(context ? "{\"event\":\"activate\"}" : "{\"event\":\"deactivate\"}");
				say_surrounding();
			}
		}
		if (client_fd >= 0 && (fds[2].revents & (POLLIN | POLLHUP | POLLERR)))
			read_client();
	}
}
