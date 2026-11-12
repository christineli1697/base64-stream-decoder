# base64-stream-decoder

Decode Base64 from stdin to raw binary on stdout, tolerating whitespace and missing padding.

```bash
source base64_stream_decoder.sh

# Decode a MIME-wrapped block from a file.
base64_stream_decoder < message.b64 > message.bin

# Or call the functions directly from another script.
printf 'aGVsbG8=' | b64_decode
# -> hello
```

The library exports two functions:

- `b64_normalize` — reads stdin, writes a whitespace-free, correctly padded Base64 string to stdout.
- `b64_decode` — reads stdin, writes raw binary to stdout.

It also runs as a filter when executed directly (`./base64_stream_decoder.sh < in.b64 > out.bin`).

## Why this exists

`base64 -d` is almost right, but it is strict about padding and chokes on the
newlines that email and many HTTP clients insert every 76 characters. Wrapping
it in a normaliser is a few lines of shell and avoids pulling in a language
runtime just to strip whitespace and append `=` characters.

The trade-off: we normalise aggressively. Any byte outside the standard Base64
alphabet (plus `=`) is discarded before decoding. That makes the decoder
forgiving of line breaks and stray spaces, but it also means a typo in the
middle of a stream will be silently ignored rather than reported. If you need
strict validation, use a dedicated decoder.

## The awkward edge

A stream whose length modulo 4 is 1 is not valid Base64. We do not try to
repair it: the normaliser passes it through unchanged and the underlying
decoder fails. This is deliberate — a remainder of 1 means a character was
lost, and guessing which one would produce wrong bytes without warning.

We also do not handle URL-safe Base64 (`-` and `_`). Mixing alphabets silently
would be worse than refusing; if you have URL-safe input, convert it first:

```bash
printf 'SGVsbG8-' | tr '_-' '/+' | b64_decode
```
