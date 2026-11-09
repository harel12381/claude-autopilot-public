"""A page's console errors in the /ap:qa sweep: each with the step that ran when it came, and the
loads WebKit logs as errors when a page is left, told apart from the site's own."""

import re
import time

from busy import OtherLoad

# What WebKit logs as errors for the loads a page still had under way when it was left (a reload,
# another page). Chromium logs nothing for them.
CUT_LOAD = re.compile(r'due to access control checks|^(Type)?Error: Load failed$|Importing a module script failed'
                      r'|failed to import scripts')

# What Playwright gives of a page error without words.
NO_WORDS = ('', 'Error')

# How long a page change may take to load before its errors are the site's again.
LEAVING_S = 60


class Console(list):
    """A case's console errors and page errors, each as "[<step>] <text>". [step] is set by the
    case as it goes; [step_load] counts how busy other work keeps the computer from then on.

    In WebKit ([webkit]), from the start of each new page until it has loaded, the errors of
    CUT_LOAD go to [cut]: told, not the site's. [ignore]: patterns of errors that are never the
    site's (the project's CONSOLE_IGNORE)."""

    def __init__(self, webkit=False, ignore=()):
        super().__init__()
        self.cut = []
        self.left = None  # when the page was last left (time.time()), until the new one loaded
        self.webkit = webkit
        self.ignore = [re.compile(p) for p in ignore]
        self.step = 'load'

    @property
    def step(self):
        return self._step

    @step.setter
    def step(self, name):
        self._step, self.step_load = name, OtherLoad()

    @property
    def leaving(self):
        return self.left is not None and time.time() - self.left < LEAVING_S

    def add(self, text):
        if any(p.search(text) for p in self.ignore):
            return
        line = '[%s] %s' % (self.step, text[:200])
        (self.cut if self.webkit and self.leaving and CUT_LOAD.search(text) else self).append(line)

    def listen(self, page):
        """Collects [page]'s errors and follows its page changes."""
        page.on('console', lambda m: self.add(m.text) if m.type == 'error' else None)
        page.on('pageerror', lambda e: self.add(str(e)) if str(e) not in NO_WORDS else None)
        page.on('request', lambda r: self._leaving(page, r))
        page.on('load', lambda p: setattr(self, 'left', None))

    def _leaving(self, page, request):
        try:
            # The first page leaves nothing: its own loads that fail are the site's.
            if request.is_navigation_request() and request.frame == page.main_frame and page.url != 'about:blank':
                self.left = time.time()
        except Exception:  # a service worker's request has no frame
            pass

    def told(self):
        """The console check's words: the site's errors, and how many cut loads were told."""
        return ('; '.join(self[:3]) or 'no errors') + (
            '; %d loads cut by leaving the page, told (WebKit logs them): %s' % (len(self.cut), self.cut[0])
            if self.cut else '')
