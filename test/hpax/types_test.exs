defmodule HPAX.TypesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import HPAX.Types

  describe "examples from the spec" do
    test "for encode_integer/2" do
      assert encode_integer(10, _prefix = 5) == <<0b01010::5>>
      assert encode_integer(1337, 5) == <<0b11111_10011010_00001010::21>>
      assert encode_integer(42, 8) == <<0b00101010::8>>
    end

    test "for decode_integer/2" do
      assert decode_integer(<<0b01010::5, "foo">>, _prefix = 5) == {:ok, 10, "foo"}
      assert decode_integer(<<0b11111_10011010_00001010::21, "foo">>, 5) == {:ok, 1337, "foo"}
      assert decode_integer(<<0b00101010::8, "foo">>, 8) == {:ok, 42, "foo"}
    end
  end

  test "decode_integer/2 with bad data" do
    assert decode_integer("bad integer", 5) == :error
  end

  # CVE-2026-58226
  describe "decode_integer/2 bounds (RFC 7541, section 5.1)" do
    test "decodes the largest supported value (2^32 - 1)" do
      max = 4_294_967_295
      encoded = encode_integer(max, 5)
      assert decode_integer(<<encoded::bitstring, "rest">>, 5) == {:ok, max, "rest"}
    end

    test "rejects values larger than 2^32 - 1" do
      encoded = encode_integer(4_294_967_296, 5)
      assert decode_integer(encoded, 5) == :error
    end

    test "rejects a long run of continuation octets without building a huge integer" do
      # An attacker-controlled prefix of all-ones followed by many continuation
      # octets (0xFF) would, unbounded, force O(N^2) bignum arithmetic. We must
      # bail out after a fixed number of octets rather than consume them all.
      payload = <<0b11111::5, 0::3, :binary.copy(<<0xFF>>, 1_000_000)::binary, 0x00>>

      assert {time_us, :error} = :timer.tc(fn -> decode_integer(payload, 5) end)

      # Should be near-instant. If we were consuming every octet this would take
      # seconds. Generous ceiling to avoid flakiness on slow machines.
      assert time_us < 100_000
    end
  end

  property "encoding and then decoding integers is circular" do
    check all value <- map(integer(), &abs/1),
              prefix <- integer(1..8),
              cruft <- binary() do
      encoded = encode_integer(value, prefix)
      assert decode_integer(<<encoded::bitstring, cruft::binary>>, prefix) == {:ok, value, cruft}
    end
  end

  property "encoding and then decoding strings is circular" do
    check all string <- binary(),
              cruft <- binary(),
              huffman? <- boolean() do
      encoded = encode_binary(string, huffman?)
      assert decode_binary(IO.iodata_to_binary([encoded, cruft])) == {:ok, string, cruft}
    end
  end
end
