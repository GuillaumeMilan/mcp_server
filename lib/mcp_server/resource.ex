defmodule McpServer.Resource do
  @moduledoc """
  Represents a static resource definition.

  Resources are data sources that can be read by MCP clients. Static resources
  have fixed URIs without template variables.

  ## Fields

  - `name` - Unique resource identifier
  - `uri` - Static URI for the resource
  - `description` - Human-readable description (optional)
  - `mime_type` - MIME type of the resource (optional)
  - `title` - Display title (optional)

  ## Examples

      iex> resource = McpServer.Resource.new(
      ...>   name: "config",
      ...>   uri: "file:///app/config.json",
      ...>   description: "Application configuration",
      ...>   mime_type: "application/json"
      ...> )
      %McpServer.Resource{
        name: "config",
        uri: "file:///app/config.json",
        description: "Application configuration",
        mime_type: "application/json"
      }
  """

  @enforce_keys [:name, :uri]
  defstruct [
    :name,
    :uri,
    :description,
    :mime_type,
    :title
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          uri: String.t(),
          description: String.t() | nil,
          mime_type: String.t() | nil,
          title: String.t() | nil
        }

  @doc """
  Creates a new Resource struct.

  ## Parameters

  - `opts` - Keyword list of resource options:
    - `:name` (required) - Unique resource identifier
    - `:uri` (required) - Static URI
    - `:description` - Human-readable description
    - `:mime_type` - MIME type
    - `:title` - Display title

  ## Examples

      iex> McpServer.Resource.new(
      ...>   name: "readme",
      ...>   uri: "file:///README.md"
      ...> )
      %McpServer.Resource{name: "readme", uri: "file:///README.md"}

      iex> McpServer.Resource.new(
      ...>   name: "config",
      ...>   uri: "file:///app/config.json",
      ...>   description: "App config",
      ...>   mime_type: "application/json",
      ...>   title: "Configuration"
      ...> )
      %McpServer.Resource{
        name: "config",
        uri: "file:///app/config.json",
        description: "App config",
        mime_type: "application/json",
        title: "Configuration"
      }
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      uri: Keyword.fetch!(opts, :uri),
      description: Keyword.get(opts, :description),
      mime_type: Keyword.get(opts, :mime_type),
      title: Keyword.get(opts, :title)
    }
  end
end

defmodule McpServer.ResourceTemplate do
  @moduledoc """
  Represents a templated resource with URI variables.

  Resource templates allow dynamic resource URIs with variables like {id}.
  These variables can be completed using the completion callback.

  ## Fields

  - `name` - Unique resource identifier
  - `uri_template` - URI template with {variable} placeholders
  - `description` - Human-readable description (optional)
  - `mime_type` - MIME type of the resource (optional)
  - `title` - Display title (optional)

  ## Examples

      iex> template = McpServer.ResourceTemplate.new(
      ...>   name: "user",
      ...>   uri_template: "https://api.example.com/users/{id}",
      ...>   description: "User profile data",
      ...>   mime_type: "application/json"
      ...> )
      %McpServer.ResourceTemplate{
        name: "user",
        uri_template: "https://api.example.com/users/{id}",
        description: "User profile data",
        mime_type: "application/json"
      }
  """

  @enforce_keys [:name, :uri_template]
  defstruct [
    :name,
    :uri_template,
    :description,
    :mime_type,
    :title
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          uri_template: String.t(),
          description: String.t() | nil,
          mime_type: String.t() | nil,
          title: String.t() | nil
        }

  @doc """
  Creates a new ResourceTemplate struct.

  ## Parameters

  - `opts` - Keyword list of resource template options:
    - `:name` (required) - Unique resource identifier
    - `:uri_template` (required) - URI template with variables
    - `:description` - Human-readable description
    - `:mime_type` - MIME type
    - `:title` - Display title

  ## Examples

      iex> McpServer.ResourceTemplate.new(
      ...>   name: "user",
      ...>   uri_template: "https://api.example.com/users/{id}"
      ...> )
      %McpServer.ResourceTemplate{
        name: "user",
        uri_template: "https://api.example.com/users/{id}"
      }

      iex> McpServer.ResourceTemplate.new(
      ...>   name: "document",
      ...>   uri_template: "file:///docs/{category}/{id}.md",
      ...>   description: "Documentation files",
      ...>   mime_type: "text/markdown",
      ...>   title: "Docs"
      ...> )
      %McpServer.ResourceTemplate{
        name: "document",
        uri_template: "file:///docs/{category}/{id}.md",
        description: "Documentation files",
        mime_type: "text/markdown",
        title: "Docs"
      }
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      uri_template: Keyword.fetch!(opts, :uri_template),
      description: Keyword.get(opts, :description),
      mime_type: Keyword.get(opts, :mime_type),
      title: Keyword.get(opts, :title)
    }
  end
end

