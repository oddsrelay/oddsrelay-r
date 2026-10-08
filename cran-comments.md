## Before submitting (delete this section)

The `Authors@R` field names "OddsRelay" as maintainer, a placeholder. CRAN asks for a named person as maintainer,
so replace it with that person (given and family name, role `c("aut", "cre")`) and keep OddsRelay as `cph`, then
rebuild and re-run the check below.

## Test environments

* local macOS (aarch64-apple-darwin20), R 4.5.3
* GitHub Actions (macOS, Windows and Ubuntu; R devel, release and oldrel-1), once the repository is public

## R CMD check results

`R CMD check --as-cran --no-manual` on the built tarball:

0 errors | 0 warnings | 2 notes

* This is a new submission.
* The GitHub URLs in `DESCRIPTION` answered 404 because the repository was not yet public when the check ran. They
  resolve now.
* README.md and NEWS.md could not be checked locally because pandoc was not installed on that machine.

## Notes for the reviewer

* The package wraps a web service that needs an API key for most calls. Examples are wrapped in
  `@examplesIf interactive() && nzchar(Sys.getenv("ODDSRELAY_KEY"))`, or `interactive()` for the routes that need no
  key, so they make no network call during checks.
* The tests use 'httr2' mocked responses built from the service's published examples. They make no network call and
  need no key.
