/* conmux - console bridge for pi-in-xen guests.
 *
 * Bridges /dev/hvc0 (the Xen PV console) to a pty on which the child
 * command (tmux attach, or the fallback shell) runs.
 *
 * Why: the Xen console interface is a pure byte stream with no
 * terminal-size channel (struct xencons_interface has no size fields,
 * the console daemon never forwards the pty winsize, and hvc_xen.c
 * never calls __hvc_resize). The guest's hvc0 therefore stays at a
 * 0x0 winsize, and a tmux client attached to it falls back to 80x25
 * regardless of the local console size.
 *
 * Fix: the dom0 console client (qlvm vm console) pushes the local
 * terminal size in-band as a DCS marker:
 *
 *     ESC P "8;rows;cols" ESC \        (DCS 8 ; rows ; cols ST)
 *
 * conmux intercepts the marker on the hvc0 -> pty leg, applies
 * TIOCSWINSZ to the pty (SIGWINCH to the child), and swallows the
 * marker. All other bytes pass through untouched in both directions.
 *
 * Usage: conmux command [args...]
 * Exits when the child exits.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pty.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#define HVC0	"/dev/hvc0"
#define BUFSZ	4096

/* Marker: ESC P 8 ; rows(1-3) ; cols(1-3) ESC \  (max 13 bytes) */

enum { ST_IDLE, ST_ESC, ST_DCS, ST_RSEP, ST_ROWS, ST_SEP, ST_COLS, ST_ST };

struct mstate {
	int st;
	int rows, cols;
	unsigned char pend[32]; /* marker candidate; replayed on abort */
	int pend_n;
};

static void pty_set_size(int pm, int rows, int cols)
{
	struct winsize ws;

	memset(&ws, 0, sizeof ws);
	ws.ws_row = (unsigned short)rows;
	ws.ws_col = (unsigned short)cols;
	if (ioctl(pm, TIOCSWINSZ, &ws) < 0)
		fprintf(stderr, "conmux: TIOCSWINSZ %dx%d: %s\n",
			rows, cols, strerror(errno));
}

/* Replay the aborted marker candidate into out; returns bytes written. */
static int flush_pend(struct mstate *m, unsigned char *out, int max)
{
	int n = m->pend_n;

	if (n > max)
		n = max;
	if (n > 0)
		memcpy(out, m->pend, n);
	m->pend_n = 0;
	return n;
}

/* Replay the candidate, then emit ch after it. */
static int emit_pend_plus(struct mstate *m, unsigned char ch,
			  unsigned char *out, int max)
{
	int n = flush_pend(m, out, max);

	if (n < max)
		out[n++] = ch;
	return n;
}

/* Feed one byte. Appends to out, or swallows it as part of a completed
 * marker (applying the size). Returns bytes added to out. */
static int mstate_feed(struct mstate *m, int pm, unsigned char ch,
		       unsigned char *out, int max)
{
	switch (m->st) {
	case ST_IDLE:
		if (ch == 0x1b) {
			m->st = ST_ESC;
			m->pend_n = 0;
			m->pend[0] = ch;
			m->pend_n = 1;
			return 0;
		}
		out[0] = ch;
		return 1;
	case ST_ESC:
		if (ch == 'P') {
			m->st = ST_DCS;
			m->pend[m->pend_n++] = ch;
			return 0;
		}
		if (ch == 0x1b)
			return 0; /* restart candidate */
		m->st = ST_IDLE; /* not a marker: replay ESC + byte */
		return emit_pend_plus(m, ch, out, max);
	case ST_DCS:
		if (ch == '8') {
			m->st = ST_RSEP;
			m->pend[m->pend_n++] = ch;
			return 0;
		}
		m->st = ST_IDLE;
		return emit_pend_plus(m, ch, out, max);
	case ST_RSEP:
		if (ch == ';') {
			m->st = ST_ROWS;
			m->rows = m->cols = 0;
			m->pend[m->pend_n++] = ch;
			return 0;
		}
		m->st = ST_IDLE;
		return emit_pend_plus(m, ch, out, max);
	case ST_ROWS:
		if (ch == ';') {
			m->st = ST_SEP;
			m->pend[m->pend_n++] = ch;
			return 0;
		}
		if (ch >= '0' && ch <= '9') {
			m->rows = m->rows * 10 + (ch - '0');
			m->pend[m->pend_n++] = ch;
			if (m->rows <= 999)
				return 0;
		}
		m->st = ST_IDLE;
		return emit_pend_plus(m, ch, out, max);
	case ST_SEP:
		if (ch >= '0' && ch <= '9') {
			m->st = ST_COLS;
			m->cols = ch - '0';
			m->pend[m->pend_n++] = ch;
			return 0;
		}
		m->st = ST_IDLE;
		return emit_pend_plus(m, ch, out, max);
	case ST_COLS:
		if (ch >= '0' && ch <= '9') {
			m->cols = m->cols * 10 + (ch - '0');
			m->pend[m->pend_n++] = ch;
			if (m->cols <= 999)
				return 0;
		} else if (ch == 0x1b) {
			m->st = ST_ST;
			m->pend[m->pend_n++] = ch;
			return 0;
		}
		m->st = ST_IDLE;
		return emit_pend_plus(m, ch, out, max);
	case ST_ST:
		if (ch == '\\') {
			m->st = ST_IDLE;
			m->pend_n = 0;
			if (m->rows >= 2 && m->cols >= 2)
				pty_set_size(pm, m->rows, m->cols);
			return 0; /* swallow the completed marker */
		}
		if (ch == 0x1b) {
			m->pend[m->pend_n++] = ch;
			return 0;
		}
		m->st = ST_IDLE;
		return emit_pend_plus(m, ch, out, max);
	}
	return 0;
}

