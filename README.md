# oddsrelay

The OddsRelay R client. One function for each GET route of the [OddsRelay API](https://oddsrelay.io/docs), which
serves bookmaker and exchange odds for the UK & Ireland as JSON. Replies come back as lists and data frames.

## Install

```r
install.packages("oddsrelay")

# or the development version
# install.packages("pak")
pak::pak("oddsrelay/oddsrelay-r")
```

## Get a key

Sign up at [app.oddsrelay.io/signup](https://app.oddsrelay.io/signup) and copy your key from the dashboard.
Free gives you 50,000 tokens for 14 days from sign-up, with no card, then no tokens until you choose a plan, on the same key. [Plans and token prices](https://oddsrelay.io/pricing).
Paid plans are for your own use. A product that serves other people runs on Enterprise.

## First call

Put your key in your `.Renviron` (open it with `file.edit("~/.Renviron")`), never in a script:

```
ODDSRELAY_KEY=your key
```

Restart R, then:

```r
library(oddsrelay)

board <- or_odds("standard", region = "uk", sports = "soccer", markets = "h2h") # soccer is the API's key for football
board$data[, c("commence_time", "home_team", "away_team")]

attr(board, "tokens") # what the call cost and what is left
```

No key yet? These answer without one:

```r
or_status()
names(or_coverage(region = "uk")$products)
```

## Functions

| Function | Route | What it returns |
|---|---|---|
| `or_odds(type, ...)` | `GET /v2/odds/{type}` | Matched odds for one board: `standard`, `2up`, `dutching`, `each-way`, `extra-place` or `bog` |
| `or_raw(...)` | `GET /v2/odds/raw` | Bookmaker and exchange prices by event, unpaired, a page at a time |
| `or_event(id, ...)` | `GET /v2/odds/event/{id}` | One event's raw prices |
| `or_sports(...)` | `GET /v2/sports` | Sport and competition keys |
| `or_events(sport, ...)` | `GET /v2/events` | Upcoming events for one sport key |
| `or_bookmakers(...)` | `GET /v2/bookmakers` | The bookmakers and exchanges you can filter on, with their keys |
| `or_regions()` | `GET /v2/regions` | The region codes open to your key |
| `or_coverage(...)` | `GET /v2/coverage` | Which bookmakers and sports each product carries (keyless; more detail with a key) |
| `or_status(...)` | `GET /v2/status` | Whether each product is serving (keyless) |
| `or_health()` | `GET /v2/health` | When each board was last processed, and whether any is behind |
| `or_usage()` | `GET /v2/usage` | Tokens used and left, and what your key may read |
| `or_pricing()` | `GET /v2/pricing` | The token rate card |
| `or_openapi()` | `GET /v2/openapi.json` | The API description (keyless) |
| `or_healthz()` | `GET /healthz` | A plain-text liveness check (keyless) |

Each returns the decoded body with every field kept, including fields the API adds after this release. Arrays of
records become data frames, so `board$data` above is one. Pass `format = "bare"` where a route takes it to get the data
frame alone.

## Filters

Every query parameter in the [API reference](https://oddsrelay.io/docs/reference) is a named argument. The API's
camelCase and R's snake_case both work, so `odds_format = "decimal"` and `oddsFormat = "decimal"` send the same thing.
A vector becomes one comma-separated value, `TRUE` and `FALSE` become `true` and `false`, a date-time becomes a UTC
timestamp, and `NULL` is left out:

```r
now <- Sys.time()
or_odds(
  "each-way",
  region = "uk",
  sports = "horse_racing",
  commence_time_from = now,
  commence_time_to = now + 6 * 3600
)
```

The API checks every filter itself. An unknown name or value signals `oddsrelay_bad_request` or a more specific class
such as `oddsrelay_unknown_sport`, and where the API lists the accepted values, `e$error$valid` holds them.

## Price a call before you make it

`quote = TRUE` asks what a call would cost instead of making it. A quote spends no tokens:

```r
quote <- or_odds("standard", region = "uk", quote = TRUE)
quote$cost
quote$remaining
```

## Polling: spend tokens only on changes

For each URL it has fetched in this session, the package keeps the reply's `ETag` and sends it back as
`If-None-Match`. When nothing has changed the API answers 304, which spends no tokens, and you get back the body you
already had with `attr(x, "not_modified")` set to `TRUE`:

```r
repeat {
  board <- or_odds("standard", region = "uk", sports = "soccer")
  if (!attr(board, "not_modified")) update_my_screen(board$data)
  Sys.sleep(poll_seconds)
}
```

## Paging

`or_raw()`, `or_sports()` and `or_events()` return a page at a time. Pass the next page's cursor back as `cursor`:

```r
cursor <- NULL
repeat {
  page <- or_raw(region = "uk", sports = "tennis", cursor = cursor)
  handle(page$data)
  cursor <- page$meta$next_cursor
  if (is.null(cursor)) break
}
```

## Errors

A refusal signals a condition of class `oddsrelay_error`. In front of that sit `oddsrelay_<code>`, from the error
code in the reply, and `oddsrelay_http_<status>`. Each condition carries `status`, `code`, `request_id`, `error` (the
whole error object), `tokens` and `rate_limit`.

| Status | Example classes |
|---|---|
| 400 | `oddsrelay_bad_request`, `oddsrelay_unknown_sport`, `oddsrelay_http_400` |
| 401 | `oddsrelay_missing_api_key`, `oddsrelay_invalid_api_key`, `oddsrelay_http_401` |
| 402 | `oddsrelay_insufficient_tokens`, with `cost`, `remaining` and `resets_at` |
| 403 | `oddsrelay_sport_not_in_plan`, `oddsrelay_http_403` |
| 404 | `oddsrelay_unknown_event`, `oddsrelay_http_404` |
| 429 | `oddsrelay_too_many_requests`, with `retry_after`, once the package's own retries are used up |
| 5xx | `oddsrelay_http_500`, `oddsrelay_http_502`, `oddsrelay_http_503` |

Branch on the class or `e$code`, never on the message, which may change. Quote `request_id` when you contact us.

```r
tryCatch(
  or_odds("dutching", region = "uk"),
  oddsrelay_insufficient_tokens = function(e) {
    message("needs ", e$cost, " tokens, ", e$remaining, " left until ", e$resets_at)
  }
)
```

A 429 is retried for you: the package says how long it will wait, waits the `Retry-After` seconds and tries again,
three requests in all.
Network failures are left as 'httr2' signals them, so a long-running loop also handles `httr2_failure`.

## Tokens and rate limits

Every result carries the reply's headers as attributes:

- `tokens`: `cost`, `used`, `remaining`, `limit` and `reset`, from the `X-Tokens-*` headers
- `rate_limit`: `limit`, `remaining` and `reset`, from the `X-RateLimit-*` headers
- `etag`, `request_id` and `not_modified`

A header the reply did not carry reads as `NA`. Printing a result shows the body and one line of tokens, not the
attributes; `unclass()` gives the plain list.

## Your key

The key travels only in the `Authorization` header. The package never puts it in a URL, and it is redacted when a
request is printed and removed from any condition message. A filter named like a key (`key`, `api_key`, `token` or
any name starting with a dot) is refused before anything is sent, so a misspelt `.key` never reaches a URL. Spaces and newlines around the key, common when it is
read from a file, are dropped.

## Versions

The `Config/oddsrelay/contract-version` field of `DESCRIPTION` names the version of the API description these
functions follow:

```r
utils::packageDescription("oddsrelay")[["Config/oddsrelay/contract-version"]]
```

The API only adds to `/v2`, so new fields and new error codes reach you without an upgrade.

## More from OddsRelay

- [oddsrelay-python](https://github.com/oddsrelay/oddsrelay-python): the Python client, `pip install oddsrelay`
- [oddsrelay-js](https://github.com/oddsrelay/oddsrelay-js): the JavaScript and TypeScript client, `npm install oddsrelay`
- [oddsrelay-mcp](https://github.com/oddsrelay/oddsrelay-mcp): an MCP server that gives Claude, Cursor and other AI assistants read access, with a token cap
- [oddsrelay-sheets](https://github.com/oddsrelay/oddsrelay-sheets): formulas and a template spreadsheet for Google Sheets
- [examples](https://github.com/oddsrelay/examples): short programs to copy, one folder each
- [Libraries and tools](https://oddsrelay.io/docs/libraries), the [docs](https://oddsrelay.io/docs), the [API reference](https://oddsrelay.io/docs/reference) and the [OpenAPI file](https://api.oddsrelay.io/v2/openapi.json)
- Contact: hello@oddsrelay.io

## Licence

MIT. See [LICENSE.md](https://github.com/oddsrelay/oddsrelay-r/blob/main/LICENSE.md).
