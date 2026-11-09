"""A fake playwright.sync_api for tests/qa-test.sh. Its browsers make pages that answer the
example case of the plugin (a title, the page's width, a load time) and take pictures (a few
bytes). FAKE_PW_BLOCK: the browsers whose launch fails as Windows' Smart App Control stops them
("webkit"); FAKE_PW_MISSING: the ones not installed. A page opened at a path with "broken" in it
logs a console error. Every call is written to FAKE_PW_LOG, when it is set."""

import contextlib
import os


class TimeoutError(Exception):  # noqa: A001 (Playwright's own name)
    pass


def log(text):
    if os.environ.get('FAKE_PW_LOG'):
        with open(os.environ['FAKE_PW_LOG'], 'a', encoding='utf-8') as f:
            f.write(text + '\n')


class Message:
    def __init__(self, text):
        self.type, self.text = 'error', text


class Page:
    def __init__(self, context):
        self.context, self.handlers, self.url, self.scripts = context, {}, 'about:blank', []
        self.main_frame = object()

    def on(self, event, handler):
        self.handlers.setdefault(event, []).append(handler)

    def add_init_script(self, script):
        self.scripts.append(script)

    def goto(self, url, **_):
        log('goto %s %s %s' % (url, self.context.options.get('locale'), self.context.options.get('color_scheme')))
        self.url = url
        if 'broken' in url:
            for h in self.handlers.get('console', []):
                h(Message('Uncaught Error: broken page'))

    def title(self):
        return 'Fake'

    def evaluate(self, script, *_):
        return 0 if 'scrollWidth' in script else 100

    def screenshot(self, path=None, **_):
        if path:
            with open(path, 'wb') as f:
                f.write(b'png')
        return b'png'

    def wait_for_timeout(self, ms):
        pass


class Context:
    def __init__(self, options):
        self.options = options

    def new_page(self):
        return Page(self)

    def new_cdp_session(self, page):
        return object()

    def close(self):
        pass


class Browser:
    def __init__(self, name):
        self.name = name

    def new_context(self, **options):
        return Context(options)

    def close(self):
        log('close %s' % self.name)


class BrowserType:
    def __init__(self, name):
        self.name = name

    def launch(self, **_):
        log('launch %s' % self.name)
        if self.name in os.environ.get('FAKE_PW_BLOCK', '').split(','):
            raise Exception('BrowserType.launch: Browser closed.\n<process did exit: exitCode=3236495362, signal=null>')
        if self.name in os.environ.get('FAKE_PW_MISSING', '').split(','):
            raise Exception("BrowserType.launch: Executable doesn't exist at /ms-playwright/%s" % self.name)
        return Browser(self.name)


class Playwright:
    def __init__(self):
        self.chromium, self.webkit, self.firefox = BrowserType('chromium'), BrowserType('webkit'), BrowserType('firefox')
        self.devices = {'iPhone 13': {'viewport': {'width': 390, 'height': 664}, 'is_mobile': True}}


def sync_playwright():
    return contextlib.nullcontext(Playwright())
