if Code.ensure_loaded?(JSON) do
  defmodule HPAX.HPACKVectorsTest do
    use ExUnit.Case, async: true

    @corpus Path.expand("fixtures/hpack-test-case", __DIR__)
    @story_paths @corpus
                 |> Path.join("*/story_*.json")
                 |> Path.wildcard()
                 |> Enum.reject(&(Path.basename(Path.dirname(&1)) == "raw-data"))
                 |> Enum.sort()

    unless @story_paths != [] do
      raise "Vendored HPACK story files are missing"
    end

    for path <- @story_paths do
      test "decodes #{Path.relative_to(path, @corpus)}" do
        assert_upstream_story(unquote(path))
      end
    end

    # RFC 7541 Appendix C examples: https://www.rfc-editor.org/rfc/rfc7541.html#appendix-C
    @rfc_examples [
      {"C.2.1", 4096,
       [
         {"400a637573746f6d2d6b65790d637573746f6d2d686561646572",
          [{"custom-key", "custom-header"}]}
       ]},
      {"C.2.2", 4096, [{"040c2f73616d706c652f70617468", [{":path", "/sample/path"}]}]},
      {"C.2.3", 4096, [{"100870617373776f726406736563726574", [{"password", "secret"}]}]},
      {"C.2.4", 4096, [{"82", [{":method", "GET"}]}]},
      {"C.3", 4096,
       [
         {"828684410f7777772e6578616d706c652e636f6d",
          [
            {":method", "GET"},
            {":scheme", "http"},
            {":path", "/"},
            {":authority", "www.example.com"}
          ]},
         {"828684be58086e6f2d6361636865",
          [
            {":method", "GET"},
            {":scheme", "http"},
            {":path", "/"},
            {":authority", "www.example.com"},
            {"cache-control", "no-cache"}
          ]},
         {"828785bf400a637573746f6d2d6b65790c637573746f6d2d76616c7565",
          [
            {":method", "GET"},
            {":scheme", "https"},
            {":path", "/index.html"},
            {":authority", "www.example.com"},
            {"custom-key", "custom-value"}
          ]}
       ]},
      {"C.4", 4096,
       [
         {"828684418cf1e3c2e5f23a6ba0ab90f4ff",
          [
            {":method", "GET"},
            {":scheme", "http"},
            {":path", "/"},
            {":authority", "www.example.com"}
          ]},
         {"828684be5886a8eb10649cbf",
          [
            {":method", "GET"},
            {":scheme", "http"},
            {":path", "/"},
            {":authority", "www.example.com"},
            {"cache-control", "no-cache"}
          ]},
         {"828785bf408825a849e95ba97d7f8925a849e95bb8e8b4bf",
          [
            {":method", "GET"},
            {":scheme", "https"},
            {":path", "/index.html"},
            {":authority", "www.example.com"},
            {"custom-key", "custom-value"}
          ]}
       ]},
      {"C.5", 256,
       [
         {"4803333032580770726976617465611d4d6f6e2c203231204f637420323031332032303a31333a323120474d546e1768747470733a2f2f7777772e6578616d706c652e636f6d",
          [
            {":status", "302"},
            {"cache-control", "private"},
            {"date", "Mon, 21 Oct 2013 20:13:21 GMT"},
            {"location", "https://www.example.com"}
          ]},
         {"4803333037c1c0bf",
          [
            {":status", "307"},
            {"cache-control", "private"},
            {"date", "Mon, 21 Oct 2013 20:13:21 GMT"},
            {"location", "https://www.example.com"}
          ]},
         {"88c1611d4d6f6e2c203231204f637420323031332032303a31333a323220474d54c05a04677a69707738666f6f3d4153444a4b48514b425a584f5157454f50495541585157454f49553b206d61782d6167653d333630303b2076657273696f6e3d31",
          [
            {":status", "200"},
            {"cache-control", "private"},
            {"date", "Mon, 21 Oct 2013 20:13:22 GMT"},
            {"location", "https://www.example.com"},
            {"content-encoding", "gzip"},
            {"set-cookie", "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1"}
          ]}
       ]},
      {"C.6", 256,
       [
         {"488264025885aec3771a4b6196d07abe941054d444a8200595040b8166e082a62d1bff6e919d29ad171863c78f0b97c8e9ae82ae43d3",
          [
            {":status", "302"},
            {"cache-control", "private"},
            {"date", "Mon, 21 Oct 2013 20:13:21 GMT"},
            {"location", "https://www.example.com"}
          ]},
         {"4883640effc1c0bf",
          [
            {":status", "307"},
            {"cache-control", "private"},
            {"date", "Mon, 21 Oct 2013 20:13:21 GMT"},
            {"location", "https://www.example.com"}
          ]},
         {"88c16196d07abe941054d444a8200595040b8166e084a62d1bffc05a839bd9ab77ad94e7821dd7f2e6c7b335dfdfcd5b3960d5af27087f3672c1ab270fb5291f9587316065c003ed4ee5b1063d5007",
          [
            {":status", "200"},
            {"cache-control", "private"},
            {"date", "Mon, 21 Oct 2013 20:13:22 GMT"},
            {"location", "https://www.example.com"},
            {"content-encoding", "gzip"},
            {"set-cookie", "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1"}
          ]}
       ]}
    ]

    for {section, table_size, blocks} <- @rfc_examples do
      test "decodes RFC 7541 Appendix #{section}" do
        assert_rfc_story(unquote(Macro.escape(blocks)), unquote(table_size), unquote(section))
      end
    end

    defp assert_upstream_story(path) do
      story = path |> File.read!() |> JSON.decode!()
      first_case = hd(story["cases"])
      initial_size = first_case["header_table_size"] || 4096

      story["cases"]
      |> Enum.with_index()
      |> Enum.reduce({initial_size, HPAX.new(initial_size)}, fn {test_case, index},
                                                                {table_size, table} ->
        {table_size, table} =
          case test_case["header_table_size"] do
            new_size when is_integer(new_size) and new_size != table_size ->
              {new_size, HPAX.protocol_resize(table, new_size)}

            _ ->
              {table_size, table}
          end

        expected =
          Enum.map(test_case["headers"], fn header ->
            [{name, value}] = Map.to_list(header)
            {name, value}
          end)

        location = "#{Path.relative_to(path, @corpus)} case #{index}"

        decode(test_case["wire"], expected, table, location)
        |> then(&{table_size, &1})
      end)

      :ok
    end

    defp assert_rfc_story(blocks, table_size, section) do
      blocks
      |> Enum.with_index()
      |> Enum.reduce(HPAX.new(table_size), fn {{wire, expected}, index}, table ->
        decode(wire, expected, table, "RFC 7541 Appendix #{section} case #{index}")
      end)

      :ok
    end

    defp decode(wire, expected, table, location) do
      case HPAX.decode(Base.decode16!(wire, case: :lower), table) do
        {:ok, headers, updated_table} ->
          assert headers == expected, "#{location}: decoded headers differ"
          updated_table

        {:error, reason} ->
          flunk("#{location}: decode failed: #{inspect(reason)}")
      end
    end
  end
end
