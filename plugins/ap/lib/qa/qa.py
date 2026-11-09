"""The /ap:qa sweep: the project's own cases, run on its site with Playwright at phone size, in
Chromium and WebKit (Safari's engine), in each of the project's languages and themes. A case checks
by itself what a still picture can't show, and saves pictures for an agent to judge (the contact
sheet: <out>/index.html). ap-qa runs it; the cases' interface: docs/qa.md of the plugin.

    python qa.py --root <checkout> --settings <ap.json> [--url <site>] [--cases <folder>]
                 [--browsers chromium,webkit] [--langs en,he] [--themes light,dark] [--only a,b]
                 [--device "iPhone 13"] [--out <folder>] [--deploy-dir <common .git>]
                 [--deploy-wait <minutes>] [--busy-load <percent>]

The options that are not given come from the "qa" part of the settings file (cases, url, browsers,
langs, themes, device, busy_load), and the url from its "site". Exit 0: every check passed (a check
not judged passes, and is named at the end); 1: a check failed; 2: the sweep could not run.
"""

import argparse
import datetime
import json
import os
import sys
import tempfile
import time
import traceback

# No __pycache__ folders: not in the plugin, and not in the project's cases folder.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from browsers import CannotStart, first_line, launch, phone  # noqa: E402
from busy import set_busy_load  # noqa: E402
from cases import BadCases, Case, load  # noqa: E402
from deploy import DEPLOY_NOTE, Deploys, DeployHangs  # noqa: E402
from result import Result, contact_sheet  # noqa: E402

DEFAULTS = {'browsers': ['chromium', 'webkit'], 'langs': ['en'], 'themes': ['light', 'dark'], 'device': 'iPhone 13',
            'busy_load': 30}


class CannotRun(Exception):
    """The sweep cannot run: a setting is missing or wrong."""


def settings(path):
    """The "qa" part of the settings file, with its "site"."""
    try:
        with open(path, encoding='utf-8-sig') as f:
            data = json.load(f)
    except (OSError, ValueError) as e:
        raise CannotRun('cannot read %s: %s' % (path, e)) from e
    qa = data.get('qa') or {}
    if not isinstance(qa, dict):
        raise CannotRun('"qa" in %s is not an object' % path)
    return qa, data.get('site')


def as_list(value, name):
    """A list from the command line ("a,b") or the settings (["a", "b"] or "a,b")."""
    items = value.split(',') if isinstance(value, str) else value
    if not isinstance(items, list) or not all(isinstance(i, str) and i.strip() for i in items) or not items:
        raise CannotRun('%s must be a list of names, not %r' % (name, value))
    return [i.strip() for i in items]


