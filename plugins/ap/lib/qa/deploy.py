"""The deploy, as the /ap:qa sweep sees it: ap-deploy holds the folder ap-deploy.lock in the
repository's common .git folder while the project's deploy command runs, and adds a line
"<start> <end>" (seconds since 1970) to ap-deploy-times after it. While a site is deployed, its
pages can fail to load: a case waits for the lock, and a check that failed beside a deploy is not
judged."""

import os
import time

# A lock older than this is one a killed deploy left (ap-qa removes such a lock before the sweep
# when its process is gone; this is the limit for one that a later deploy left meanwhile).
STALE_S = 2 * 3600

# Said of a check that failed beside a deploy.
DEPLOY_NOTE = '; the site was deploying, not judged'


class DeployHangs(Exception):
    """The deploy lock was still held after the wait's limit."""


class Deploys:
    """The deploys of the repository whose common .git folder is [folder] (None: no deploys are
    known, nothing waits)."""

    def __init__(self, folder, wait_s=3600, say=print, sleep=time.sleep, now=time.time):
        self.lock = os.path.join(folder, 'ap-deploy.lock') if folder else None
        self.times = os.path.join(folder, 'ap-deploy-times') if folder else None
        self.wait_s, self.say, self.sleep, self.now = wait_s, say, sleep, now

    def held(self):
        """Whether a deploy runs now: the lock is there and not stale."""
        if not self.lock:
            return False
        try:
            return self.now() - os.path.getmtime(self.lock) < STALE_S
        except OSError:
            return False

    def owner(self):
        try:
            with open(os.path.join(self.lock, 'owner'), encoding='utf-8', errors='replace') as f:
                return f.read().strip().partition(' ')[2] or 'a deploy'
        except OSError:
            return 'a deploy'

    def wait(self):
        """Waits while a deploy runs, at most wait_s; DeployHangs after that."""
        if not self.held():
            return
        self.say('Waiting for the deploy to end: %s' % self.owner(), flush=True)
        started = self.now()
        while self.held():
            if self.now() - started > self.wait_s:
                raise DeployHangs('the deploy lock %s was still held after %d s (%s)'
                                  % (self.lock, self.wait_s, self.owner()))
            self.sleep(5)
        self.say('The deploy ended; the sweep goes on.', flush=True)

    def ran_between(self, start, end):
        """Whether a deploy ran at some time from [start] to [end] (seconds since 1970): one runs
        now, or a line of ap-deploy-times overlaps them."""
        if self.held():
            return True
        try:
            with open(self.times, encoding='utf-8') as f:
                lines = f.read().split('\n')
        except (OSError, TypeError):
            return False
        for line in lines:
            parts = line.split()
            if len(parts) == 2 and all(p.isdigit() for p in parts):
                if int(parts[0]) <= end and int(parts[1]) >= start:
                    return True
        return False
