defmodule McpServer.Controller do
  @moduledoc """
  Helper functions for declaring data in controllers.

  Usually you would import this module in your controller modules:

      defmodule MyApp.MyController do
        import McpServer.Controller

        def read_resource(params) do
          %{
            "contents" => [
              content("file.txt", "file:///path/to/file.txt", mimeType: "text/plain", text: "File content")
            ],
            "messages" => [
              message("user", "text", "Hello!"),
              message("assistant", "text", "Hi there!")
            ],
            "completions" => [
              completion(["Alice", "Bob"], total: 10, has_more: true)
            ]
          }
        end
      end
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

  # Examples

      iex> content("main.rs", "file:///project/src/main.rs", mimeType: "plain/text", text: "<actual content of the file>...", title: "Main file of the code base")
      %{
        "name" => "main.rs",
        "uri" => "file:///project/src/main.rs",
        "mimeType" => "plain/text",
        "text" => "<actual content of the file>...",
        "title" => "Main file of the code base"
      }

      iex> content("image.png", "file:///tmp/image.png", mimeType: "image/png", blob: <<255, 216, 255>>)
      %{
        "name" => "image.png",
        "uri" => "file:///tmp/image.png",
        "mimeType" => "image/png",
        "blob" => "/9j/"  # base64-encoded
      }
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

  @doc """
  Creates a message for a prompt response.

  ## Parameters

  - `role` - The role of the message sender ("user", "assistant", "system")
  - `type` - The type of content ("text", "image", etc.)
  - `content` - The actual content of the message

  ## Examples

      iex> message("user", "text", "Hello world!")
      %{
        "role" => "user",
        "content" => %{
          "type" => "text",
          "text" => "Hello world!"
        }
      }
  """
  def message(role, type, content)
      when is_binary(role) and is_binary(type) and is_binary(content) do
    %{
      "role" => role,
      "content" => %{
        "type" => type,
        type => content
      }
    }
  end

  @doc """
  Creates a completion response for prompt argument completion.

  ## Parameters

  - `values` - A list of completion values
  - `opts` - Optional parameters:
    - `:total` - Total number of possible completions
    - `:has_more` - Whether there are more completions available

  ## Examples

      iex> completion(["Alice", "Bob", "Charlie"])
      %{
          "values" => ["Alice", "Bob", "Charlie"],
      }

      iex> completion(["Alice", "Bob"], total: 10, has_more: true)
      %{
          "values" => ["Alice", "Bob"],
          "total" => 10,
          "hasMore" => true
      }

      iex> completion(["Alice", "Bob"], total: 10, has_more: false)
      %{
          "values" => ["Alice", "Bob"],
          "total" => 10,
          "hasMore" => false
      }
  """
  def completion(values, opts \\ []) when is_list(values) do
    total = Keyword.get(opts, :total)
    has_more = Keyword.get(opts, :has_more)

    %{
      "values" => values,
      "total" => total,
      "hasMore" => has_more
    }
    |> Map.reject(fn {_, v} -> is_nil(v) end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
