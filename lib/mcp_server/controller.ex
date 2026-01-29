defmodule McpServer.Controller do
  @moduledoc """
  Helper functions for declaring data in controllers.

  Usually you would import this module in your controller modules:

      defmodule MyApp.MyController do
        import McpServer.Controller
        alias McpServer.Tool.Content, as: ToolContent

        # Tool content helpers (use McpServer.Tool.Content)
        def search_tool(_conn, %{"query" => query}) do
          [
            ToolContent.text("Found 5 results for: \#{query}"),
            ToolContent.text("Result 1: ..."),
            ToolContent.text("Result 2: ...")
          ]
        end

        def generate_chart(_conn, %{"data" => data}) do
          chart_image = create_chart(data)
          [
            ToolContent.text("Chart generated successfully"),
            ToolContent.image(chart_image, "image/png")
          ]
        end

        def read_file(_conn, %{"path" => path}) do
          ToolContent.resource("file://\#{path}", text: File.read!(path), mimeType: "text/plain")
        end

        # Resource content helpers
        def read_resource(params) do
          McpServer.Resource.ReadResult.new(
            contents: [
              content("file.txt", "file:///path/to/file.txt", mimeType: "text/plain", text: "File content")
            ]
          )
        end

        # Prompt helpers
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

  @doc """
  Creates a text content item for tool responses.

  Deprecated: Use `McpServer.Tool.Content.text/1` instead.

  ## Examples

      iex> text_content("Hello, World!")
      %McpServer.Tool.Content.Text{text: "Hello, World!"}
  """
  @deprecated "Use McpServer.Tool.Content.text/1 instead"
  @spec text_content(String.t()) :: McpServer.Tool.Content.Text.t()
  def text_content(text) when is_binary(text) do
    McpServer.Tool.Content.text(text)
  end

  @doc """
  Creates an image content item for tool responses.

  Deprecated: Use `McpServer.Tool.Content.image/2` instead.

  ## Examples

      iex> image_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      iex> image_content(image_data, "image/png")
      %McpServer.Tool.Content.Image{data: <<137, 80, 78, 71, 13, 10, 26, 10>>, mime_type: "image/png"}
  """
  @deprecated "Use McpServer.Tool.Content.image/2 instead"
  @spec image_content(binary(), String.t()) :: McpServer.Tool.Content.Image.t()
  def image_content(data, mime_type) when is_binary(data) and is_binary(mime_type) do
    McpServer.Tool.Content.image(data, mime_type)
  end

  @doc """
  Creates an embedded resource content item for tool responses.

  Deprecated: Use `McpServer.Tool.Content.resource/2` instead.

  ## Examples

      iex> resource_content("file:///path/to/file.txt")
      %McpServer.Tool.Content.Resource{uri: "file:///path/to/file.txt", text: nil, blob: nil, mime_type: nil}

      iex> resource_content("file:///data.json", mimeType: "application/json", text: ~s({"key": "value"}))
      %McpServer.Tool.Content.Resource{
        uri: "file:///data.json",
        mime_type: "application/json",
        text: ~s({"key": "value"}),
        blob: nil
      }
  """
  @deprecated "Use McpServer.Tool.Content.resource/2 instead"
  @spec resource_content(String.t(), keyword()) :: McpServer.Tool.Content.Resource.t()
  def resource_content(uri, opts \\ []) when is_binary(uri) and is_list(opts) do
    McpServer.Tool.Content.resource(uri, opts)
  end
end