defmodule McpServer.Resource.Content do
  @moduledoc """
  Represents a single content item from a resource.

  Content items contain the actual data read from a resource, along with
  metadata. Content can be either textual or binary (base64-encoded blob).

  ## Fields

  - `name` - Display name (e.g., filename)
  - `uri` - Canonical URI of the content
  - `mime_type` - MIME type (optional)
  - `text` - Textual content (optional, mutually exclusive with blob)
  - `blob` - Base64-encoded binary content (optional, mutually exclusive with text)
  - `title` - Display title (optional)

  ## Examples

      iex> content = McpServer.Resource.Content.new(
      ...>   name: "example.txt",
      ...>   uri: "file:///path/to/example.txt",
      ...>   mime_type: "text/plain",
      ...>   text: "File content here..."
      ...> )
      %McpServer.Resource.Content{
        name: "example.txt",
        uri: "file:///path/to/example.txt",
        mime_type: "text/plain",
        text: "File content here..."
      }
  """

  @enforce_keys [:name, :uri]
  defstruct [
    :name,
    :uri,
    :mime_type,
    :text,
    :blob,
    :title
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          uri: String.t(),
          mime_type: String.t() | nil,
          text: String.t() | nil,
          blob: String.t() | nil,
          title: String.t() | nil
        }

  @doc """
  Creates a new Resource.Content struct.

  ## Parameters

  - `opts` - Keyword list of content options:
    - `:name` (required) - Display name
    - `:uri` (required) - Canonical URI
    - `:mime_type` - MIME type
    - `:text` - Textual content
    - `:blob` - Base64-encoded binary content
    - `:title` - Display title

  ## Examples

      iex> McpServer.Resource.Content.new(
      ...>   name: "config.json",
      ...>   uri: "file:///app/config.json",
      ...>   mime_type: "application/json",
      ...>   text: "{\\"setting\\": \\"value\\"}"
      ...> )
      %McpServer.Resource.Content{
        name: "config.json",
        uri: "file:///app/config.json",
        mime_type: "application/json",
        text: "{\\"setting\\": \\"value\\"}"
      }

      iex> McpServer.Resource.Content.new(
      ...>   name: "image.png",
      ...>   uri: "file:///images/logo.png",
      ...>   mime_type: "image/png",
      ...>   blob: "iVBORw0KGgo..."
      ...> )
      %McpServer.Resource.Content{
        name: "image.png",
        uri: "file:///images/logo.png",
        mime_type: "image/png",
        blob: "iVBORw0KGgo..."
      }
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      uri: Keyword.fetch!(opts, :uri),
      mime_type: Keyword.get(opts, :mime_type),
      text: Keyword.get(opts, :text),
      blob: Keyword.get(opts, :blob),
      title: Keyword.get(opts, :title)
    }
  end
end

defmodule McpServer.Resource.ReadResult do
  @moduledoc """
  Represents the response from reading a resource.

  A read result contains a list of content items that were retrieved
  from the resource.

  ## Fields

  - `contents` - List of Resource.Content structs

  ## Examples

      iex> result = McpServer.Resource.ReadResult.new(
      ...>   contents: [
      ...>     McpServer.Resource.Content.new(
      ...>       name: "file.txt",
      ...>       uri: "file:///file.txt",
      ...>       text: "Content"
      ...>     )
      ...>   ]
      ...> )
      %McpServer.Resource.ReadResult{
        contents: [%McpServer.Resource.Content{...}]
      }
  """

  @enforce_keys [:contents]
  defstruct [:contents]

  @type t :: %__MODULE__{
          contents: list(McpServer.Resource.Content.t())
        }

  @doc """
  Creates a new Resource.ReadResult struct.

  ## Parameters

  - `opts` - Keyword list of read result options:
    - `:contents` (required) - List of Content structs

  ## Examples

      iex> McpServer.Resource.ReadResult.new(contents: [])
      %McpServer.Resource.ReadResult{contents: []}

      iex> content = McpServer.Resource.Content.new(
      ...>   name: "example.txt",
      ...>   uri: "file:///example.txt",
      ...>   text: "Hello"
      ...> )
      iex> McpServer.Resource.ReadResult.new(contents: [content])
      %McpServer.Resource.ReadResult{contents: [%McpServer.Resource.Content{...}]}
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      contents: Keyword.fetch!(opts, :contents)
    }
  end
end

# Jason Encoders

defimpl Jason.Encoder, for: McpServer.Resource do
  def encode(value, opts) do
    map = %{
      "name" => value.name,
      "uri" => value.uri
    }

    map = maybe_put(map, "description", value.description)
    map = maybe_put(map, "mimeType", value.mime_type)
    map = maybe_put(map, "title", value.title)

    Jason.Encode.map(map, opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defimpl Jason.Encoder, for: McpServer.ResourceTemplate do
  def encode(value, opts) do
    map = %{
      "name" => value.name,
      "uriTemplate" => value.uri_template
    }

    map = maybe_put(map, "description", value.description)
    map = maybe_put(map, "mimeType", value.mime_type)
    map = maybe_put(map, "title", value.title)

    Jason.Encode.map(map, opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defimpl Jason.Encoder, for: McpServer.Resource.Content do
  def encode(value, opts) do
    map = %{
      "name" => value.name,
      "uri" => value.uri
    }

    map = maybe_put(map, "mimeType", value.mime_type)
    map = maybe_put(map, "text", value.text)
    map = maybe_put(map, "blob", value.blob)
    map = maybe_put(map, "title", value.title)

    Jason.Encode.map(map, opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defimpl Jason.Encoder, for: McpServer.Resource.ReadResult do
  def encode(value, opts) do
    map = %{
      "contents" => value.contents
    }

    Jason.Encode.map(map, opts)
  end
end
