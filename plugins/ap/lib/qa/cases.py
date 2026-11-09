"""The project's own cases of the /ap:qa sweep, and what each case is given (Case). The interface
is written down in the plugin's docs/qa.md: keep the two the same.

The cases folder (qa.cases in .claude/ap.json) holds one Python file per case, and an optional
project.py with what every case shares. A file whose name starts with "_" is not a case."""

import contextlib
import importlib.util
import os
import time

from browsers import first_line
from busy import BUSY_NOTE, Late, OtherLoad, busy_computer, busy_verdict, load_note, timed_out
from console import Console

# What project.py may set, with its default.
PROJECT_DEFAULTS = {
    'init_scripts': None,    # function(case) -> list of scripts every page gets before the site's own
    'ready': None,           # function(page): waits until the site is ready after a load
    'LOCALES': {},           # {lang: browser locale}: 'he' -> 'he-IL'; missing: the lang itself
    'CONSOLE_IGNORE': (),    # patterns of console errors that are never the site's
}


class BadCases(Exception):
    """The cases folder breaks the interface (docs/qa.md)."""


def load_file(path, name):
    spec = importlib.util.spec_from_file_location('ap_qa_' + name, path)
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except Exception as e:
        raise BadCases('%s could not be loaded: %s: %s' % (path, type(e).__name__, first_line(e))) from e
    return module


class Project:
    """project.py of the cases folder, or its defaults."""

    def __init__(self, module=None):
        for key, default in PROJECT_DEFAULTS.items():
            setattr(self, key, getattr(module, key, default) if module else default)
        if self.init_scripts is not None and not callable(self.init_scripts):
            raise BadCases('project.py: init_scripts must be a function of the case')
        if self.ready is not None and not callable(self.ready):
            raise BadCases('project.py: ready must be a function of the page')

    def locale(self, lang):
        return self.LOCALES.get(lang, lang)


class CaseFile:
    """One case of the folder: its name (the file's), run(case), and when it runs."""

    def __init__(self, name, module):
        self.name = name
        self.run = getattr(module, 'run', None)
        if not callable(self.run):
            raise BadCases('%s.py has no run(case) function' % name)
        self.look = bool(getattr(module, 'LOOK', False))
        browsers = getattr(module, 'BROWSERS', None)
        self.browsers = set(browsers) if browsers else None

    def runs_in(self, browser, first_theme):
        """Whether it runs in [browser], and with this theme ([first_theme]: the first of the
        sweep's themes): a LOOK case runs with every theme, the others with the first only."""
        return (self.browsers is None or browser in self.browsers) and (self.look or first_theme)


def load(folder, only=None):
    """(Project, [CaseFile]) of the cases [folder], in the order of their names; [only]: just
    those names, in that order."""
    if not os.path.isdir(folder):
        raise BadCases('there is no cases folder %s (qa.cases in .claude/ap.json)' % folder)
    names = sorted(f[:-3] for f in os.listdir(folder)
                   if f.endswith('.py') and not f.startswith('_') and f != 'project.py')
    project_path = os.path.join(folder, 'project.py')
    project = Project(load_file(project_path, 'project') if os.path.isfile(project_path) else None)
    if only:
        missing = [n for n in only if n not in names]
        if missing:
            raise BadCases('no case %s in %s' % (', '.join(missing), folder))
        names = list(only)
    if not names:
        raise BadCases('%s has no case (a <name>.py with a run(case) function)' % folder)
    return project, [CaseFile(n, load_file(os.path.join(folder, n + '.py'), n)) for n in names]


