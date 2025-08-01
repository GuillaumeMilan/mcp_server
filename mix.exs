defmodule McpServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :mcp_server,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug_cowboy, "~> 2.0"},
      {:bandit, "~> 1.0"},
      # TODO give the ability to use custom JSON encoder / decoder to the user
      {:jason, "~> 1.4"}
    ]
  end
end
