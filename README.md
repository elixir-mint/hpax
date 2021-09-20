# HPax

HPax is an Elixir implementation of HPACK header compression as used in HTTP/2, 
and defined in RFC 7541. HPax is (or will soon be) used by several Elixir projects, 
including the [Mint](https://github.com/elixir-mint/mint) HTTP client and the
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

