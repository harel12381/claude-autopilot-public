"""Whether the computer is too busy to judge a check of the /ap:qa sweep. A check of time or frames
that fails only because the computer is slow is told, not judged (BUSY_NOTE). Two signs: the page
loses frames standing still (BUSY_MS), or other work than the sweep's own keeps the CPU busy
(BUSY_LOAD, OtherLoad). busy_computer() takes either."""

import contextlib
import time

# Standing still, frames this long (p95, ms) mean the computer is busy.
BUSY_MS = 50

# In the words of a check that passed only because it could not be judged (a busy computer, a
# deploy beside it, nothing to judge): it is marked TOLD, not ok, and listed at the end.
NOT_JUDGED = 'not judged'

# Said of a check on a busy computer.
BUSY_NOTE = '; computer busy, ' + NOT_JUDGED

# Over this CPU use (%, of all the computer's cores) by other work than the sweep's own, the
# computer is busy. ap-qa --busy-load changes it.
BUSY_LOAD = 30


def set_busy_load(percent):
    global BUSY_LOAD
    BUSY_LOAD = percent


def busy_computer(still95=None, load=None):
    """Whether the computer was too busy to judge a check of time or frames: the page lost frames
    standing still ([still95], p95 ms, over BUSY_MS), or other work kept the CPU over BUSY_LOAD
    meanwhile ([load], OtherLoad's percent). None: not known."""
    return (still95 is not None and still95 > BUSY_MS) or (load is not None and load > BUSY_LOAD)


class Late(Exception):
    """A wait of the sweep's own (or of a case) that ran out of time: an element or a state did
    not come. As Playwright's TimeoutError, a busy computer can cause it, so a case stopped by it
    on a busy computer is told, not judged."""


def timed_out(e):
    """Whether [e] is a wait that ran out of time: Playwright's TimeoutError (by its class's
    module: Python's own TimeoutError is not one), or Late."""
    return isinstance(e, Late) or (type(e).__name__ == 'TimeoutError' and type(e).__module__.startswith('playwright'))


def busy_verdict(failed, still95=None, load=None):
    """(ok, the note to add) of a check of time or frames that [failed] or not: a failure on a
    busy computer passes, told (BUSY_NOTE)."""
    told = failed and busy_computer(still95, load)
    return not failed or told, load_note(load) + (BUSY_NOTE if told else '')


def other_load(all_s, busy_s, ours_s):
    """How busy the CPU was with other work (%): of [all_s] CPU seconds (all cores, busy or not),
    [busy_s] were busy, [ours_s] of them the sweep's own."""
    return max(0.0, (busy_s - ours_s) / all_s * 100) if all_s > 0 else 0.0


class OtherLoad:
    """The CPU use of other work than the sweep's own, from now to percent(): the sweep's own is
    this Python and its children (Playwright's driver and the browsers), so a slow site, which
    keeps the browser busy, never counts as a busy computer. percent() is None without psutil.

    Not [running]: it counts only inside counting() blocks, all of them together."""

    def __init__(self, running=True):
        try:
            import psutil
        except ImportError:
            self.psutil = None
            return
        self.psutil = psutil
        self.spent = (0, 0, 0)  # the CPU seconds (all, busy, the sweep's own) of the blocks counted
        self.started = self._now() if running else None

    def _now(self):
        """The computer's CPU seconds so far, all and busy, and the sweep's own, by process."""
        ps = self.psutil
        t = ps.cpu_times()
        every = sum(t) - getattr(t, 'guest', 0) - getattr(t, 'guest_nice', 0)
        me, ours = ps.Process(), {}
        for p in [me] + me.children(recursive=True):
            try:
                c = p.cpu_times()
                ours[p.pid, p.create_time()] = c.user + c.system
            except ps.Error:  # gone meanwhile
                pass
        return every, every - t.idle - getattr(t, 'iowait', 0), ours

    def _spent(self):
        if self.started is None:
            return self.spent
        every, busy, ours = self._now()
        every0, busy0, ours0 = self.started
        # By process: one that ended meanwhile takes nothing away, one that started counts from 0.
        span = every - every0, busy - busy0, sum(s - ours0.get(k, 0) for k, s in ours.items())
        return tuple(a + b for a, b in zip(self.spent, span))

    @contextlib.contextmanager
    def counting(self):
        """Counts the CPU use while in this block."""
        if self.psutil is None:
            yield
            return
        self.started = self._now()
        try:
            yield
        finally:
            self.spent, self.started = self._spent(), None

    def percent(self):
        if self.psutil is None:
            return None
        return other_load(*self._spent())


def load_over(seconds, wait=time.sleep):
    """OtherLoad's percent over [seconds], spent in wait(seconds): None without psutil."""
    load = OtherLoad()
    wait(seconds)
    return load.percent()


def load_note(percent):
    """Said of [percent], OtherLoad's: '' when unknown."""
    return '' if percent is None else '; other work kept the computer at %.0f%% CPU' % percent
