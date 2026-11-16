#!/usr/bin/env bats
# Tests for script/bump-formula. Run from the repo root with: bats test/
#
# Every test works on a throwaway tap under bats' temp dir (fixture formulas are copies of the
# real ones in Formula/, which is never touched). curl, git and brew are stubs on PATH, so
# there is no network access and no real git or brew call. Set BUMP_FORMULA_SCRIPT to run the
# suite against another copy of the script (used to check that the tests can fail).

bats_require_minimum_version 1.5.0

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# Formula contents without the top-level url/sha256 lines.
other_lines() {
  grep -v -e '^  url "' -e '^  sha256 "' "$1"
}

# Stub that records its name and arguments, then fails.
install_failing_stub() {
  local name="$1"
  cat > "${STUBS}/${name}" <<EOF2
#!/usr/bin/env bash
echo "${name} \$*" >> "\${CALL_LOG}"
exit 99
EOF2
  chmod +x "${STUBS}/${name}"
}

# curl stub: logs its arguments; mode "ok" serves ${TARBALL}, mode "fail" exits 22.
install_curl_stub() {
  local mode="$1"
  cat > "${STUBS}/curl" <<EOF2
#!/usr/bin/env bash
echo "curl \$*" >> "\${CALL_LOG}"
[ "${mode}" = "ok" ] || { echo "curl: (22) stub failure" >&2; exit 22; }
out=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o|--output) out="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
cp "${TARBALL}" "\${out}"
EOF2
  chmod +x "${STUBS}/curl"
}

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  REAL_SCRIPT="${BUMP_FORMULA_SCRIPT:-${REPO_ROOT}/script/bump-formula}"
  [ -f "${REAL_SCRIPT}" ] || { echo "script not found: ${REAL_SCRIPT}" >&2; return 1; }

  TAP="${BATS_TEST_TMPDIR}/tap"
  mkdir -p "${TAP}/Formula" "${TAP}/script"
  cp "${REAL_SCRIPT}" "${TAP}/script/bump-formula"
  SCRIPT="${TAP}/script/bump-formula"
  cp "${REPO_ROOT}/Formula/towit.rb" "${TAP}/Formula/towit.rb"
  ORIG="${BATS_TEST_TMPDIR}/towit.rb.orig"
  cp "${TAP}/Formula/towit.rb" "${ORIG}"

  # Distinct local tarballs => distinct hashes.
  TARBALL="${BATS_TEST_TMPDIR}/v1.tar.gz"
  TARBALL2="${BATS_TEST_TMPDIR}/v2.tar.gz"
  echo one > "${BATS_TEST_TMPDIR}/one"
  echo two > "${BATS_TEST_TMPDIR}/two"
  tar czf "${TARBALL}" -C "${BATS_TEST_TMPDIR}" one
  tar czf "${TARBALL2}" -C "${BATS_TEST_TMPDIR}" two
  SHA="$(sha256_of "${TARBALL}")"
  SHA2="$(sha256_of "${TARBALL2}")"

  # git/brew/curl stubs that fail loudly and log every call.
  STUBS="${BATS_TEST_TMPDIR}/stubs"
  CALL_LOG="${BATS_TEST_TMPDIR}/calls.log"
  mkdir -p "${STUBS}"
  export CALL_LOG
  install_failing_stub git
  install_failing_stub brew
  install_failing_stub curl
  # A BASH_ENV file (mise, direnv) can re-prepend its own dirs in the script's bash and shadow the stubs.
  unset BASH_ENV
  PATH="${STUBS}:${PATH}"

  # Keep script temp files inside the sandbox so leaks are visible.
  export TMPDIR="${BATS_TEST_TMPDIR}/tmp"
  mkdir -p "${TMPDIR}"
}

assert_formula_unchanged() {
  cmp "${ORIG}" "${TAP}/Formula/towit.rb"
}

