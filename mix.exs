defmodule McpServer.MixProject do
  use Mix.Project

  @source_url "https://github.com/GuillaumeMilan/mcp_server"

  def project do
    [
      app: :mcp_server,
      version: "0.5.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "HTTP implementation of the MCP (Model Context Protocol) with typed structs",
      package: package(),

      # Docs
      name: "HTTP MCP Server",
      docs: docs(),
      source_url: @source_url
    ]
  end

  defp package do
    [
      maintainers: ["Guillaume Milan"],
      licenses: ["X11"],
      links: %{
        "GitHub" => @source_url,
        "MCP" => "https://modelcontextprotocol.io/introduction"
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {McpServer.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"},
      {:bandit, "~> 1.0"},
      # TODO give the ability to use custom JSON encoder / decoder to the user
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},

      # Documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "MIGRATION_GUIDE.md",
        "STRUCTURES.md",
        "CHANGELOG_v0.4.0.md",
        "QUICK_MIGRATION_REFERENCE.md"
      ],
      groups_for_extras: [
        "Getting Started": ["README.md"],
        "Migration & Upgrade": [
          "MIGRATION_GUIDE.md",
          "QUICK_MIGRATION_REFERENCE.md",
          "CHANGELOG_v0.4.0.md"
        ],
        Reference: ["STRUCTURES.md"]
      ],
      source_url: @source_url,
      formatters: ["html"]
    ]
  end
end
