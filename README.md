# HPax

[![Build Status](https://travis-ci.org/elixir-mint/hpax.svg?branch=master)](https://travis-ci.org/elixir-mint/hpax)
[![Docs](https://img.shields.io/badge/api-docs-green.svg?style=flat)](https://hexdocs.pm/hpax)
[![Hex.pm Version](http://img.shields.io/hexpm/v/hpax.svg?style=flat)](https://hex.pm/packages/hpax)

HPax is an Elixir implementation of the HPACK header compression algorithm as used in HTTP/2 and
defined in RFC 7541. HPax is (or will soon be) used by several Elixir projects, including the
[Mint](https://github.com/elixir-mint/mint) HTTP client and
[bandit](https://github.com/mtrudel/bandit) HTTP server projects.

## Installation

To install HPax, add it to your `mix.exs` file.

```elixir
defp deps do
  [
    {:hpax, "~> 0.1.0"}
  ]
end
```

Then, run `$ mix deps.get`.

## Usage

HPax is designed to be used in both encoding and decoding scenarios. In both cases, a context is
used to maintain state internal to the HPACK algorithm. In the common use case of using HPax
within HTTP/2, this context must be shared between any subsequent encoding/decoding calls within
an endpoint. Note that the contexts used for encoding and decoding within HTTP/2 are completely
distinct from one another, even though they are structurally identical.

To encode a set of headers into a binary with HPax:

```elixir
ctx = HPax.new(4096)
headers = [{:store, ":status", "201"}, {:store, "location", "http://example.com"}]
{encoded_headers, ctx} = HPax.encode(headers, ctx)
#=> {iodata, updated_context}
```

To decode a binary into a set of headers with HPax:

```elixir
ctx = HPax.new(4096)
encoded_headers = <<...>>
{:ok, headers, ctx} = HPax.decode(encoded_headers, ctx)
#=> {:ok, [{:store, ":status", "201"}, {:store, "location", "http://example.com"}], updated_context}
```

For complete usage information, please see the HPax [documentation](https://hex.pm/packages/hpax).

## Contributing

If you wish to contribute check out the [issue list](https://github.com/elixir-mint/hpax/issues) and let us know what you want to work on so we can discuss it and reduce duplicate work.

## License

Copyright 2021 Eric Meadows-Jönsson and Andrea Leopardi

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