assert_no_stray_files() {
  # Only the formulae we put there may exist, and nothing is left in TMPDIR.
  [ -z "$(ls -A "${TMPDIR}")" ]
  [ -z "$(ls -A "${TAP}/Formula" | grep -v '\.rb$' || true)" ]
  [ -z "$(ls -A "${TAP}/Formula" | grep '^\.' || true)" ]
  [ ! -e "${CALL_LOG}" ] || [ -z "$(grep -v '^curl ' "${CALL_LOG}" || true)" ]
}

@test "script exists, is executable bash with strict mode" {
  [ -x "${REAL_SCRIPT}" ]
  [[ "$(head -n 1 "${REAL_SCRIPT}")" == "#!"*bash* ]]
  grep -q 'set -euo pipefail' "${REAL_SCRIPT}"
}

@test "default formula and repo: the only formula, repo read from its url" {
  run "${SCRIPT}" 0.13.2 --tarball "${TARBALL}"
  [ "${status}" -eq 0 ]
  grep -qx '  url "https://github.com/chrisbloom7/to-wit/archive/refs/tags/v0.13.2.tar.gz"' "${TAP}/Formula/towit.rb"
  grep -qx "  sha256 \"${SHA}\"" "${TAP}/Formula/towit.rb"
}

@test "default tap dir is the checkout that holds the script, even from another cwd" {
  cd "${BATS_TEST_TMPDIR}"
  run "${SCRIPT}" 0.13.2 --tarball "${TARBALL}"
  [ "${status}" -eq 0 ]
  grep -qx "  sha256 \"${SHA}\"" "${TAP}/Formula/towit.rb"
}

@test "rewrites the url line with the new version and the sha256 line" {
  run "${SCRIPT}" 0.13.2 --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -eq 0 ]
  grep -qx '  url "https://github.com/chrisbloom7/to-wit/archive/refs/tags/v0.13.2.tar.gz"' "${TAP}/Formula/towit.rb"
  grep -qx "  sha256 \"${SHA}\"" "${TAP}/Formula/towit.rb"
  [[ "${SHA}" =~ ^[0-9a-f]{64}$ ]]
  # The previous url and sha256 come from the fixture copy, so this does not depend on which
  # version Formula/towit.rb is at today.
  old_url="$(grep '^  url "' "${ORIG}")"
  old_sha="$(sed -n 's/^  sha256 "\(.*\)"$/\1/p' "${ORIG}")"
  [ -n "${old_url}" ] && [ -n "${old_sha}" ]
  ! grep -qF -- "${old_url}" "${TAP}/Formula/towit.rb"
  ! grep -qF -- "${old_sha}" "${TAP}/Formula/towit.rb"
}

@test "leaves every other line byte-identical and keeps line positions" {
  run "${SCRIPT}" 0.13.2 --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -eq 0 ]
  ! cmp -s "${ORIG}" "${TAP}/Formula/towit.rb"
  diff <(other_lines "${ORIG}") <(other_lines "${TAP}/Formula/towit.rb")
  [ "$(wc -c < "${ORIG}" | tr -d ' ')" -ne 0 ]
  [ "$(wc -l < "${ORIG}")" -eq "$(wc -l < "${TAP}/Formula/towit.rb")" ]
  [ "$(grep -n '^  url "' "${ORIG}" | cut -d: -f1)" = "$(grep -n '^  url "' "${TAP}/Formula/towit.rb" | cut -d: -f1)" ]
  [ "$(grep -n '^  sha256 "' "${ORIG}" | cut -d: -f1)" = "$(grep -n '^  sha256 "' "${TAP}/Formula/towit.rb" | cut -d: -f1)" ]
}

