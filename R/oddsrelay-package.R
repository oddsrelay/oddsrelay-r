#' @section Your key:
#' Every function but [or_status()], [or_coverage()], [or_healthz()] and
#' [or_openapi()] needs a key. Each reads it from the `ODDSRELAY_KEY`
#' environment variable, or from its `.key` argument. Put the key in your
#' `.Renviron` rather than in a script. It travels only in the `Authorization`
#' header: never in a URL, and never in a printed request, a message or a
#' condition.
#'
#' @section What a call returns:
#' The decoded JSON body, with every field the API sends, including fields it
#' adds after this release. Arrays of records become data frames. Each result
#' carries these attributes:
#'
#' * `tokens`: a list of `cost`, `used`, `remaining`, `limit` and `reset`, from
#'   the `X-Tokens-*` headers. `remaining` and `limit` may be `"unlimited"`.
#' * `rate_limit`: a list of `limit`, `remaining` and `reset`, from the
#'   `X-RateLimit-*` headers.
#' * `etag` and `request_id`.
#' * `not_modified`: `TRUE` when the API answered 304 (see below).
#'
#' A header the reply did not carry reads as `NA` (or `NULL` for `etag` and
#' `request_id`). A result that is not a data frame has the class
#' `oddsrelay_result`, which prints the body and one line of tokens instead of
#' every attribute; `unclass()` gives the plain list or string.
#'
#' @section Polling:
#' For each URL it has fetched in this session, the package keeps the reply's
#' `ETag` and body, and sends the tag back as `If-None-Match`. When nothing has
#' changed the API answers 304, which spends no tokens, and the call returns
#' the body you already had with `attr(x, "not_modified")` set to `TRUE`.
#'
#' @section Errors:
#' A refusal signals a condition of class `oddsrelay_error`, with the classes
#' `oddsrelay_<code>` (from the body's `error.code`, such as
#' `oddsrelay_insufficient_tokens`) and `oddsrelay_http_<status>` in front of
#' it. Each carries `status`, `code`, `request_id`, `error` (the whole error
#' object), `tokens` and `rate_limit`. A 402 also carries `cost`, `remaining`
#' and `resets_at`. Branch on the class or `code`, never on the message. Quote
#' `request_id` when you contact us.
#'
#' A 429 is retried for you: the package waits the `Retry-After` seconds and
#' tries again, three requests in all, with a message before each wait, then
#' signals `oddsrelay_http_429` with `retry_after`. Network failures are left as
#' 'httr2' signals them.
#'
#' @keywords internal
"_PACKAGE"