class Case:
    """What a case's run(case) is given: the page and the facts of this run, and the ways to
    write down what it found. Every row it adds is named "<case>.<name>"."""

    Late = Late  # raise case.Late('...') for a wait of the case's own that ran out of time

    def __init__(self, browser, browser_name, file, project, phone, base, lang, theme, out, res):
        self.browser_name, self.file, self.project = browser_name, file, project
        self.base, self.lang, self.theme, self.out, self.res = base, lang, theme, out, res
        # A theme is "dark" (the phone's), or "<the site's own>/<the phone's>": "light/dark".
        self.scheme = theme.split('/')[-1]
        self.name = file.name
        self.id = '%s-%s-%s' % (browser_name, lang, theme.replace('/', '-'))
        self._browser, self._phone = browser, phone
        self.console = Console(webkit=browser_name == 'webkit', ignore=project.CONSOLE_IGNORE)
        self.context, self.page = self._new_page()
        self.cdp = self.context.new_cdp_session(self.page) if browser_name == 'chromium' else None

    def _new_page(self, **options):
        device, scripts = self._phone
        context = self._browser.new_context(**dict(device, **options), locale=self.project.locale(self.lang),
                                            color_scheme=self.scheme)
        page = context.new_page()
        self.console.listen(page)
        for script in scripts + list(self.project.init_scripts(self) if self.project.init_scripts else []):
            page.add_init_script(script)
        return context, page

    @contextlib.contextmanager
    def new_page(self, **options):
        """Another page of this case, with Playwright's context [options] on top of the phone's
        (viewport={'width': 320, 'height': 640}), closed after the block."""
        context, page = self._new_page(**options)
        try:
            yield page
        finally:
            context.close()

    def close(self):
        self.context.close()

    # What a case does.

    def step(self, name):
        """The step under way: a failure or a console error names it, and load() counts from it."""
        self.console.step = name

    def open(self, path='/', page=None):
        """Opens the site at [path] in [page] (the case's own), and waits until it is ready: the
        project's ready(page), or the load event and a screen that stands still."""
        page = page or self.page
        page.goto(self.base + path, wait_until='load', timeout=60000)
        if self.project.ready:
            self.project.ready(page)
        else:
            self.settle(page)

    def settle(self, page=None, most_s=30, still_s=2):
        """Waits until the screen stands still for [still_s] seconds (two pictures a second
        apart are the same), at most [most_s]. Returns the last picture (PNG bytes)."""
        page = page or self.page
        started = time.time()
        last, still = page.screenshot(), 0
        while time.time() - started < most_s and still < still_s:
            page.wait_for_timeout(1000)
            now = page.screenshot()
            still = still + 1 if now == last else 0
            last = now
        return last

    def check(self, name, ok, detail='', picture=None):
        """A row: [name] passed ([ok]) or failed, with [detail]."""
        self.res.add(self.id, '%s.%s' % (self.name, name), ok, detail or ('ok' if ok else 'failed'), picture)

    def picture(self, name, detail='a picture to judge', page=None, **options):
        """A picture of the screen, <id>-<case>-<name>.png, as a row to judge by eye. Returns its path."""
        path = os.path.join(self.out, '%s-%s-%s.png' % (self.id, self.name, name))
        (page or self.page).screenshot(path=path, **options)
        self.check(name, True, detail, path)
        return path

    def load(self):
        """The CPU use (%) of other work than the sweep's since the step began, or None."""
        return self.console.step_load.percent()

    def timed(self, name, failed, detail='', still95=None):
        """A row of a check of time or frames: one that [failed] on a busy computer passes,
        told (not judged)."""
        ok, note = busy_verdict(failed, still95, self.load())
        self.check(name, ok, (detail or ('too slow' if failed else 'ok')) + note)

    def counting(self):
        """An OtherLoad to count the CPU use of other work over some blocks only (its counting())."""
        return OtherLoad(running=False)

    def stopped(self, e):
        """The row of a case that stopped on [e]: a time-out on a busy computer is told, every
        other stop fails. With a picture of the page at that moment."""
        other = self.load()
        told = timed_out(e) and busy_computer(load=other)
        shot = os.path.join(self.out, '%s-%s-failed.png' % (self.id, self.name))
        try:
            self.page.screenshot(path=shot)
        except Exception:
            shot = None
        detail = 'stopped in %s: %s%s: %s%s%s' % (
            self.console.step, 'the page crashed; ' if 'crash' in str(e).lower() else '', type(e).__name__,
            first_line(e)[:200], load_note(other), BUSY_NOTE if told else '')
        self.res.add(self.id, self.name + '.run', told, detail, shot)
