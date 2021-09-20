defmodule HPAXTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  test "new/1" do
    assert %HPAX.Table{} = HPAX.new(100)
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

  # https://datatracker.ietf.org/doc/html/rfc7541#section-4.2
  property "decode/2 accepts dynamic resizes at the start of a block" do
    enc_table = HPAX.new(20_000)
    # Start with a non-empty decode table
    dec_table = HPAX.new(20_000)
    {encoded, _enc_table} = HPAX.encode([{:store, "bogus", "BOGUS"}], dec_table)
    encoded = IO.iodata_to_binary(encoded)
    assert {:ok, _decoded, dec_table} = HPAX.decode(encoded, dec_table)
    assert dec_table.size > 0

    check all headers_to_encode <- list_of(header_with_store(), min_length: 1) do
      assert {encoded, enc_table} = HPAX.encode(headers_to_encode, enc_table)
      encoded = IO.iodata_to_binary(encoded)
      assert {:ok, _decoded, new_dec_table} = HPAX.decode(encoded, dec_table)
      assert new_dec_table.size > enc_table.size

      # Now prepend a table zeroing to the beginning and ensure that we are exactly
      # the same size as the encode table
      encoded = <<0b001::3, 0::5>> <> encoded
      assert {:ok, _decoded, new_dec_table} = HPAX.decode(encoded, dec_table)
      assert new_dec_table.size == enc_table.size
    end
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
    action = member_of([:store, :store_name, :no_store, :never_store])
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
end
