"""The browsers of the /ap:qa sweep: one started by Playwright, or why it could not start (on
Windows, Smart App Control can block WebKit), and the phone the pages are opened as."""

import re

# Windows' Smart App Control stops a program it blocks before it runs, with this exit code; its
# words in a program's output.
BLOCKED_WORDS = 'Application Control policy has blocked'
BLOCKED_EXIT = '0xC0E90002'
_CODE = int(BLOCKED_EXIT, 16)
# That exit code in hex or in decimal (Playwright's browser logs: "exitCode=3236495362"), also as
# a signed number.
_EXIT = re.compile(r'(?<![\w-])(%s)\b' % '|'.join(map(re.escape, (str(_CODE), str(_CODE - 2 ** 32), BLOCKED_EXIT))),
                   re.I)

# Playwright's iPhones keep the computer's navigator.platform ("Win32"); a site that reads it
# would lay itself out as on a computer. Safari on an iPhone says "iPhone".
IPHONE = "Object.defineProperty(Navigator.prototype, 'platform', {get: () => 'iPhone'});"


def blocked(output):
    """Whether a program's [output] says Windows blocked it: its words, or its exit code."""
    return BLOCKED_WORDS in output or _EXIT.search(output) is not None


def first_line(e):
    """The first line of error [e]'s message (Playwright's go on with their logs), or its kind."""
    text = str(e).strip()
    return text.splitlines()[0] if text else type(e).__name__


class CannotStart(Exception):
    """A browser that did not start, with why."""


def cannot_start(name, e):
    title = 'WebKit' if name == 'webkit' else name.capitalize()
    if blocked(str(e)):
        return ('Windows blocked %s (Smart App Control, exit code %s): its cases did not run; run them on another '
                'computer, or allow the browser in Windows Security' % (title, BLOCKED_EXIT))
    return '%s could not start: %s' % (title, first_line(e))


def launch(pw, name):
    """Browser [name] ('chromium', 'webkit', 'firefox') of Playwright [pw], or CannotStart.
    Chromium: the full browser, not Playwright's headless shell, which draws WebGL in software
    and makes every animation look slow."""
    try:
        if name == 'chromium':
            return pw.chromium.launch(channel='chromium')
        return getattr(pw, name).launch()
    except Exception as e:
        raise CannotStart(cannot_start(name, e)) from e


def phone(pw, device):
    """The context options of Playwright's device [device] ('iPhone 13'), and the scripts each of
    its pages gets first."""
    try:
        options = dict(pw.devices[device])
    except KeyError:
        raise ValueError('Playwright has no device %r' % device) from None
    return options, [IPHONE] if 'iphone' in device.lower() else []
