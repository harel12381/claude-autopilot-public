"""The rows of the /ap:qa sweep (a case, a check, ok or not, its words, a picture), how each is
shown (ok, FAIL, TOLD), and the contact sheet, <out>/index.html."""

import html
import os

from busy import NOT_JUDGED


def mark(ok, detail):
    """'ok', 'FAIL', or 'TOLD' when it passed only because it was not judged (NOT_JUDGED in its
    words): a run with every check not judged must not read as all passed."""
    return 'FAIL' if not ok else 'TOLD' if NOT_JUDGED in detail else 'ok  '


class Result:
    def __init__(self, say=print):
        self.rows = []  # (case, check, ok, detail, picture)
        self.say = say
        self.held = None  # the index of the first row of the case under way, while rows are held

    def add(self, case, check, ok, detail, picture=None):
        self.rows.append((case, check, bool(ok), detail, picture))
        if self.held is None:
            self.show(self.rows[-1])

    def show(self, row):
        case, check, ok, detail, _ = row
        self.say('%s  %-24s %-24s %s' % (mark(ok, detail), case, check, detail), flush=True)

    def hold(self):
        """The rows from now on are shown at release(), once it is known whether a deploy ran."""
        self.held = len(self.rows)

    def release(self, note=None):
        """Shows the held rows. With [note] (a deploy ran beside them), each failed one passes,
        told: [note] says why it is not judged."""
        start, self.held = self.held, None
        if start is None:
            return
        for i in range(start, len(self.rows)):
            case, check, ok, detail, picture = self.rows[i]
            if note and not ok:
                self.rows[i] = (case, check, True, detail + note, picture)
            self.show(self.rows[i])

    @property
    def failed(self):
        return [r for r in self.rows if not r[2]]

    @property
    def not_judged(self):
        return [r for r in self.rows if mark(r[2], r[3]) == 'TOLD']


def contact_sheet(res, out, title='QA'):
    """<out>/index.html: one row per check, its picture beside it; failed rows red, told ones
    orange."""
    rows = []
    for case, check, ok, detail, pic in res.rows:
        img = '<img src="%s">' % html.escape(os.path.basename(pic)) if pic else ''
        rows.append('<tr class="%s"><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>' % (
            mark(ok, detail).strip().lower(), html.escape(case), html.escape(check), html.escape(detail), img))
    path = os.path.join(out, 'index.html')
    with open(path, 'w', encoding='utf-8') as f:
        f.write('<!doctype html><meta charset="utf-8"><title>%s</title><style>'
                'body{font:14px system-ui;margin:16px}td{border-bottom:1px solid #ddd;padding:6px;vertical-align:top}'
                'img{width:195px}.fail td:nth-child(2){color:#c00;font-weight:600}'
                '.told td:nth-child(2){color:#b60;font-weight:600}</style>'
                '<h1>%s</h1><table>%s</table>' % (html.escape(title), html.escape(title), ''.join(rows)))
    return path
