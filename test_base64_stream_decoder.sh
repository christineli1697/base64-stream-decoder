#!/usr/bin/env bash
# Tests for base64-stream-decoder. Run with: bash test_base64_stream_decoder.sh
#
# The test harness is deliberately tiny: one assert_eq function, TAP-like
# output, and a non-zero exit on the first failure. We source the library so
# we exercise the real exported functions, not a re-implementation.

set -euo pipefail

# shellcheck source=base64_stream_decoder.sh
source "$(dirname "$0")/base64_stream_decoder.sh"

PASS=0
FAIL=0

assert_eq() {
    local expected="$1"
    local actual="$2"
    local label="$3"
    if [ "$expected" = "$actual" ]; then
        printf 'ok %d - %s\n' "$((PASS + FAIL + 1))" "$label"
        PASS=$((PASS + 1))
    else
        printf 'not ok %d - %s\n' "$((PASS + FAIL + 1))" "$label"
        printf '  expected: %q\n' "$expected"
        printf '  actual:   %q\n' "$actual"
        FAIL=$((FAIL + 1))
    fi
}

# Helper: run b64_decode on a string and capture stdout as text. We use
# `printf '%s'` rather than `echo` so that no trailing newline is added to
# the input, which would change the decoded bytes.
decode_text() {
    printf '%s' "$1" | b64_decode
}

# --- happy path ------------------------------------------------------------

assert_eq "hello" "$(decode_text 'aGVsbG8=')" "decodes a simple padded string"
assert_eq ""      "$(decode_text '')"       "empty input decodes to empty output"

# --- whitespace tolerance -------------------------------------------------

# Newlines inside the stream (the classic MIME-wrapped case).
assert_eq "hello" "$(decode_text $'aGVs\nbG8=')" "tolerates a newline inside the stream"
assert_eq "hello" "$(decode_text $'aGVs\r\nbG8=')" "tolerates CRLF inside the stream"
assert_eq "hello" "$(decode_text 'aG Vs bG8=')" "tolerates spaces inside the stream"
assert_eq "hello" "$(decode_text $'\n\naGVsbG8=\n\n')" "tolerates leading and trailing newlines"

# --- padding tolerance ----------------------------------------------------

# Two bytes of input -> 4 chars with one '='. If we drop the '=', the decoder
# should still recover the same two bytes.
assert_eq "hi" "$(decode_text 'aGk=')" "decodes with explicit padding"
assert_eq "hi" "$(decode_text 'aGk')"  "adds missing padding for a 2-byte payload"

# One byte of input -> 4 chars with two '='.
assert_eq "h" "$(decode_text 'aA==')" "decodes with two padding characters"
assert_eq "h" "$(decode_text 'aA')"   "adds missing padding for a 1-byte payload"

# --- awkward cases --------------------------------------------------------

# A stream whose length mod 4 is 1 is not valid Base64. Our normaliser leaves
# it alone and lets the decoder fail; the important thing is that we do not
# silently invent or drop bytes. We assert that the command fails.
if printf 'a' | b64_decode >/dev/null 2>&1; then
    assert_eq "failure" "success" "length mod 4 == 1 is rejected"
else
    assert_eq "failure" "failure" "length mod 4 == 1 is rejected"
fi

# Binary output: 0x00 0x01 0x02 0x03 encodes to AAECAw==. We compare the
# decoded bytes with `od` rather than trying to hold NUL in a shell string.
expected_hex="00010203"
actual_hex=$(printf 'AAECAw==' | b64_decode | od -An -tx1 | tr -d ' \n')
assert_eq "$expected_hex" "$actual_hex" "decodes to raw binary including NUL"

# Whitespace mixed with padding: the normaliser should strip the whitespace
# first, then add any missing padding.
assert_eq "hi" "$(decode_text $'a G k\n')" "strips whitespace before fixing padding"

# --- summary --------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
