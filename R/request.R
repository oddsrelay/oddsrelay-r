base_url <- "https://api.oddsrelay.io"
max_tries <- 3 # a 429 is retried until this many requests have been made
cache_size <- 32 # URLs whose last ETag and body are kept for conditional requests

the <- new.env(parent = emptyenv())
the$cache <- list()

`%||%` <- function(x, y) if (is.null(x)) y else x

# The key: the argument, else ODDSRELAY_KEY. Trimmed, since a key read from a file often ends in a newline.
# No message here ever echoes it.
resolve_key <- function(key = NULL) {
  key <- key %||% Sys.getenv("ODDSRELAY_KEY")
  if (!is.character(key) || length(key) != 1 || is.na(key)) {
    stop("`.key` must be a single string.", call. = FALSE)
  }
  key <- trimws(key)
  if (nzchar(key) && !grepl("^[\\x21-\\x7e]+$", key, perl = TRUE)) {
    stop("The API key holds characters an HTTP header cannot carry: copy it again.", call. = FALSE)
  }
  key
}

# Filters arrive as `...`: snake_case names become the API's camelCase, vectors become comma-separated values,
# TRUE and FALSE become true and false, date-times become UTC timestamps, and NULL is left out.
query_params <- function(params) {
  params <- Filter(Negate(is.null), params)
  if (length(params) && (is.null(names(params)) || any(names(params) == ""))) {
    stop("Every filter needs a name, such as `sports = \"tennis\"`.", call. = FALSE)
  }
  names(params) <- gsub("_([a-z])", "\\U\\1", names(params), perl = TRUE)
  lapply(params, function(value) {
    if (inherits(value, "POSIXt")) value <- format(value, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    if (is.logical(value)) value <- tolower(as.character(value))
    if (is.numeric(value)) value <- format(value, scientific = FALSE, trim = TRUE)
    paste(value, collapse = ",")
  })
}

path_segment <- function(x) utils::URLencode(as.character(x), reserved = TRUE)

wait <- function(seconds) Sys.sleep(seconds)

retry_after <- function(resp) {
  seconds <- suppressWarnings(as.numeric(httr2::resp_header(resp, "Retry-After")))
  if (length(seconds) == 1 && !is.na(seconds)) seconds else 1
}

or_get <- function(path, params = list(), key = "", simplify = TRUE) {
  req <- httr2::request(base_url)
  req <- httr2::req_url_path(req, path)
  req <- do.call(httr2::req_url_query, c(list(req), query_params(params)))
  req <- httr2::req_user_agent(req, paste0("oddsrelay-r/", utils::packageVersion("oddsrelay")))
  req <- httr2::req_options(req, accept_encoding = "gzip") # sent, and the reply decompressed, by curl
  req <- httr2::req_timeout(req, 30)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  if (nzchar(key)) req <- httr2::req_auth_bearer_token(req, key) # a redacted header, never in the URL
  url <- req$url
  cached <- the$cache[[url]]
  if (!is.null(cached)) req <- httr2::req_headers(req, `If-None-Match` = cached$etag)

  for (attempt in seq_len(max_tries)) {
    resp <- httr2::req_perform(req)
    if (httr2::resp_status(resp) != 429 || attempt == max_tries) break
    wait(retry_after(resp))
  }

  status <- httr2::resp_status(resp)
  if (status == 304) return(with_headers(cached$body %||% list(), resp, not_modified = TRUE))
  if (status >= 400) stop(api_condition(resp, key))
  body <- httr2::resp_body_string(resp, encoding = "UTF-8")
  if (grepl("json", httr2::resp_content_type(resp) %||% "", fixed = TRUE)) {
    body <- jsonlite::parse_json(body, simplifyVector = simplify, simplifyMatrix = FALSE)
  }
  etag <- httr2::resp_header(resp, "ETag")
  if (!is.null(etag)) cache_set(url, etag, body)
  with_headers(body, resp)
}

cache_set <- function(url, etag, body) {
  the$cache[[url]] <- NULL
  the$cache[[url]] <- list(etag = etag, body = body)
  # ponytail: drops the oldest stored URL, not the least recently used one
  if (length(the$cache) > cache_size) the$cache <- the$cache[-1]
}

header_value <- function(resp, name) {
  value <- httr2::resp_header(resp, name)
  if (is.null(value)) NA else if (grepl("^[0-9]+$", value)) as.numeric(value) else value
}

header_list <- function(resp, prefix, fields) {
  stats::setNames(lapply(fields, function(f) header_value(resp, paste0(prefix, f))), tolower(fields))
}

tokens <- function(resp) header_list(resp, "X-Tokens-", c("Cost", "Used", "Remaining", "Limit", "Reset"))
rate_limit <- function(resp) header_list(resp, "X-RateLimit-", c("Limit", "Remaining", "Reset"))

with_headers <- function(x, resp, not_modified = FALSE) {
  attr(x, "tokens") <- tokens(resp)
  attr(x, "rate_limit") <- rate_limit(resp)
  attr(x, "etag") <- httr2::resp_header(resp, "ETag")
  attr(x, "request_id") <- httr2::resp_header(resp, "X-OddsRelay-Request-Id")
  attr(x, "not_modified") <- not_modified
  x
}

api_condition <- function(resp, key) {
  status <- httr2::resp_status(resp)
  error <- tryCatch(
    jsonlite::parse_json(httr2::resp_body_string(resp, encoding = "UTF-8"))$error,
    error = function(e) NULL # the front door's 429 and 502 have an empty body
  )
  if (!is.list(error)) error <- list()
  if (nzchar(key)) { # a key never reaches a condition, even if a message ever echoed one
    for (name in setdiff(names(error), "code")) {
      if (is.character(error[[name]])) error[[name]] <- gsub(key, "***", error[[name]], fixed = TRUE)
    }
  }
  code <- error$code
  request_id <- error$request_id %||% httr2::resp_header(resp, "X-OddsRelay-Request-Id")
  message <- paste0(
    "OddsRelay API: HTTP ", status, if (!is.null(code)) paste0(" ", code), ": ",
    error$message %||% "the reply carried no details",
    if (status == 401 && !nzchar(key)) " Set the ODDSRELAY_KEY environment variable to your key.",
    if (!is.null(request_id)) paste0(" (request_id ", request_id, ")")
  )
  fields <- list(
    message = message, call = NULL, status = status, code = code, request_id = request_id,
    error = error, tokens = tokens(resp), rate_limit = rate_limit(resp)
  )
  if (status == 402) fields[c("cost", "remaining", "resets_at")] <- error[c("cost", "remaining", "resets_at")]
  if (status == 429) fields$retry_after <- retry_after(resp)
  structure(
    class = c(if (!is.null(code)) paste0("oddsrelay_", code), paste0("oddsrelay_http_", status),
              "oddsrelay_error", "error", "condition"),
    fields
  )
}
