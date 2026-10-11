# Published to GitHub

On 11 October 2026 the whole project was pushed to your repository, over SSH, into the folder `PokerChipCountingApp/` under `Swift Project/`, after you deleted the folder of that name you had uploaded by hand.

| | |
|---|---|
| Repository | `PranavTummalapalli6/Projects-` (public), branch `main` |
| Folder | `PythonProjects/Swift Project/PokerChipCountingApp/` |
| What is in it | A snapshot of this project's last commit: the app, the Lock Screen extension, the tests, the backend (`ChipVisionService`), the docs and the screenshots. Only files git tracks go up, so the photos (`PokerChipApp/test_photos/`), the service-account key and `.env` stay behind |
| Not touched | The older copy of the app directly in `Swift Project/` (and its `__MACOSX` folder), and the `PickleballApp/` folder |
| History | One commit in your repository, authored as `PranavTummalapalli6`, with Claude as co-author. This project's own commit history stays in the local repository (`git subtree` could bring it across; say if you want that) |

## How it was done

A shallow clone of your repository over SSH with the key you made (`~/ssh_key`); GitHub's host key was checked against the fingerprint GitHub publishes at `api.github.com/meta` before anything was sent; the project's tracked files (`git archive HEAD`) were extracted into the folder; one commit; `git push`. Nothing in your repository was deleted or rewritten by it.

To undo it: `git revert` the commit, or delete the folder on github.com.

To publish a later version, repeat it:

```bash
export GIT_SSH_COMMAND="ssh -i ~/ssh_key -o IdentitiesOnly=yes"
git clone --depth 1 git@github.com:PranavTummalapalli6/Projects-.git /tmp/projects && cd /tmp/projects
D="PythonProjects/Swift Project/PokerChipCountingApp"
git rm -r -q --cached "$D" && rm -rf "$D" && mkdir -p "$D"
git -C ~/Desktop/PokerChipApp archive --format=tar HEAD | tar -x -C "$D"
git add -A "$D" && git commit -m "Update PokerChipCountingApp" && git push origin main
```

(Commit in the project first: `git archive` exports the last commit, not edits in the working folder.)

## Three things to know

1. **It is public.** Everything tracked is visible to anyone: the source, the docs, the screenshots, `GoogleService-Info.plist`, the Firebase project name (`pokerchipapp-f7a84`) and your Apple team ID in the Xcode project. The older copy in the same repository already had the Firebase file. The Firebase key in it is not a password (it is inside every copy of the app), but it should be restricted to the app's bundle ID in the Google Cloud console (`docs/QUESTIONS.md` → B1.3), which is still open.
2. **The SSH key is an account key with no passphrase.** `~/ssh_key` was added to your GitHub account, so it can write to every repository you own, and anything running as you on this Mac can use it. Once you no longer need it, remove it from GitHub (Settings → SSH and GPG keys) and delete the two files, or give it a passphrase (`ssh-keygen -p -f ~/ssh_key`) and move it into `~/.ssh/`. For a one-off, a *deploy key* on this one repository is safer than an account key.
3. **The CI file does not run there.** GitHub only reads workflows at the root of a repository, so `.github/workflows/ci.yml` inside the folder does nothing. It works unchanged if this project ever gets a repository of its own.
