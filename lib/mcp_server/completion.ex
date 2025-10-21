defmodule McpServer.Completion do
  @moduledoc """
  Represents completion suggestions for prompt arguments or resource URI template variables.

  This module provides a structured way to return auto-completion suggestions
  to clients. It's used by both prompt argument completion and resource URI
  template variable completion.

  ## Fields

  - `values` - List of completion suggestions
  - `total` - Total number of possible completions (optional)
  - `has_more` - Whether there are more completions available beyond those returned (optional)

  ## Examples

      iex> completion = McpServer.Completion.new(
      ...>   values: ["Alice", "Bob", "Charlie"]
      ...> )
      %McpServer.Completion{
        values: ["Alice", "Bob", "Charlie"]
      }

      iex> completion = McpServer.Completion.new(
      ...>   values: ["option1", "option2"],
      ...>   total: 100,
      ...>   has_more: true
      ...> )
      %McpServer.Completion{
        values: ["option1", "option2"],
        total: 100,
        has_more: true
      }
  """

  @enforce_keys [:values]
  defstruct [
    :values,
    :total,
    :has_more
  ]

  @type t :: %__MODULE__{
          values: list(String.t()),
          total: integer() | nil,
          has_more: boolean() | nil
        }

  @doc """
  Creates a new Completion struct.

  ## Parameters

  - `opts` - Keyword list of completion options:
    - `:values` (required) - List of completion suggestions
    - `:total` - Total number of possible completions
    - `:has_more` - Whether there are more completions available

  ## Examples

      iex> McpServer.Completion.new(values: ["Alice", "Bob"])
      %McpServer.Completion{values: ["Alice", "Bob"]}

      iex> McpServer.Completion.new(
      ...>   values: ["file1.txt", "file2.txt"],
      ...>   total: 50,
      ...>   has_more: true
      ...> )
      %McpServer.Completion{
        values: ["file1.txt", "file2.txt"],
        total: 50,
        has_more: true
      }

      iex> McpServer.Completion.new(values: [], total: 0, has_more: false)
      %McpServer.Completion{values: [], total: 0, has_more: false}
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      values: Keyword.fetch!(opts, :values),
      total: Keyword.get(opts, :total),
      has_more: Keyword.get(opts, :has_more)
    }
  end
end

defimpl Jason.Encoder, for: McpServer.Completion do
  def encode(value, opts) do
    map = %{
      "values" => value.values
    }

    map = maybe_put(map, "total", value.total)
    map = maybe_put(map, "hasMore", value.has_more)

    Jason.Encode.map(map, opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
