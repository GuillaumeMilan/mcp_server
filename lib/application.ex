defmodule McpServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = []

    # Create the ETS table for sessions
    :ets.new(McpServer.Session, [:named_table, :public, read_concurrency: true])

    opts = [strategy: :one_for_one, name: McpServer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
