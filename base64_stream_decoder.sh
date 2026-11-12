#!/usr/bin/env bash
# base64-stream-decoder: decode Base64 from stdin to raw binary on stdout.
#
# Design decisions:
#   * Pure bash + coreutils (base64, tr, sed) — no Python, no Perl, no network.
#   * We do not attempt to fully validate Base64; we normalise the input stream
#     (strip whitespace, fix missing padding) and hand it to `base64 -d`.
#   * GNU coreutils' `base64 -d` is lenient about some things but not all, so
#     the normalisation step is where we absorb the awkward cases the brief
#     mentions: whitespace anywhere, and missing `=` padding at the end.
#   * We deliberately do NOT try to decode URL-safe Base64 (`-` and `_`).
#     The brief says "Base64", and mixing alphabets silently would be a
#     footgun. If you need URL-safe, pipe through `tr '_-' '/+'` first.
#
# Exported functions:
#   b64_normalize  — read stdin, write normalised Base64 to stdout
#   b64_decode     — read stdin, write raw binary to stdout
#
# Both are safe to call from a sourced script; the file has no top-level side
# effects.

set -euo pipefail

# Read all of stdin into a single variable. We use a command substitution
# rather than a while-read loop because we need to strip *all* whitespace
# including newlines, and because command substitution is the only portable
# way to get binary-safe behaviour out of bash without temp files. The input
# is Base64 text, so it is ASCII and safe to hold in a shell variable.
b64_normalize() {
    local raw
    raw=$(cat)

    # Remove every character that is not part of the standard Base64 alphabet
    # or the padding character. `tr -cd` keeps only the listed characters.
    # This handles spaces, tabs, CR, LF, and any other stray bytes.
    local compact
    compact=$(printf '%s' "$raw" | tr -cd 'A-Za-z0-9+/=')

    # Fix padding. A valid Base64 stream has length divisible by 4. If the
    # caller stripped padding (or the encoder omitted it), we add back the
    # minimum number of '=' characters. We never remove existing '=' — that
    # would be a different (and lossy) operation.
    local len=${#compact}
    local rem=$((len % 4))
    if [ "$rem" -eq 1 ]; then
        # A remainder of 1 is impossible for valid Base64. We let the decoder
        # below fail rather than silently dropping a character, because
        # dropping a character changes the decoded bytes.
        printf '%s' "$compact"
        return 0
    fi
    if [ "$rem" -ne 0 ]; then
        local pad=$((4 - rem))
        local i=0
        while [ "$i" -lt "$pad" ]; do
            compact="${compact}="
            i=$((i + 1))
        done
    fi

    printf '%s' "$compact"
}

# Decode Base64 from stdin to raw binary on stdout. The normalisation step
# above is what makes us tolerant of whitespace and missing padding; the
# actual decoding is delegated to `base64 -d`, which is the only coreutils
# tool that produces raw binary correctly on every platform we care about.
b64_decode() {
    b64_normalize | base64 -d 2>/dev/null
}

# If this file is executed directly (not sourced), act as a filter. This is
# the smallest useful CLI: `cat file.b64 | ./base64_stream_decoder.sh > out`.
# We check BASH_SOURCE so that sourcing the file in a test does not run main.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    b64_decode
fi
