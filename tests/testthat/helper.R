# Replies built from the contract's own examples. No test touches the network or needs a key.

fixture_response <- function(file, status = 200L, headers = list()) {
  path <- test_path("fixtures", file)
  type <- if (grepl("\\.json$", file)) "application/json" else "text/plain; charset=utf-8"
  httr2::response(
    status_code = status,
    headers = c(list(`Content-Type` = type), headers),
    body = readBin(path, "raw", file.size(path))
  )
}

# Answers every request with the next reply in `replies` and keeps the requests it saw.
mock_api <- function(..., env = parent.frame()) {
  replies <- list(...)
  seen <- new.env()
  seen$requests <- list()
  httr2::local_mocked_responses(function(req) {
    seen$requests[[length(seen$requests) + 1]] <- req
    replies[[length(seen$requests)]]
  }, env = env)
  seen
}

auth_header <- function(req) httr2::req_get_headers(req, "reveal")$Authorization

# Tests run inside the package namespace, so `the` (the package's ETag cache) is in reach.
fresh_cache <- function(env = parent.frame()) {
  the$cache <- list()
  withr::defer(the$cache <- list(), envir = env)
}
