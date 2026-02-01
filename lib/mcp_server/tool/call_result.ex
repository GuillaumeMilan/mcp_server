defmodule McpServer.Tool.CallResult do
  @moduledoc """
  Extended tool call result supporting structured content for UI rendering.

  Controllers can return this struct instead of a plain content list to include
  `structured_content` (structured data optimized for UI rendering) alongside
  the standard `content` (text representation for model context).

  ## Fields

  - `content` (required) - List of content blocks (`McpServer.Tool.Content.Text`,
    `McpServer.Tool.Content.Image`, `McpServer.Tool.Content.Resource`).
    This is the text representation included in model context.
  - `structured_content` - Map of structured data optimized for UI rendering.
    Excluded from model context. Used by views to render rich interfaces.
  - `_meta` - Additional metadata (timestamps, source info). Not included
    in model context.

  ## Usage

  Return from a tool controller function:

      def get_weather(_conn, %{"location" => location}) do
        weather = fetch_weather(location)

        {:ok, McpServer.Tool.CallResult.new(
          content: [McpServer.Tool.Content.text("Weather in \#{location}: \#{weather.temp}°F")],
          structured_content: %{
            "temperature" => weather.temp,
            "unit" => "fahrenheit",
            "humidity" => weather.humidity,
            "forecast" => weather.forecast
          }
        )}
      end

  For backward compatibility, controllers can still return a plain content list:

      def echo(_conn, %{"message" => message}) do
        {:ok, [McpServer.Tool.Content.text(message)]}
      end
  """

  @enforce_keys [:content]
  defstruct [
    :content,
    :structured_content,
    :_meta
  ]

  @type t :: %__MODULE__{
          content: list(),
          structured_content: map() | nil,
          _meta: map() | nil
        }

  @doc """
  Creates a new CallResult struct.

  ## Parameters

  - `opts` - Keyword list of options:
    - `:content` (required) - List of content blocks
    - `:structured_content` - Structured data for UI rendering (optional)
    - `:_meta` - Additional metadata (optional)

  ## Examples

      iex> McpServer.Tool.CallResult.new(
      ...>   content: [McpServer.Tool.Content.text("hello")],
      ...>   structured_content: %{"greeting" => "hello"}
      ...> )
      %McpServer.Tool.CallResult{
        content: [%McpServer.Tool.Content.Text{text: "hello"}],
        structured_content: %{"greeting" => "hello"}
      }
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      content: Keyword.fetch!(opts, :content),
      structured_content: Keyword.get(opts, :structured_content),
      _meta: Keyword.get(opts, :_meta)
    }
  end
end

defimpl Jason.Encoder, for: McpServer.Tool.CallResult do
  def encode(value, opts) do
    map = %{"content" => value.content, "isError" => false}
    map = maybe_put(map, "structuredContent", value.structured_content)
    map = maybe_put(map, "_meta", value._meta)

    Jason.Encode.map(map, opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
