# CLAUDE.md

`chrisbloom7/tap` is a personal Homebrew tap (`brew tap chrisbloom7/tap`). Each formula is one file in
`Formula/`; the tap has no application code of its own. Upstream projects: `to-wit` (`towit`) and
`wt-cleanup`.

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
- `.github/workflows/autobump.yml` also runs `brew bump --open-pr` daily (15:30 UTC) and can open the
  same PR on its own.
- `tests.yml` (`brew test-bot`) runs on every PR and push to `main`: tap syntax, then build and test of
  the formulae on macOS and Linux. `publish.yml` (`brew pr-pull`, started by hand with a PR number) is
  the stock bottle-publish workflow from `brew tap-new`.

## Gotchas

- Keep the table in `README.md` in step with `Formula/` when adding or removing a formula.
- Each formula's quirks live in its own file. `towit` pins its interpreter with `write_env_script` and
  `TOWIT_PYTHON`; a shell formula that needs bash 4+ must rewrite its shebang in `inreplace`.
- GitHub Actions are pinned by commit SHA with a version comment (Dependabot updates them weekly).
  Keep that when editing workflows.
- The default branch is `main`; changes go through PRs. There is no deploy: merging to `main` is what
  publishes the formula.

## Claude Code setup

`.claude/settings.json` allows `brew style`, `brew audit` and `brew test`, and registers
`brew-style.sh`, a hook that runs `brew style --fix` on edited `Formula/*.rb` files and reports what
is left. It skips quietly when `brew` or `jq` is missing.

Changes to `.claude/` (hooks and the allowlist) and to this file run or steer Claude Code on the machine
of whoever opens the repo, so `.github/CODEOWNERS` routes them to the maintainer. When reviewing an
outside PR that touches them, read the diff first (`gh pr diff <number> -- .claude CLAUDE.md`) before
checking the branch out and starting Claude Code there.
