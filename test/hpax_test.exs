defmodule HPAXTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  test "new/1" do
    assert %HPAX.Table{} = HPAX.new(100)
  end

  describe "new/2" do
    test "raises for unknown options" do
      assert_raise ArgumentError, "unknown option: :unknown", fn ->
        HPAX.new(100, unknown: :option)
      end
    end
  end

  # https://http2.github.io/http2-spec/compression.html#rfc.section.C.2.1
  test "decode/2 with an example from the spec" do
    table = HPAX.new(1000)

    dump =
      <<0x40, 0x0A, 0x63, 0x75>> <>
        <<0x73, 0x74, 0x6F, 0x6D>> <>
        <<0x2D, 0x6B, 0x65, 0x79>> <>
        <<0x0D, 0x63, 0x75, 0x73>> <>
        <<0x74, 0x6F, 0x6D, 0x2D>> <> <<0x68, 0x65, 0x61, 0x64>> <> <<0x65, 0x72>>

    assert {:ok, headers, %HPAX.Table{}} = HPAX.decode(dump, table)
    assert headers == [{"custom-key", "custom-header"}]
  end

  # https://http2.github.io/http2-spec/compression.html#rfc.section.C.3.1
  test "encode/2 with a literal example from the spec" do
    table = HPAX.new(1000, huffman_encoding: :never)

    headers = [
      {:store, ":method", "GET"},
      {:store, ":scheme", "http"},
      {:store, ":path", "/"},
      {:store, ":authority", "www.example.com"}
    ]

    assert {encoded, %HPAX.Table{}} = HPAX.encode(headers, table)

    expected =
      <<0x82, 0x86, 0x84, 0x41, 0x0F, 0x77, 0x77, 0x77, 0x2E, 0x65, 0x78, 0x61, 0x6D, 0x70, 0x6C,
        0x65, 0x2E, 0x63, 0x6F, 0x6D>>

    assert IO.iodata_to_binary(encoded) == expected
  end

  # https://http2.github.io/http2-spec/compression.html#rfc.section.C.4.1
  test "encode/2 with a Huffman example from the spec" do
    table = HPAX.new(1000, huffman_encoding: :always)

    headers = [
      {:store, ":method", "GET"},
      {:store, ":scheme", "http"},
      {:store, ":path", "/"},
      {:store, ":authority", "www.example.com"}
    ]

    assert {encoded, %HPAX.Table{}} = HPAX.encode(headers, table)

    expected =
      <<0x82, 0x86, 0x84, 0x41, 0x8C, 0xF1, 0xE3, 0xC2, 0xE5, 0xF2, 0x3A, 0x6B, 0xA0, 0xAB, 0x90,
        0xF4, 0xFF>>

    assert IO.iodata_to_binary(encoded) == expected
  end

  test "manually doing operations on the table that property-based testing would be " <>
         "so much better at doing :( we need stateful testing folks" do
    enc_table = HPAX.new(1000)
    dec_table = HPAX.new(1000)

    {encoded, enc_table} = HPAX.encode([{:store, "a", "A"}], enc_table)
    encoded = IO.iodata_to_binary(encoded)
    assert {:ok, [{"a", "A"}], dec_table} = HPAX.decode(encoded, dec_table)
    assert dec_table.entries == [{"a", "A"}]

    {encoded, enc_table} = HPAX.encode([{:store_name, "a", "other"}], enc_table)
    encoded = IO.iodata_to_binary(encoded)
    assert {:ok, [{"a", "other"}], dec_table} = HPAX.decode(encoded, dec_table)
    assert dec_table.entries == [{"a", "A"}]

    {encoded, enc_table} = HPAX.encode([{:store_name, "b", "B"}], enc_table)
    encoded = IO.iodata_to_binary(encoded)
    assert {:ok, [{"b", "B"}], dec_table} = HPAX.decode(encoded, dec_table)
    assert dec_table.entries == [{"b", "B"}, {"a", "A"}]

    {encoded, _enc_table} = HPAX.encode([{:no_store, "c", "C"}], enc_table)
    encoded = IO.iodata_to_binary(encoded)
    assert {:ok, [{"c", "C"}], dec_table} = HPAX.decode(encoded, dec_table)
    assert dec_table.entries == [{"b", "B"}, {"a", "A"}]
  end

  property "encode/3 with a single action" do
    table = HPAX.new(500)

    check all action <- store_action(),
              headers <- list_of(header()) do
      assert {encoded, table} = HPAX.encode(action, headers, table)
      encoded = IO.iodata_to_binary(encoded)
      assert {:ok, decoded, _table} = HPAX.decode(encoded, table)
      assert decoded == headers
    end
  end

  property "encode/3 prepends dynamic resizes at the start of a block" do
    enc_table = HPAX.new(20_000)
    # Start with a non-empty decode table
    dec_table = HPAX.new(20_000)

    # Put a record in both to prime the pump. The table sizes should match
    {encoded, enc_table} = HPAX.encode([{:store, "bogus", "BOGUS"}], enc_table)
    encoded = IO.iodata_to_binary(encoded)
    assert {:ok, _decoded, dec_table} = HPAX.decode(encoded, dec_table)
    assert dec_table.size == enc_table.size
    assert enc_table.max_table_size == 20_000
    assert dec_table.max_table_size == 20_000

    # Encode a record after resizing the table. We expect a dynamic resize to be
    # encoded and the for two table sizes to be identical after decoding
    enc_table = HPAX.resize(enc_table, 0)
    enc_table = HPAX.resize(enc_table, 1234)
    {encoded, enc_table} = HPAX.encode([{:store, "lame", "LAME"}], enc_table)
    encoded = IO.iodata_to_binary(encoded)

    # Ensure that we see two resizes in order
    assert <<0b001::3, rest::bitstring>> = encoded
    assert {:ok, 0, rest} = HPAX.Types.decode_integer(rest, 5)
    assert <<0b001::3, rest::bitstring>> = rest
    assert {:ok, 1234, _rest} = HPAX.Types.decode_integer(rest, 5)

    # Finally, ensure that the decoder makes proper sense of this encoding
    assert {:ok, _decoded, dec_table} = HPAX.decode(encoded, dec_table)
    assert dec_table.size == enc_table.size
    assert enc_table.max_table_size == 1234
    assert dec_table.max_table_size == 1234
  end

  # https://datatracker.ietf.org/doc/html/rfc7541#section-4.2
  property "decode/2 accepts dynamic resizes at the start of a block" do
    enc_table = HPAX.new(20_000)
    # Start with a non-empty decode table
    dec_table = HPAX.new(20_000)

    # Put a record in both to prime the pump. The table sizes should match
    {encoded, enc_table} = HPAX.encode([{:store, "bogus", "BOGUS"}], enc_table)
    encoded = IO.iodata_to_binary(encoded)
    assert {:ok, _decoded, dec_table} = HPAX.decode(encoded, dec_table)
    assert dec_table.size == enc_table.size
    assert enc_table.max_table_size == 20_000
    assert dec_table.max_table_size == 20_000

    # Encode a record but prepend a resize to it. The decode side will now be
    # smaller since it only contains the newly added record
    old_enc_table_size = enc_table.size
    {encoded, _enc_table} = HPAX.encode([{:store, "lame", "LAME"}], dec_table)
    encoded = <<0b001::3, 0::5>> <> IO.iodata_to_binary(encoded)
    assert {:ok, _decoded, dec_table} = HPAX.decode(encoded, dec_table)
    assert dec_table.size == enc_table.size - old_enc_table_size
    assert enc_table.max_table_size == 20_000
    assert dec_table.max_table_size == 0
  end

  # https://datatracker.ietf.org/doc/html/rfc7541#section-4.2
  property "decode/2 rejects dynamic resizes anywhere but at the start of a block" do
    enc_table = HPAX.new(20_000)
    dec_table = HPAX.new(20_000)

    check all headers_to_encode <- list_of(header_with_store(), min_length: 1) do
      assert {encoded, _enc_table} = HPAX.encode(headers_to_encode, enc_table)

      encoded = IO.iodata_to_binary(encoded) <> <<0b001::3, 0::5>>
      assert {:error, :protocol_error} = HPAX.decode(encoded, dec_table)
    end
  end

  # https://datatracker.ietf.org/doc/html/rfc7541#section-6.2
  property "decode/2 rejects dynamic resizes larger than the original table size" do
    enc_table = HPAX.new(29)
    dec_table = HPAX.new(29)

    check all headers_to_encode <- list_of(header_with_store(), min_length: 1) do
      assert {encoded, _enc_table} = HPAX.encode(headers_to_encode, enc_table)

      encoded = <<0b001::3, 0b11110::5>> <> IO.iodata_to_binary(encoded)
      assert {:error, :protocol_error} = HPAX.decode(encoded, dec_table)
    end
  end

  property "encoding then decoding headers is circular" do
    table = HPAX.new(500)

    check all headers_to_encode <- list_of(header_with_action()),
              headers = for({_action, name, value} <- headers_to_encode, do: {name, value}) do
      assert {encoded, table} = HPAX.encode(headers_to_encode, table)
      encoded = IO.iodata_to_binary(encoded)
      assert {:ok, decoded, _table} = HPAX.decode(encoded, table)
      assert decoded == headers
    end
  end

  describe "interacting with joedevivo/hpack" do
    property "encoding through joedevivo/hpack and decoding through HPACK" do
      encode_table = :hpack.new_context(10_000)
      decode_table = HPAX.new(10_000)

      header_with_no_empty_value = filter(header(), fn {_name, value} -> value != "" end)

      check all headers <- list_of(header_with_no_empty_value) do
        {:ok, {encoded, _encode_table}} = :hpack.encode(headers, encode_table)
        assert {:ok, ^headers, _} = HPAX.decode(encoded, decode_table)
      end
    end

    property "encoding through HPACK and decoding through joedevivo/hpack" do
      encode_table = HPAX.new(10_000)
      decode_table = :hpack.new_context(10_000)

      check all headers_with_action <- list_of(header_with_action(), min_length: 1),
                headers = for({_action, name, value} <- headers_with_action, do: {name, value}) do
        {encoded, _encode_table} = HPAX.encode(headers_with_action, encode_table)

        assert {:ok, {^headers, _decode_table}} =
                 :hpack.decode(IO.iodata_to_binary(encoded), decode_table)
      end
    end
  end

  defp header_with_store() do
    map(header(), fn {name, value} -> {:store, name, value} end)
  end

  # Header generator.
  defp header_with_action() do
    action = store_action()
    bind(header(), fn {name, value} -> {action, constant(name), constant(value)} end)
  end

  defp header() do
    header_from_static_table =
      bind(member_of(HPAX.Table.__static_table__()), fn
        {name, nil} -> {constant(name), binary()}
        {name, value} -> constant({name, value})
      end)

    random_header = {string(0..127, min_length: 1), binary()}

    frequency([
      {1, header_from_static_table},
      {2, random_header}
    ])
  end

  defp store_action do
    member_of([:store, :store_name, :no_store, :never_store])
  end
end
