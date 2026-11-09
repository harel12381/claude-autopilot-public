"""An example project.py of /ap:qa: what every case of the folder shares. Every name here may be
left out."""

import json

# The browser's locale for each of the project's languages (qa.langs); missing: the language code.
LOCALES = {'en': 'en-US', 'he': 'he-IL'}

# Console errors that are never the site's (a pattern each): a third party's frame, say.
CONSOLE_IGNORE = [r'report-only Content Security Policy']


def init_scripts(case):
    """Scripts every page of the case gets before the site's own: here, a site that keeps its
    language in localStorage starts in the case's language. case.theme is "dark", or
    "<the site's own theme>/<the phone's>" ("light/dark") when qa.themes gives pairs."""
    return ["if (location.protocol !== 'about:') localStorage.setItem('language', %s);" % json.dumps(case.lang)]