@test "preserves the file mode and a missing trailing newline" {
  printf '%s' "$(cat "${ORIG}")" > "${TAP}/Formula/towit.rb"   # drops the final newline
  chmod 640 "${TAP}/Formula/towit.rb"
  [ "$(tail -c1 "${TAP}/Formula/towit.rb" | od -An -c | tr -d ' ')" = "d" ]
  run "${SCRIPT}" 0.13.2 --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -eq 0 ]
  [ "$(tail -c1 "${TAP}/Formula/towit.rb" | od -An -c | tr -d ' ')" = "d" ]
  [ "$(stat -c %a "${TAP}/Formula/towit.rb" 2>/dev/null || stat -f %Lp "${TAP}/Formula/towit.rb")" = "640" ]
  grep -qx "  sha256 \"${SHA}\"" "${TAP}/Formula/towit.rb"
}

@test "prints a change summary with old and new url and sha256, and says nothing was committed" {
  run "${SCRIPT}" 0.13.2 --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"0.13.2"* ]]
  [[ "${output}" == *"${SHA}"* ]]
  # Old tarball name and the start of the old sha256, read from the fixture copy (see above).
  old_tarball="$(sed -n 's|^  url ".*/\(v[^/"]*\.tar\.gz\)"$|\1|p' "${ORIG}")"
  old_sha="$(sed -n 's/^  sha256 "\(.*\)"$/\1/p' "${ORIG}")"
  [ -n "${old_tarball}" ] && [ -n "${old_sha}" ]
  [[ "${output}" == *"${old_tarball}"* ]]
  [[ "${output}" == *"${old_sha:0:8}"* ]]
  [[ "${output}" == *"Nothing was committed"* ]]
}

@test "is idempotent for the same version and tarball" {
  run "${SCRIPT}" 0.13.2 --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -eq 0 ]
  cp "${TAP}/Formula/towit.rb" "${BATS_TEST_TMPDIR}/after_first"
  run "${SCRIPT}" 0.13.2 --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"already up to date"* ]]
  cmp "${BATS_TEST_TMPDIR}/after_first" "${TAP}/Formula/towit.rb"
}

@test "a later bump replaces the previously bumped values" {
  run "${SCRIPT}" 0.13.2 --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -eq 0 ]
  run "${SCRIPT}" 1.0.0 --tap-dir "${TAP}" --tarball "${TARBALL2}"
  [ "${status}" -eq 0 ]
  grep -qx '  url "https://github.com/chrisbloom7/to-wit/archive/refs/tags/v1.0.0.tar.gz"' "${TAP}/Formula/towit.rb"
  grep -qx "  sha256 \"${SHA2}\"" "${TAP}/Formula/towit.rb"
  [ "$(grep -c '^  url "' "${TAP}/Formula/towit.rb")" -eq 1 ]
  [ "$(grep -c '^  sha256 "' "${TAP}/Formula/towit.rb")" -eq 1 ]
  diff <(other_lines "${ORIG}") <(other_lines "${TAP}/Formula/towit.rb")
}

@test "runs no git or brew, and only the named formula changes" {
  cp "${REPO_ROOT}/Formula/wt-cleanup.rb" "${TAP}/Formula/wt-cleanup.rb"
  cp "${TAP}/Formula/wt-cleanup.rb" "${BATS_TEST_TMPDIR}/wt.orig"
  run "${SCRIPT}" 0.13.2 --formula towit --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -eq 0 ]
  [ ! -e "${CALL_LOG}" ]
  cmp "${BATS_TEST_TMPDIR}/wt.orig" "${TAP}/Formula/wt-cleanup.rb"
  ! cmp -s "${ORIG}" "${TAP}/Formula/towit.rb"
  [ ! -e "${TAP}/.git" ]
}

@test "atomic write: no temp files left behind after a bump or a no-op" {
  run "${SCRIPT}" 0.13.2 --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -eq 0 ]
  assert_no_stray_files
  run "${SCRIPT}" 0.13.2 --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -eq 0 ]
  assert_no_stray_files
  [ "$(ls "${TAP}/Formula")" = "towit.rb" ]
}

