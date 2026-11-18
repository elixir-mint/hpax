# HPACK test data

The stories come from [http2jp/hpack-test-case](https://github.com/http2jp/hpack-test-case), commit `8a1406e7d14bfcb6c046021f13cc15cfb162726d`. They are distributed under the MIT license; see `LICENSE`.

This selection keeps both string encodings and a long dynamic-table sequence: `swift-nio-hpack-huffman/story_24.json` (33 cases) covers Huffman strings, `swift-nio-hpack-plain-text/story_24.json` (33 cases) covers plain-text strings, and `nghttp2-16384-4096/story_20.json` (164 cases) covers a 16,384-byte table with a wire update to 4,096 bytes. The three stories contain 230 cases total.
