defmodule McpServer.Resource do
  @moduledoc """
  Helper functions for declaring resource contents for MCP resources.

  Provides a `content/3` function to build the content maps used by
  resource controllers in tests and applications.

  Examples

      iex> McpServer.Resource.content("main.rs", "file:///project/src/main.rs", mimeType: "plain/text", text: "...", title: "Main file")
      %{
        "name" => "main.rs",
        "uri" => "file:///project/src/main.rs",
        "mimeType" => "plain/text",
        "text" => "...",
        "title" => "Main file"
      }

      iex> McpServer.Resource.content("image.png", "file:///tmp/image.png", mimeType: "image/png", blob: <<255,216,255>>)
      %{
        "name" => "image.png",
        "uri" => "file:///tmp/image.png",
        "mimeType" => "image/png",
        "blob" => "\/9j\/8A=="
      }
  """

  @doc """
  Build a resource content map.

  - `name` (string): the display name of the content (e.g. filename)
  - `uri` (string): the canonical URI of the content
  - `opts` (keyword list): optional keys include:
    - `:mimeType` - mime type string
    - `:text` - textual content
    - `:title` - title for the content
    - `:blob` - binary content; when present it's base64-encoded into the returned map

  The returned map uses string keys matching the tests' expectations.
  """
  @spec content(String.t(), String.t(), keyword()) :: map()
  def content(name, uri, opts \\ []) when is_binary(name) and is_binary(uri) and is_list(opts) do
    mime = Keyword.get(opts, :mimeType)
    text = Keyword.get(opts, :text)
    title = Keyword.get(opts, :title)
    blob = Keyword.get(opts, :blob)

    base = %{
      "name" => name,
      "uri" => uri
    }

    base = maybe_put(base, "mimeType", mime)
    base = maybe_put(base, "text", text)
    base = maybe_put(base, "title", title)

    base =
      case blob do
        nil -> base
        b when is_binary(b) -> Map.put(base, "blob", Base.encode64(b))
        _ -> raise ArgumentError, ":blob option must be a binary"
      end

    base
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
