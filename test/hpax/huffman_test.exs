defmodule HPAX.HuffmanTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias HPAX.Huffman

  property "encoding and then decoding is circular" do
    check all binary <- binary() do
      encoded = Huffman.encode(binary)
      assert is_binary(encoded)
      assert Huffman.decode(encoded) == binary
    end
  end

  property "encoding and decoding match joedevivo/hpack's :huffman" do
    check all binary <- string(:ascii) do
      encoded = Huffman.encode(binary)
      assert encoded == :huffman.encode(binary)
      assert Huffman.decode(encoded) == :huffman.decode(encoded)
    end
  end

  describe "decode/1 with malformed input" do
    test "raises a catchable :hpax error instead of a FunctionClauseError when the trailing bits don't correspond to any complete code" do
      # 8+ bits of all 1s is a valid prefix of the 30-bit EOS code but is neither a complete
      # code nor <= 7 bits of valid EOS padding, so it can't come from a real encoder
      for n_bits <- [8, 9, 15, 16, 23, 29] do
        invalid = for _ <- 1..n_bits, into: <<>>, do: <<1::1>>

        assert catch_throw(Huffman.decode(invalid)) ==
                 {:hpax, {:protocol_error, :invalid_huffman_encoding}}
      end
    end
  end
end
