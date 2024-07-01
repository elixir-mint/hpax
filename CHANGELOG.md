# Changelog

## v1.0.0

  * Silence warnings on Elixir 1.17+.
  * Require Elixir 1.12+.

## v0.2.0

  * Add `HPAX.new/2`, which supports a list of options. For now, the only option
    is `:huffman_encoding`, to choose whether to use Huffman encoding or not.
  * Add `HPAX.encode/3`, which supports encoding all headers with the same
    action.
  * Add the `HPAX.table/0` opaque type.

## v0.1.2

  * Fix `use Bitwise` deprecation warning.

## v0.1.1

  * Improve checking of dynamic resize updates.
