defmodule McpServer.Controller do
  @moduledoc """
  Helper functions for declaring data in controllers.

  Usually you would import this module in your controller modules:

      defmodule MyApp.MyController do
        import McpServer.Controller

        def read_resource(params) do
          McpServer.Resource.ReadResult.new(
            contents: [
              content("file.txt", "file:///path/to/file.txt", mimeType: "text/plain", text: "File content")
            ]
          )
        end

        def get_prompt(_conn, _args) do
          [
            message("user", "text", "Hello!"),
            message("assistant", "text", "Hi there!")
          ]
        end

        def complete_prompt(_conn, _arg, _prefix) do
          completion(["Alice", "Bob"], total: 10, has_more: true)
        end
      end
  """

  @doc """
  Creates a resource content item.

  Returns a `McpServer.Resource.Content` struct that can be used in read_resource responses.

  ## Parameters

  - `name` (string): the display name of the content (e.g. filename)
  - `uri` (string): the canonical URI of the content
  - `opts` (keyword list): optional keys include:
    - `:mimeType` - mime type string
    - `:text` - textual content
    - `:title` - title for the content
    - `:blob` - binary content; when present it's base64-encoded

  ## Examples

      iex> content("main.rs", "file:///project/src/main.rs", mimeType: "plain/text", text: "<actual content of the file>...", title: "Main file of the code base")
      %McpServer.Resource.Content{
        name: "main.rs",
        uri: "file:///project/src/main.rs",
        mime_type: "plain/text",
        text: "<actual content of the file>...",
        title: "Main file of the code base"
      }

      iex> content("image.png", "file:///tmp/image.png", mimeType: "image/png", blob: <<255, 216, 255>>)
      %McpServer.Resource.Content{
        name: "image.png",
        uri: "file:///tmp/image.png",
        mime_type: "image/png",
        blob: "/9j/"  # base64-encoded
      }
  """
  @spec content(String.t(), String.t(), keyword()) :: McpServer.Resource.Content.t()
  def content(name, uri, opts \\ []) when is_binary(name) and is_binary(uri) and is_list(opts) do
    mime_type = Keyword.get(opts, :mimeType)
    text = Keyword.get(opts, :text)
    title = Keyword.get(opts, :title)
    blob = Keyword.get(opts, :blob)

    # Base64 encode blob if provided
    encoded_blob =
      case blob do
        nil -> nil
        b when is_binary(b) -> Base.encode64(b)
        _ -> raise ArgumentError, ":blob option must be a binary"
      end

    McpServer.Resource.Content.new(
      name: name,
      uri: uri,
      mime_type: mime_type,
      text: text,
      title: title,
      blob: encoded_blob
    )
  end

  @doc """
  Creates a message for a prompt response.

  Returns a `McpServer.Prompt.Message` struct that can be used in get_prompt responses.

  ## Parameters

  - `role` - The role of the message sender ("user", "assistant", "system")
  - `type` - The type of content ("text", "image", etc.)
  - `content` - The actual content of the message

  ## Examples

      iex> message("user", "text", "Hello world!")
      %McpServer.Prompt.Message{
        role: "user",
        content: %McpServer.Prompt.MessageContent{
          type: "text",
          text: "Hello world!"
        }
      }
  """
  @spec message(String.t(), String.t(), String.t()) :: McpServer.Prompt.Message.t()
  def message(role, type, content)
      when is_binary(role) and is_binary(type) and is_binary(content) do
    McpServer.Prompt.Message.new(
      role: role,
      content: McpServer.Prompt.MessageContent.new(type: type, text: content)
    )
  end

  @doc """
  Creates a completion response for prompt argument or resource URI completion.

  Returns a `McpServer.Completion` struct that can be used in completion responses.

  ## Parameters

  - `values` - A list of completion values
  - `opts` - Optional parameters:
    - `:total` - Total number of possible completions
    - `:has_more` - Whether there are more completions available

  ## Examples

      iex> completion(["Alice", "Bob", "Charlie"])
      %McpServer.Completion{
          values: ["Alice", "Bob", "Charlie"]
      }

      iex> completion(["Alice", "Bob"], total: 10, has_more: true)
      %McpServer.Completion{
          values: ["Alice", "Bob"],
          total: 10,
          has_more: true
      }

      iex> completion(["Alice", "Bob"], total: 10, has_more: false)
      %McpServer.Completion{
          values: ["Alice", "Bob"],
          total: 10,
          has_more: false
      }
  """
  @spec completion(list(String.t()), keyword()) :: McpServer.Completion.t()
  def completion(values, opts \\ []) when is_list(values) do
    McpServer.Completion.new(
      values: values,
      total: Keyword.get(opts, :total),
      has_more: Keyword.get(opts, :has_more)
    )
  end
end
