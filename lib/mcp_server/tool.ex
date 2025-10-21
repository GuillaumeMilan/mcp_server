defmodule McpServer.Tool do
  @moduledoc """
  Represents a complete tool definition with metadata and schema.

  This module defines the structure for MCP tools, which are callable functions
  with input validation, output schemas, and behavioral hints.

  ## Fields

  - `name` - Unique tool identifier
  - `description` - Human-readable description
  - `input_schema` - JSON Schema for input validation (can be a map or McpServer.Schema struct)
  - `annotations` - Optional metadata including title and behavioral hints

  ## Examples

      iex> tool = McpServer.Tool.new(
      ...>   name: "calculator",
      ...>   description: "Performs arithmetic operations",
      ...>   input_schema: %{
      ...>     "type" => "object",
      ...>     "properties" => %{
      ...>       "operation" => %{"type" => "string"}
      ...>     }
      ...>   }
      ...> )
      %McpServer.Tool{
        name: "calculator",
        description: "Performs arithmetic operations",
        input_schema: %{...}
      }
  """

  @enforce_keys [:name, :description, :input_schema]
  defstruct [
    :name,
    :description,
    :input_schema,
    :annotations
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          input_schema: map() | McpServer.Schema.t(),
          annotations: McpServer.Tool.Annotations.t() | nil
        }

  @doc """
  Creates a new Tool struct.

  ## Parameters

  - `opts` - Keyword list of tool options:
    - `:name` (required) - Unique tool identifier
    - `:description` (required) - Human-readable description
    - `:input_schema` (required) - JSON Schema for input validation
    - `:annotations` - Optional Tool.Annotations struct

  ## Examples

      iex> McpServer.Tool.new(
      ...>   name: "echo",
      ...>   description: "Echoes back the input",
      ...>   input_schema: %{"type" => "object"}
      ...> )
      %McpServer.Tool{
        name: "echo",
        description: "Echoes back the input",
        input_schema: %{"type" => "object"}
      }

      iex> McpServer.Tool.new(
      ...>   name: "greet",
      ...>   description: "Greets a person",
      ...>   input_schema: McpServer.Schema.new(type: "object"),
      ...>   annotations: McpServer.Tool.Annotations.new(title: "Greeter")
      ...> )
      %McpServer.Tool{
        name: "greet",
        description: "Greets a person",
        annotations: %McpServer.Tool.Annotations{title: "Greeter"}
      }
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      description: Keyword.fetch!(opts, :description),
      input_schema: Keyword.fetch!(opts, :input_schema),
      annotations: Keyword.get(opts, :annotations)
    }
  end
end

defmodule McpServer.Tool.Annotations do
  @moduledoc """
  Represents behavioral hints and metadata for tools.

  Annotations provide additional information about tool behavior that helps
  clients make informed decisions about when and how to use the tool.

  ## Fields

  - `title` - Display title for the tool
  - `read_only_hint` - True if the tool doesn't modify state
  - `destructive_hint` - True if the tool may have side effects
  - `idempotent_hint` - True if repeated calls produce the same result
  - `open_world_hint` - True if the tool works with unbounded/external data

  ## Examples

      iex> annotations = McpServer.Tool.Annotations.new(
      ...>   title: "Calculator",
      ...>   read_only_hint: true,
      ...>   idempotent_hint: true
      ...> )
      %McpServer.Tool.Annotations{
        title: "Calculator",
        read_only_hint: true,
        idempotent_hint: true
      }
  """

  defstruct [
    :title,
    read_only_hint: false,
    destructive_hint: true,
    idempotent_hint: false,
    open_world_hint: true
  ]

  @type t :: %__MODULE__{
          title: String.t() | nil,
          read_only_hint: boolean(),
          destructive_hint: boolean(),
          idempotent_hint: boolean(),
          open_world_hint: boolean()
        }

  @doc """
  Creates a new Tool.Annotations struct.

  ## Parameters

  - `opts` - Keyword list of annotation options:
    - `:title` - Display title
    - `:read_only_hint` - Whether the tool is read-only (default: false)
    - `:destructive_hint` - Whether the tool may have side effects (default: true)
    - `:idempotent_hint` - Whether the tool is idempotent (default: false)
    - `:open_world_hint` - Whether the tool works with unbounded data (default: true)

  ## Examples

      iex> McpServer.Tool.Annotations.new(title: "Echo Tool")
      %McpServer.Tool.Annotations{title: "Echo Tool"}

      iex> McpServer.Tool.Annotations.new(
      ...>   read_only_hint: true,
      ...>   destructive_hint: false,
      ...>   idempotent_hint: true,
      ...>   open_world_hint: false
      ...> )
      %McpServer.Tool.Annotations{
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true,
        open_world_hint: false
      }
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      title: Keyword.get(opts, :title),
      read_only_hint: Keyword.get(opts, :read_only_hint, false),
      destructive_hint: Keyword.get(opts, :destructive_hint, true),
      idempotent_hint: Keyword.get(opts, :idempotent_hint, false),
      open_world_hint: Keyword.get(opts, :open_world_hint, true)
    }
  end
end

defimpl Jason.Encoder, for: McpServer.Tool do
  def encode(value, opts) do
    map = %{
      "name" => value.name,
      "description" => value.description,
      "inputSchema" => value.input_schema
    }

    map = maybe_put(map, "annotations", value.annotations)

    Jason.Encode.map(map, opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defimpl Jason.Encoder, for: McpServer.Tool.Annotations do
  def encode(value, opts) do
    map = %{
      "readOnlyHint" => value.read_only_hint,
      "destructiveHint" => value.destructive_hint,
      "idempotentHint" => value.idempotent_hint,
      "openWorldHint" => value.open_world_hint
    }

    map = maybe_put(map, "title", value.title)

    Jason.Encode.map(map, opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