@test "atomic write: a failure while rewriting leaves the formula and Formula/ untouched" {
  # python3 failing simulates a crash after the temp file is created.
  printf '#!/usr/bin/env bash\nexit 1\n' > "${STUBS}/python3"
  chmod +x "${STUBS}/python3"
  run "${SCRIPT}" 0.13.2 --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -ne 0 ]
  assert_formula_unchanged
  [ "$(ls -A "${TAP}/Formula")" = "towit.rb" ]
}

@test "--formula selects one formula when the tap has several" {
  cp "${REPO_ROOT}/Formula/wt-cleanup.rb" "${TAP}/Formula/wt-cleanup.rb"
  run "${SCRIPT}" 0.2.0 --formula wt-cleanup --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -eq 0 ]
  grep -qx '  url "https://github.com/chrisbloom7/wt-cleanup/archive/refs/tags/v0.2.0.tar.gz"' "${TAP}/Formula/wt-cleanup.rb"
  grep -qx "  sha256 \"${SHA}\"" "${TAP}/Formula/wt-cleanup.rb"
  assert_formula_unchanged
}

@test "--repo overrides the repo read from the formula url" {
  run "${SCRIPT}" 0.13.2 --repo someone/fork --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -eq 0 ]
  grep -qx '  url "https://github.com/someone/fork/archive/refs/tags/v0.13.2.tar.gz"' "${TAP}/Formula/towit.rb"
}

@test "repo falls back to chrisbloom7/<name> when the url is not a GitHub archive url" {
  sed 's#^  url ".*#  url "https://example.com/towit.tar.gz"#' "${ORIG}" > "${TAP}/Formula/towit.rb"
  run "${SCRIPT}" 0.13.2 --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -eq 0 ]
  grep -qx '  url "https://github.com/chrisbloom7/towit/archive/refs/tags/v0.13.2.tar.gz"' "${TAP}/Formula/towit.rb"
}

@test "--tarball with a local file makes no curl call" {
  run "${SCRIPT}" 0.13.2 --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -eq 0 ]
  [ ! -e "${CALL_LOG}" ]
}

@test "downloads the exact tag tarball URL via curl when --tarball is absent" {
  install_curl_stub ok
  run "${SCRIPT}" 0.13.2 --tap-dir "${TAP}"
  [ "${status}" -eq 0 ]
  [ "$(wc -l < "${CALL_LOG}" | tr -d ' ')" -eq 1 ]
  grep -qF 'https://github.com/chrisbloom7/to-wit/archive/refs/tags/v0.13.2.tar.gz' "${CALL_LOG}"
  grep -qx "  sha256 \"${SHA}\"" "${TAP}/Formula/towit.rb"
  grep -qx '  url "https://github.com/chrisbloom7/to-wit/archive/refs/tags/v0.13.2.tar.gz"' "${TAP}/Formula/towit.rb"
  [ -z "$(ls -A "${TMPDIR}")" ]
}

@test "failing download exits non-zero, leaves the formula unchanged and no temp files" {
  install_curl_stub fail
  run --separate-stderr "${SCRIPT}" 0.13.2 --tap-dir "${TAP}"
  [ "${status}" -ne 0 ]
  [[ "${stderr}" == *"download failed"* ]]
  assert_formula_unchanged
  [ -z "$(ls -A "${TMPDIR}")" ]
  [ "$(ls -A "${TAP}/Formula")" = "towit.rb" ]
}

@test "rejects malformed versions with a message on stderr and changes nothing" {
  local v
  for v in v1.2.3 1.2 1.2.3-rc1 1.2.3.4 "" abc "1.2.x" "1.2.3 " '$(id)'; do
    run --separate-stderr "${SCRIPT}" "${v}" --tap-dir "${TAP}" --tarball "${TARBALL}"
    [ "${status}" -ne 0 ]
    [[ "${stderr}" =~ [Vv]ersion|[Uu]sage ]]
    assert_formula_unchanged
  done
}

