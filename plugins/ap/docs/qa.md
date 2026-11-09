# /ap:qa: the sweep and the project's cases

`/ap:qa` opens the project's site the way a phone does, and checks what a still picture of one
screen can't show. The plugin holds the driver (`ap-qa`, `lib/qa/`); the project holds its own
cases, in a folder `.claude/ap.json` names. Turn it on with `/ap:setup` (`parts.qa`).

## What the driver does

- Opens each case in Playwright at phone size (`qa.device`, `iPhone 13`), in Chromium (the full
  browser, on the GPU) and WebKit (Safari's engine), once per language (`qa.langs`) and theme
  (`qa.themes`). An iPhone page says it runs on an iPhone (`navigator.platform`).
- A theme is the phone's (`light`, `dark`: the browser's colour scheme), or a pair
  `<the site's own>/<the phone's>` (`dark/light`) for a site with a theme of its own: the case and
  `project.py` see the whole pair in `case.theme`, and set the site's own theme themselves.
- A browser that cannot start is a failed `launch` row, and the sweep goes on with the next one.
  On Windows, Smart App Control can block WebKit: the row says so, and its cases did not run.
- A case that stops (an error, a crash, a time-out) is a failed `<case>.run` row, with the step it
  was in and a picture of the page at that moment. The next case still runs.
- Each case gets a `<case>.console` row: the page's console errors and page errors, each named by
  the step it came in. WebKit's errors for the loads a page had under way when it was left are told,
  not counted.
- **Not judged on a busy computer.** A check of time or frames (`case.timed`), or a case stopped by
  a time-out, that fails while other work keeps the CPU over `qa.busy_load` (30%) passes, marked
  `TOLD` and "not judged". Needs `psutil`; without it, such a check fails. The summary names every
  check not judged: it is not a pass, only not known.
- **Not during a deploy.** Before the sweep and before each case, it waits while `ap-deploy` holds
  the deploy lock (at most `--deploy-wait`, 60 minutes; then it stops, exit 2). A check that failed
  while a deploy ran is not judged.
- Saves the pictures and `index.html`, the contact sheet (failed rows red, not judged orange), in
  `--out` (default: a new folder under the computer's temp folder). The last lines: `<n> checks,
  <f> failed, <t> not judged, <s> s. Pictures: <out>/index.html`, then `Not judged: ...`.

Exit 0: every check passed (one not judged passes); 1: a check failed; 2: it could not run; 3:
`parts.qa` is off.

Once on a computer (free, about 300 MB):
`pip install playwright psutil && python -m playwright install chromium webkit`.

## The settings (`.claude/ap.json`)

```json
"parts": { "qa": true },
"qa": {
  "cases": ".claude/ap/qa",
  "url": "https://example.org",
  "langs": ["en", "he"],
  "themes": ["light", "dark"],
  "browsers": ["chromium", "webkit"],
  "device": "iPhone 13",
  "busy_load": 30
}
```

Only `cases` is needed. `url` is the site to check (missing: `site`). The rest have the defaults
above (`langs`: `["en"]`). `ap-qa --url <u> --langs he --themes dark --only home,menu
--browsers chromium` narrows one run.

## The cases folder

One Python file per case, and an optional `project.py`. A file whose name starts with `_` is not a
case (a helper the cases import). The plugin's example: `docs/qa-example/` (`home.py`,
`project.py`); `/ap:setup` copies it when the folder is new.

### A case: `<name>.py`

```python
LOOK = True                 # optional: runs with every theme (default: the first theme only)
BROWSERS = {'chromium'}     # optional: only in these browsers

def run(case):
    case.step('open')
    case.open('/')
    case.check('title', bool(case.page.title()), 'title: %r' % case.page.title())
    case.picture('screen')
```

A case of how the site looks (`LOOK = True`) runs with each theme; a case of how it behaves runs
once per browser and language, with the first theme.

### What `run(case)` gets

| Name | What it is |
|---|---|
| `case.page`, `case.context` | Playwright's page and context of this case, as the phone |
| `case.browser_name`, `case.lang`, `case.theme`, `case.scheme` | `chromium`; `he`; `dark/light`; `light` (the phone's part of the theme) |
| `case.base`, `case.out`, `case.name`, `case.id` | the site's address; the pictures' folder; the file's name; `<browser>-<lang>-<theme>` |
| `case.cdp` | Chromium's CDP session of the page (frames, a slower CPU), `None` in other browsers |
| `case.step(name)` | names the step under way: a stop or a console error names it, and `load()` counts from it |
| `case.open(path='/', page=None)` | opens the site at `path` and waits until it is ready (`project.ready`, or the load event and a screen that stands still) |
| `case.settle(page=None, most_s=30, still_s=2)` | waits until the screen stands still; returns the last picture |
| `case.check(name, ok, detail='', picture=None)` | a row `<case>.<name>`, passed or failed |
| `case.picture(name, detail=..., page=None)` | a picture `<id>-<case>-<name>.png`, as a row to judge by eye |
| `case.timed(name, failed, detail='', still95=None)` | a row of a check of time or frames: a failure on a busy computer is not judged |
| `case.load()` | the CPU use (%) of other work since the step began, or `None` |
| `case.counting()` | an `OtherLoad` that counts only inside its `counting()` blocks (a drag while the finger moves) |
| `case.new_page(**options)` | `with case.new_page(viewport={'width': 320, 'height': 640}) as p:` another page of the case, closed after |
| `raise case.Late('...')` | a wait of the case's own that ran out of time: like Playwright's time-out, not judged on a busy computer |

### `project.py` (every name optional)

| Name | What it is |
|---|---|
| `init_scripts(case)` | a list of scripts every page of the case gets before the site's own (set the site's language or theme in `localStorage`) |
| `ready(page)` | waits until the site is ready after a load (instead of the load event and a still screen) |
| `LOCALES` | `{'he': 'he-IL'}`: the browser's locale for each language (missing: the language code) |
| `CONSOLE_IGNORE` | patterns of console errors that are never the site's |

## Writing a good case

- Check by machine what a still picture can't show: a theme from the first frame, an animation
  that goes back, a page that jumps when it comes back, a button too small to tap, a sheet that
  loses frames. Leave the look of a screen to the picture and the agent's eye.
- Name each step (`case.step`): a failure then says where it stopped.
- A limit of time or frames goes through `case.timed`, so a busy computer is not a failure.
- A failure that comes from the case itself (a wrong limit, a button it could not find) is a bug in
  the case: fix it in the cases folder, never ignore it.