/* Pump n bytes from buf through the marker filter into out. */
static int pump_marker(struct mstate *m, int pm, const unsigned char *buf,
		       int n, unsigned char *out, int max)
{
	int o = 0;

	for (int i = 0; i < n && o < max; i++)
		o += mstate_feed(m, pm, buf[i], out + o, max - o);
	return o;
}

static void write_full(int fd, const void *p, size_t n)
{
	const unsigned char *b = p;

	while (n > 0) {
		ssize_t w = write(fd, b, n);

		if (w < 0) {
			if (errno == EINTR)
				continue;
			return;
		}
		b += w;
		n -= (size_t)w;
	}
}

int main(int argc, char **argv)
{
	int hvc, pm, ps;
	pid_t pid;
	struct mstate m = { .st = ST_IDLE };

	if (argc < 2) {
		fprintf(stderr, "usage: conmux command [args...]\n");
		return 2;
	}
	/* Do NOT SIG_IGN SIGCHLD: the child (tmux client / shell) must become a
	 * reapable zombie so the waitpid() below detects its exit. (With SIG_IGN
	 * it is auto-reaped and waitpid returns ECHILD, so we could only rely on
	 * the pty EOF — which the line discipline's ECHO can mask while the
	 * client still has the slave open.) */
	signal(SIGPIPE, SIG_IGN);

	hvc = open(HVC0, O_RDWR | O_NOCTTY | O_CLOEXEC);
	if (hvc < 0) {
		fprintf(stderr, "conmux: open %s: %s\n", HVC0, strerror(errno));
		return 1;
	}
	/* Raw mode: no ECHO (else the in-band size marker we filter would be
	 * echoed back into the console stream) and no canonical line
	 * buffering (the child manages its own termios on the pty side). */
	{
		struct termios t;

		if (tcgetattr(hvc, &t) == 0) {
			cfmakeraw(&t);
			tcsetattr(hvc, TCSANOW, &t);
		}
	}

	/* NULL termios = kernel default (cooked + echo), like a real tty. The
	 * child (tmux / interactive shell) configures its own mode; a zeroed
	 * raw pty would leave children that don't reconfigure (e.g. a plain
	 * cat) without input echo. The size marker is swallowed by conmux
	 * before it reaches this pty, so default echo can't leak it. */
	if (openpty(&pm, &ps, NULL, NULL, NULL) < 0) {
		fprintf(stderr, "conmux: openpty: %s\n", strerror(errno));
		return 1;
	}
	pty_set_size(pm, 25, 80); /* initial; the dom0 client updates it */

	pid = fork();
	if (pid < 0) {
		fprintf(stderr, "conmux: fork: %s\n", strerror(errno));
		return 1;
	}
	if (pid == 0) {
		close(hvc);
		close(pm);
		setsid();
		ioctl(ps, TIOCSCTTY, 0);
		dup2(ps, 0);
		dup2(ps, 1);
		dup2(ps, 2);
		if (ps > 2)
			close(ps);
		execvp(argv[1], argv + 1);
		fprintf(stderr, "conmux: exec %s: %s\n", argv[1],
			strerror(errno));
		_exit(127);
	}
	close(ps);

	for (;;) {
		struct pollfd pfds[2];
		int pr;

		pfds[0].fd = hvc;
		pfds[0].events = POLLIN;
		pfds[1].fd = pm;
		pfds[1].events = POLLIN;
		/* 500 ms timeout (not -1): even with no console/pty traffic we wake
		 * to re-check waitpid(), so a child exit is detected promptly
		 * without depending on the pty EOF (which ECHO can mask). */
		pr = poll(pfds, 2, 500);
		if (pr < 0) {
			if (errno == EINTR)
				continue;
			break;
		}
		if (pfds[0].revents & (POLLIN | POLLHUP | POLLERR)) {
			unsigned char buf[BUFSZ], out[BUFSZ * 2];
			ssize_t n = read(hvc, buf, sizeof buf);

			if (n > 0) {
				int o = pump_marker(&m, pm, buf, (int)n,
						    out, (int)sizeof out);

				if (o > 0)
					write_full(pm, out, (size_t)o);
			} else if (n < 0 && errno != EINTR) {
				break;
			}
		}
		if (pfds[1].revents & (POLLIN | POLLHUP | POLLERR)) {
			unsigned char buf[BUFSZ];
			ssize_t n = read(pm, buf, sizeof buf);

			if (n > 0)
				write_full(hvc, buf, (size_t)n);
			else if (n == 0)
				break; /* slave side closed: child gone */
		}
		if (waitpid(pid, NULL, WNOHANG) > 0)
			break; /* child exited */
	}
	return 0;
}