@test "missing version argument fails with usage on stderr and changes nothing" {
  run --separate-stderr "${SCRIPT}" --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -ne 0 ]
  [[ "${stderr}" =~ [Uu]sage ]]
  assert_formula_unchanged
}

@test "rejects an unknown option, an extra argument and an option with no value" {
  run --separate-stderr "${SCRIPT}" 0.13.2 --bogus --tap-dir "${TAP}"
  [ "${status}" -ne 0 ]
  [[ "${stderr}" == *"unknown option"* ]]
  run --separate-stderr "${SCRIPT}" 0.13.2 0.13.3 --tap-dir "${TAP}"
  [ "${status}" -ne 0 ]
  [[ "${stderr}" == *"unexpected argument"* ]]
  run --separate-stderr "${SCRIPT}" 0.13.2 --formula
  [ "${status}" -ne 0 ]
  [[ "${stderr}" == *"requires a value"* ]]
  assert_formula_unchanged
}

@test "rejects a path-traversal or otherwise invalid formula name" {
  cp "${ORIG}" "${BATS_TEST_TMPDIR}/x.rb"
  local n
  for n in "../x" "../../x" "/etc/passwd" ".hidden" "a/b" "Towit" 'x;id'; do
    run --separate-stderr "${SCRIPT}" 0.13.2 --formula "${n}" --tap-dir "${TAP}" --tarball "${TARBALL}"
    [ "${status}" -ne 0 ]
    [[ "${stderr}" == *"invalid formula name"* || "${stderr}" == *"not found"* ]]
    assert_formula_unchanged
  done
  cmp "${ORIG}" "${BATS_TEST_TMPDIR}/x.rb"
}

@test "rejects a malformed --repo and changes nothing" {
  local r
  for r in "noslash" "a/b/c" "a b/c" "/repo" "owner/" 'o/r;id' "o/r\"x"; do
    run --separate-stderr "${SCRIPT}" 0.13.2 --repo "${r}" --tap-dir "${TAP}" --tarball "${TARBALL}"
    [ "${status}" -ne 0 ]
    [[ "${stderr}" == *"invalid repo"* ]]
    assert_formula_unchanged
  done
}

@test "errors when the named formula does not exist" {
  run --separate-stderr "${SCRIPT}" 0.13.2 --formula nope --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -ne 0 ]
  [[ "${stderr}" == *"nope.rb"* ]]
  [ ! -e "${TAP}/Formula/nope.rb" ]
  assert_formula_unchanged
}

@test "errors listing the choices when several formulae exist and none was named" {
  cp "${REPO_ROOT}/Formula/wt-cleanup.rb" "${TAP}/Formula/wt-cleanup.rb"
  cp "${TAP}/Formula/wt-cleanup.rb" "${BATS_TEST_TMPDIR}/wt.orig"
  run --separate-stderr "${SCRIPT}" 0.13.2 --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -ne 0 ]
  [[ "${stderr}" == *"several formulae"* ]]
  [[ "${stderr}" == *"towit"* && "${stderr}" == *"wt-cleanup"* ]]
  assert_formula_unchanged
  cmp "${BATS_TEST_TMPDIR}/wt.orig" "${TAP}/Formula/wt-cleanup.rb"
}

@test "errors clearly when the tap dir does not exist or has no Formula directory" {
  run --separate-stderr "${SCRIPT}" 0.13.2 --tap-dir "${BATS_TEST_TMPDIR}/nope" --tarball "${TARBALL}"
  [ "${status}" -ne 0 ]
  [[ "${stderr}" == *"nope"* ]]
  [ ! -e "${BATS_TEST_TMPDIR}/nope" ]
  mkdir -p "${BATS_TEST_TMPDIR}/empty_tap"
  run --separate-stderr "${SCRIPT}" 0.13.2 --tap-dir "${BATS_TEST_TMPDIR}/empty_tap" --tarball "${TARBALL}"
  [ "${status}" -ne 0 ]
  [[ "${stderr}" == *"no Formula directory"* ]]
  assert_formula_unchanged
}

