"""An example case of /ap:qa: the site's first page at phone size. Copy it into the project's
cases folder (qa.cases in .claude/ap.json) and change it to the project's own screens.

It checks that the page has a title, that nothing is wider than the phone's screen (no side
scroll), and that it opens fast enough; then it saves a picture to judge by eye."""

# A case of how the site looks: it runs with every theme (the others run with the first only).
LOOK = True

# The longest a first page may take, from the request to the load event (ms).
LOAD_MS = 5000


def run(case):
    case.step('open')
    case.open('/')

    case.step('title')
    title = case.page.title()
    case.check('title', bool(title.strip()), 'title: %r' % title)

    case.step('width')
    wide = case.page.evaluate('() => document.documentElement.scrollWidth - window.innerWidth')
    case.check('width', wide <= 0, 'wider than the screen by %d px' % wide if wide > 0 else 'fits the screen')

    case.step('speed')
    took = case.page.evaluate('() => { const n = performance.getEntriesByType("navigation")[0];'
                              ' return n ? Math.round(n.loadEventEnd - n.startTime) : 0; }')
    case.timed('speed', took > LOAD_MS, 'loaded in %d ms (at most %d)' % (took, LOAD_MS))

    case.picture('screen')
