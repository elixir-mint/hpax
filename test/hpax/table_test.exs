defmodule HPAX.TableTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias HPAX.Table

  test "new/1" do
    assert %Table{} = Table.new(100, :always)
  end

  test "adding headers and fetching them by value" do
    table = Table.new(10_000, :always)

    # These are in the static table.
    assert {:full, _} = Table.lookup_by_header(table, ":status", "200")
    assert {:name, _} = Table.lookup_by_header(table, ":authority", nil)
    assert {:name, _} = Table.lookup_by_header(table, ":authority", "https://example.com")

    assert Table.lookup_by_header(table, "my-nonexistent-header", nil) == :not_found
    assert Table.lookup_by_header(table, "my-nonexistent-header", "my-value") == :not_found

    table = Table.add(table, ":my-header", "my-value")

    assert {:full, _} = Table.lookup_by_header(table, ":my-header", "my-value")
    assert {:name, _} = Table.lookup_by_header(table, ":my-header", "other-value")
    assert {:name, _} = Table.lookup_by_header(table, ":my-header", nil)
  end

  test "LRU eviction" do
    dynamic_table_start = length(Table.__static_table__()) + 1

    # This fits two headers that have name and value of 4 bytes (4 + 4 + 32, twice).
    table = Table.new(80, :always)

    table = Table.add(table, "aaaa", "AAAA")
    table = Table.add(table, "bbbb", "BBBB")
    assert Table.lookup_by_index(table, dynamic_table_start + 1) == {:ok, {"aaaa", "AAAA"}}
    assert Table.lookup_by_index(table, dynamic_table_start) == {:ok, {"bbbb", "BBBB"}}

    # We need to remove one now.
    table = Table.add(table, "cccc", "CCCC")
    assert Table.lookup_by_index(table, dynamic_table_start) == {:ok, {"cccc", "CCCC"}}
    assert Table.lookup_by_index(table, dynamic_table_start + 1) == {:ok, {"bbbb", "BBBB"}}
    assert Table.lookup_by_index(table, dynamic_table_start + 2) == :error
  end

  describe "looking headers up by index" do
    test "with an index out of bounds" do
      assert Table.lookup_by_index(Table.new(100, :never), 1000) == :error
    end

    test "with an index in the static table" do
      assert Table.lookup_by_index(Table.new(100, :never), 1) == {:ok, {":authority", nil}}
    end

    test "with an index in the dynamic table" do
      table = Table.new(100, :never)
      table = Table.add(table, "my-header", "my-value")

      assert Table.lookup_by_index(table, length(Table.__static_table__()) + 1) ==
               {:ok, {"my-header", "my-value"}}
    end
  end

  property "adding a header and then looking it up always returns the index of that header" do
    check all {name, value} <- {string(0..127, min_length: 1), binary()} do
      assert %Table{} = table = Table.new(10_000, :never)
      assert %Table{} = table = Table.add(table, name, value)
      assert {:full, 62} = Table.lookup_by_header(table, name, value)
    end
  end

  describe "resize/2" do
    test "increasing the protocol max table size" do
      table = Table.new(4096, :never)
      table = Table.add(table, "aaaa", "AAAA")
      table = Table.resize(table, 8192)
      assert table.size == 40
      assert table.max_table_size == 8192
      assert table.protocol_max_table_size == 8192
    end

    test "decreasing the protocol max table size but above table size" do
      table = Table.new(4096, :never)
      table = Table.add(table, "aaaa", "AAAA")
      table = Table.resize(table, 2048)
      assert table.size == 40
      assert table.max_table_size == 2048
      assert table.protocol_max_table_size == 2048
    end

    test "decreasing the protocol max table size below current size should evict" do
      table = Table.new(4096, :never)
      table = Table.add(table, "aaaa", "AAAA")
      table = Table.add(table, "bbbb", "BBBB")
      table = Table.resize(table, 60)
      assert table.size == 40
      assert table.max_table_size == 60
      assert table.protocol_max_table_size == 60
    end
  end

  describe "dynamic_resize/2" do
    test "decreasing the max table size but above table size" do
      table = Table.new(4096, :never)
      table = Table.add(table, "aaaa", "AAAA")
      table = Table.dynamic_resize(table, 2048)
      assert table.size == 40
      assert table.max_table_size == 2048
      assert table.protocol_max_table_size == 4096
    end

    test "decreasing the protocol max table size below current size should evict" do
      table = Table.new(4096, :never)
      table = Table.add(table, "aaaa", "AAAA")
      table = Table.add(table, "bbbb", "BBBB")
      table = Table.dynamic_resize(table, 60)
      assert table.size == 40
      assert table.max_table_size == 60
      assert table.protocol_max_table_size == 4096
    end
  end
end