def options(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--root', required=True, help='the checkout whose cases run (qa.cases is relative to it)')
    ap.add_argument('--settings', required=True, help='the .claude/ap.json to read')
    for name in ('url', 'cases', 'browsers', 'langs', 'themes', 'device', 'only', 'out', 'deploy-dir'):
        ap.add_argument('--' + name)
    ap.add_argument('--deploy-wait', type=float, default=60, help='minutes to wait for a deploy at most')
    ap.add_argument('--busy-load', type=float)
    ap.add_argument('--title', default='QA')
    a = ap.parse_args(argv)
    qa, site = settings(a.settings)
    pick = lambda name: getattr(a, name.replace('-', '_')) or qa.get(name.replace('-', '_')) or DEFAULTS.get(name)
    a.url = (a.url or qa.get('url') or site or '').rstrip('/')
    if not a.url:
        raise CannotRun('no site to check: give --url, or set qa.url or site in .claude/ap.json')
    cases = a.cases or qa.get('cases')
    if not cases:
        raise CannotRun('no cases folder: set qa.cases in .claude/ap.json (docs/qa.md of the plugin)')
    a.cases = os.path.join(a.root, cases)
    a.browsers, a.langs, a.themes = (as_list(pick(n), n) for n in ('browsers', 'langs', 'themes'))
    a.only = as_list(a.only, 'only') if a.only else None
    a.device = pick('device')
    a.busy_load = a.busy_load if a.busy_load is not None else float(pick('busy_load'))
    return a


def run_case(pw, browser, browser_name, file, project, device, base, lang, theme, out, res, deploys):
    """One case file in one browser, language and theme. A deploy that ran beside it makes its
    failed rows not judged."""
    deploys.wait()
    started = time.time()
    res.hold()
    case = None
    try:
        case = Case(browser, browser_name, file, project, device, base, lang, theme, out, res)
        file.run(case)
    except Exception as e:  # a case that could not run is a failure, with its reason
        if case is None:
            res.add('%s-%s-%s' % (browser_name, lang, theme.replace('/', '-')), file.name + '.run', False,
                    'could not make its page: %s: %s' % (type(e).__name__, first_line(e)))
        else:
            case.stopped(e)
    finally:
        if case is not None:
            res.add(case.id, file.name + '.console', not case.console, case.console.told())
            try:
                case.close()
            except Exception:
                pass
        res.release(DEPLOY_NOTE if deploys.ran_between(started, time.time()) else None)


def run_browser(pw, browser_name, a, project, files, device, out, res, deploys):
    """Every case of one browser, per language and theme. CannotStart when it does not start."""
    browser = launch(pw, browser_name)
    try:
        for lang in a.langs:
            for i, theme in enumerate(a.themes):
                for file in files:
                    if file.runs_in(browser_name, i == 0):
                        run_case(pw, browser, browser_name, file, project, device, a.url, lang, theme, out, res,
                                 deploys)
    finally:
        browser.close()


def sweep(a):
    project, files = load(a.cases, a.only)
    set_busy_load(a.busy_load)
    out = a.out or os.path.join(tempfile.gettempdir(), 'ap-qa', datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
    os.makedirs(out, exist_ok=True)
    deploys = Deploys(a.deploy_dir, wait_s=a.deploy_wait * 60)
    res = Result()
    started = time.time()
    print('Checking %s: %d case(s), %s, %s, %s.' % (a.url, len(files), ','.join(a.browsers), ','.join(a.langs),
                                                    ','.join(a.themes)), flush=True)
    from playwright.sync_api import sync_playwright  # here: the tests of the sweep's logic run without it
    hung = None
    with sync_playwright() as pw:
        device = phone(pw, a.device)
        for browser_name in a.browsers:
            # A browser that cannot start, or whose run stops outside a case, is a failed row:
            # the sweep goes on with the next one, and the contact sheet keeps what the others got.
            try:
                run_browser(pw, browser_name, a, project, files, device, out, res, deploys)
            except DeployHangs as e:
                res.release()
                hung = e
                break
            except Exception as e:
                launch_failed = isinstance(e, CannotStart)
                if not launch_failed:
                    traceback.print_exc()
                why = e if launch_failed else 'the sweep stopped in %s: %s: %s' % (browser_name, type(e).__name__,
                                                                                    first_line(e))
                res.release()
                res.add(browser_name, 'launch' if launch_failed else 'run', False,
                        '%s; not run: its cases from then on' % why)
    sheet = contact_sheet(res, out, a.title)
    told = res.not_judged
    print('\n%d checks, %d failed, %d not judged, %.0f s. Pictures: %s' % (
        len(res.rows), len(res.failed), len(told), time.time() - started, sheet))
    if told:
        print('Not judged: ' + ', '.join('%s %s' % (case, check) for case, check, *_ in told))
    if hung:
        print('ap-qa: stopped: %s' % hung, file=sys.stderr)
        return 2
    return 1 if res.failed else 0


def main(argv=None):
    try:
        return sweep(options(argv))
    except (CannotRun, BadCases, ValueError) as e:
        print('ap-qa: %s' % e, file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
