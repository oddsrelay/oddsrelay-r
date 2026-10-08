#' Matched boards and raw odds
#'
#' `or_odds()` reads one matched board, where each selection pairs bookmaker
#' back prices with exchange lay prices. `or_raw()` reads bookmaker and
#' exchange prices by event, unpaired, a page at a time. `or_event()` reads one
#' event's raw prices. These calls spend tokens: pass `quote = TRUE` to learn
#' what a call costs without making it.
#'
#' @param type The board: `"standard"`, `"2up"`, `"dutching"`, `"each-way"`,
#'   `"extra-place"` or `"bog"`.
#' @param id An event id: `event_id` on a board, or `id` on a raw page or an
#'   `or_events()` row.
#' @param ... Filters, named as in the API reference, such as `region`,
#'   `sports`, `bookmakers` or `markets`. `snake_case` names work too
#'   (`odds_format` is sent as `oddsFormat`). A vector is sent as one
#'   comma-separated value, `TRUE` as `true`, and a date-time as a UTC
#'   timestamp. The API refuses names and values it does not know.
#' @param .key Your API key. Left out, it is read from the `ODDSRELAY_KEY`
#'   environment variable.
#' @return The decoded JSON body as a list, with arrays of records as data
#'   frames; a `format = "bare"` call returns the data frame alone. The reply's
#'   token and rate limit headers ride along as attributes: see
#'   [oddsrelay-package].
#' @examplesIf interactive() && nzchar(Sys.getenv("ODDSRELAY_KEY"))
#' # What would it cost?
#' or_odds("standard", region = "uk", sports = "soccer", quote = TRUE)
#'
#' board <- or_odds("standard", region = "uk", sports = "soccer", markets = "h2h")
#' board$data[, c("commence_time", "home_team", "away_team")]
#' attr(board, "tokens")
#'
#' page <- or_raw(region = "uk", sports = "tennis", limit = 50)
#' page$meta$next_cursor
#' @export
or_odds <- function(type, ..., .key = NULL) {
  or_get(paste0("/v2/odds/", path_segment(type)), list(...), resolve_key(.key))
}

#' @rdname or_odds
#' @export
or_raw <- function(..., .key = NULL) {
  or_get("/v2/odds/raw", list(...), resolve_key(.key))
}

#' @rdname or_odds
#' @export
or_event <- function(id, ..., .key = NULL) {
  or_get(paste0("/v2/odds/event/", path_segment(id)), list(...), resolve_key(.key))
}

#' Sports, events, bookmakers and regions
#'
#' The keys the odds calls filter on. `or_sports()` lists sport and
#' competition keys and `or_events()` the upcoming events for one sport key,
#' both a page at a time (pass `meta$next_cursor` back as `cursor`).
#' `or_bookmakers()` lists the bookmakers and exchanges with their keys, and
#' `or_regions()` the region codes open to your key. These calls spend no
#' tokens.
#'
#' @param sport A sport key from `or_sports()`.
#' @inheritParams or_odds
#' @inherit or_odds return
#' @examplesIf interactive() && nzchar(Sys.getenv("ODDSRELAY_KEY"))
#' sports <- or_sports(region = "uk")
#' head(sports$data[, c("key", "title")])
#'
#' or_events("tennis", region = "uk")
#' or_bookmakers(format = "bare")
#' or_regions()
#' @export
or_sports <- function(..., .key = NULL) {
  or_get("/v2/sports", list(...), resolve_key(.key))
}

#' @rdname or_sports
#' @export
or_events <- function(sport, ..., .key = NULL) {
  or_get("/v2/events", c(list(sport = sport), list(...)), resolve_key(.key))
}

#' @rdname or_sports
#' @export
or_bookmakers <- function(..., .key = NULL) {
  or_get("/v2/bookmakers", list(...), resolve_key(.key))
}

#' @rdname or_sports
#' @export
or_regions <- function(.key = NULL) {
  or_get("/v2/regions", key = resolve_key(.key))
}

#' Service state
#'
#' `or_status()` says whether each product is serving and needs no key.
#' `or_coverage()` lists which bookmakers, exchanges and sports each product
#' carries; it needs no key, and gives more detail with one. `or_health()`
#' says when each board was last processed and whether any is behind.
#' `or_healthz()` is a plain-text liveness check and `or_openapi()` returns the
#' API description; neither needs a key.
#'
#' @inheritParams or_odds
#' @return As for [or_odds()]. `or_healthz()` returns a single string and
#'   `or_openapi()` a list that keeps the description's own structure.
#' @examplesIf interactive()
#' or_status(region = "uk")
#' names(or_coverage(region = "uk")$products)
#' cat(or_healthz())
#' or_openapi()$info$version
#' @export
or_status <- function(..., .key = NULL) { # the route is keyless: `.key` is accepted and never sent
  or_get("/v2/status", list(...))
}

#' @rdname or_status
#' @export
or_coverage <- function(..., .key = NULL) {
  or_get("/v2/coverage", list(...), resolve_key(.key))
}

#' @rdname or_status
#' @export
or_health <- function(.key = NULL) {
  or_get("/v2/health", key = resolve_key(.key))
}

#' @rdname or_status
#' @export
or_healthz <- function() {
  or_get("/healthz")
}

#' @rdname or_status
#' @export
or_openapi <- function() {
  or_get("/v2/openapi.json", simplify = FALSE)
}

#' Your account
#'
#' `or_usage()` returns the tokens your account has used and has left, and
#' what your key may read. `or_pricing()` returns the token rate card. Neither
#' spends tokens.
#'
#' @inheritParams or_odds
#' @inherit or_odds return
#' @examplesIf interactive() && nzchar(Sys.getenv("ODDSRELAY_KEY"))
#' or_usage()$tokens
#' or_pricing()
#' @export
or_usage <- function(.key = NULL) {
  or_get("/v2/usage", key = resolve_key(.key))
}

#' @rdname or_usage
#' @export
or_pricing <- function(.key = NULL) {
  or_get("/v2/pricing", key = resolve_key(.key))
}
