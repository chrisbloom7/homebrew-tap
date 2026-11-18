# CLAUDE.md

`chrisbloom7/tap` is a personal Homebrew tap (`brew tap chrisbloom7/tap`). Each formula is one file in
`Formula/`; the tap has no application code of its own. Upstream projects: `to-wit` (`towit`),
`wt-cleanup` and `brewfile-tools`.

## Commands

```bash
brew style Formula/<name>.rb                         # lint (rubocop with Homebrew's config)
brew audit --strict --online chrisbloom7/tap/<name>  # formula audit
brew reinstall chrisbloom7/tap/<name> && brew test chrisbloom7/tap/<name>   # build and run the test block
bats test/                                           # tests for script/bump-formula (no network, brew or git)
```

`script-tests.yml` runs `bats test/` in CI when `script/` or `test/` changes. Install bats with
`brew install bats-core`.

`brew audit` and `brew test` by name act on Homebrew's own checkout of the tap
(`$(brew --repository chrisbloom7/tap)`), not on a worktree or clone elsewhere. Edit there when you
need them to see your change; `brew style <path>` works on any checkout.

## How versions move

- A new upstream release needs a bump PR: branch `<formula>-X.Y.Z`, commit and PR title `<formula> X.Y.Z`
  (see `git log`), merged as a normal PR with a merge commit.
- The change is the formula's `url` and `sha256` (the tag tarball from the upstream repo, `vX.Y.Z`).
  `script/bump-formula <X.Y.Z> --formula <name>` rewrites them (and nothing else): it downloads the
  tag tarball, never runs git, and leaves the diff for you to review, commit and open as the PR.
  `--repo` and `--tarball` are optional; see the header of the script. The shared `release` skill
  (`chrisbloom7-development` plugin, from the `ai-tools` marketplace) calls it from each project's
  release flow.
- Bumps are always opened by hand through that release flow. There is deliberately no scheduled
  `brew bump --open-pr` workflow (the stock `brew tap-new` autobump was removed): it would be a second
  path that conflicts with how each project's release skill bumps the tap.
- `tests.yml` runs on every PR and push to `main`. Its `test-bot` job (`brew test-bot`) checks tap syntax
  always, and builds and tests the formulae on macOS and Linux for PRs only. Its `actionlint`, `zizmor`
  (offline) and `shellcheck` (`shellcheck -S warning script/*`) jobs lint the workflows and scripts. The
  `ci-gate` job needs all four and is the only required check on `main`. The tap publishes no bottles:
  every formula installs from its source tarball, so there is no bottle-publish workflow.

## Gotchas

- Keep the table in `README.md` in step with `Formula/` when adding or removing a formula.
- Each formula's quirks live in its own file. `towit` pins its interpreter with `write_env_script` and
  `TOWIT_PYTHON`; a shell formula that needs bash 4+ must rewrite its shebang in `inreplace`.
- GitHub Actions are pinned by commit SHA with a version comment (Dependabot updates them weekly).
  Keep that when editing workflows.
- The default branch is `main`; changes go through PRs. There is no deploy: merging to `main` is what
  publishes the formula.

## Claude Code setup

`.claude/settings.json` holds the command allowlist and registers two PostToolUse hooks that lint edited
`Formula/*.rb` (`brew style --fix`) and `script/*` (`shellcheck`, errors only) files; both skip quietly
when their tools are missing. The hook blocks on `-S error` but CI fails on `-S warning`, so a script can
pass the hook and still fail CI.

Changes to `.claude/` (hooks and the allowlist) and to this file run or steer Claude Code on the machine
of whoever opens the repo, so `.github/CODEOWNERS` routes them to the maintainer. When reviewing an
outside PR that touches them, read the diff first (`gh pr diff <number> -- .claude CLAUDE.md`) before
checking the branch out and starting Claude Code there.

`.github/CODEOWNERS` also routes `.github/`, `script/` and `Formula/` to the maintainer.