@test "errors when the Formula directory holds no formulae" {
  mkdir -p "${BATS_TEST_TMPDIR}/bare/Formula"
  run --separate-stderr "${SCRIPT}" 0.13.2 --tap-dir "${BATS_TEST_TMPDIR}/bare" --tarball "${TARBALL}"
  [ "${status}" -ne 0 ]
  [[ "${stderr}" == *"no formulae found"* ]]
}

@test "errors when the --tarball file does not exist and changes nothing" {
  run --separate-stderr "${SCRIPT}" 0.13.2 --tap-dir "${TAP}" --tarball "${BATS_TEST_TMPDIR}/missing.tar.gz"
  [ "${status}" -ne 0 ]
  [[ "${stderr}" == *"missing.tar.gz"* ]]
  assert_formula_unchanged
}

@test "refuses a formula with no sha256 line" {
  grep -v '^  sha256 "' "${ORIG}" > "${TAP}/Formula/towit.rb"
  cp "${TAP}/Formula/towit.rb" "${ORIG}"
  run --separate-stderr "${SCRIPT}" 0.13.2 --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -ne 0 ]
  [[ "${stderr}" == *"sha256"* ]]
  assert_formula_unchanged
}

@test "refuses a formula with no url line" {
  grep -v '^  url "' "${ORIG}" > "${TAP}/Formula/towit.rb"
  cp "${TAP}/Formula/towit.rb" "${ORIG}"
  run --separate-stderr "${SCRIPT}" 0.13.2 --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -ne 0 ]
  [[ "${stderr}" == *"url"* ]]
  assert_formula_unchanged
}

@test "refuses a formula with a duplicated url line" {
  awk '{print} /^  url "/{print}' "${ORIG}" > "${TAP}/Formula/towit.rb"
  cp "${TAP}/Formula/towit.rb" "${ORIG}"
  run --separate-stderr "${SCRIPT}" 0.13.2 --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -ne 0 ]
  [[ "${stderr}" == *"url"* ]]
  assert_formula_unchanged
}

@test "refuses a formula with a duplicated sha256 line" {
  awk '{print} /^  sha256 "/{print}' "${ORIG}" > "${TAP}/Formula/towit.rb"
  cp "${TAP}/Formula/towit.rb" "${ORIG}"
  run --separate-stderr "${SCRIPT}" 0.13.2 --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -ne 0 ]
  [[ "${stderr}" == *"sha256"* ]]
  assert_formula_unchanged
}

@test "ignores deeper-indented url/sha256 lines (resource blocks)" {
  awk '
    /^  def install/ {
      print "  resource \"extra\" do"
      print "    url \"https://example.com/other.tar.gz\""
      print "    sha256 \"0000000000000000000000000000000000000000000000000000000000000000\""
      print "  end"
      print ""
    }
    {print}' "${ORIG}" > "${TAP}/Formula/towit.rb"
  cp "${TAP}/Formula/towit.rb" "${ORIG}"
  run "${SCRIPT}" 0.13.2 --tap-dir "${TAP}" --tarball "${TARBALL}"
  [ "${status}" -eq 0 ]
  grep -qx '    url "https://example.com/other.tar.gz"' "${TAP}/Formula/towit.rb"
  grep -qx '    sha256 "0000000000000000000000000000000000000000000000000000000000000000"' "${TAP}/Formula/towit.rb"
  grep -qx '  url "https://github.com/chrisbloom7/to-wit/archive/refs/tags/v0.13.2.tar.gz"' "${TAP}/Formula/towit.rb"
  grep -qx "  sha256 \"${SHA}\"" "${TAP}/Formula/towit.rb"
  diff <(other_lines "${ORIG}") <(other_lines "${TAP}/Formula/towit.rb")
}
