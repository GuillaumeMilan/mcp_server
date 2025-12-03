defmodule McpServer.Schema do
  @moduledoc """
  Represents a JSON Schema object for validating tool parameters.

  This module provides a structured way to define JSON schemas that are used
  for input and output validation in MCP tools, following the MCP specification
  which implements recursive schema definitions.

  Schemas can be:
  - **StringSchema**: Simple string values with optional enum and description
  - **NumberSchema**: Numeric values (number or integer) with optional description
  - **BooleanSchema**: Boolean values with optional description
  - **ArraySchema**: Arrays with items that can be any schema type
  - **ObjectSchema**: Objects with typed properties, optional required fields, and description

  All schema types support optional description fields.

  ## Fields (shared across schema types)

  - `type` - The JSON type: "object", "string", "number", "integer", "boolean", "array"
  - `description` - Human-readable description (optional)
  - `properties` - Map of property schemas for object types (ObjectSchema only)
  - `required` - List of required property names (ObjectSchema only)
  - `items` - Schema for array items (ArraySchema only)
  - `enum` - List of allowed values (StringSchema only)
  - `default` - Default value if not provided (any type)

  ## Examples

      # StringSchema
      iex> string_schema = McpServer.Schema.new(
      ...>   type: "string",
      ...>   description: "A user name",
      ...>   enum: ["alice", "bob", "charlie"]
      ...> )
      %McpServer.Schema{type: "string", description: "A user name", enum: ["alice", "bob", "charlie"]}

      # NumberSchema
      iex> number_schema = McpServer.Schema.new(
      ...>   type: "number",
      ...>   description: "A decimal value"
      ...> )
      %McpServer.Schema{type: "number", description: "A decimal value"}

      # BooleanSchema
      iex> bool_schema = McpServer.Schema.new(
      ...>   type: "boolean",
      ...>   description: "A flag",
      ...>   default: true
      ...> )
      %McpServer.Schema{type: "boolean", description: "A flag", default: true}

      # ArraySchema
      iex> array_schema = McpServer.Schema.new(
      ...>   type: "array",
      ...>   items: McpServer.Schema.new(type: "string")
      ...> )
      %McpServer.Schema{
        type: "array",
        items: %McpServer.Schema{type: "string"}
      }

      # ObjectSchema (recursive)
      iex> object_schema = McpServer.Schema.new(
      ...>   type: "object",
      ...>   properties: %{
      ...>     "name" => McpServer.Schema.new(type: "string", description: "User name"),
      ...>     "age" => McpServer.Schema.new(type: "integer", description: "User age")
      ...>   },
      ...>   required: ["name"]
      ...> )
      %McpServer.Schema{
        type: "object",
        properties: %{
          "name" => %McpServer.Schema{type: "string", description: "User name"},
          "age" => %McpServer.Schema{type: "integer", description: "User age"}
        },
        required: ["name"]
      }
  """

  @enforce_keys [:type]
  defstruct [
    :type,
    :properties,
    :required,
    :description,
    :items,
    :enum,
    :default
  ]

  @type schema_type :: String.t()
  @type t :: %__MODULE__{
          type: schema_type(),
          properties: map() | nil,
          required: list(String.t()) | nil,
          description: String.t() | nil,
          items: t() | nil,
          enum: list() | nil,
          default: any() | nil
        }

  @doc """
  Creates a new Schema struct.

  Supports recursive schema definitions where properties and items can be nested schemas.

  ## Parameters

  - `opts` - Keyword list of schema options:
    - `:type` (required) - The JSON type ("object", "string", "number", "integer", "boolean", "array")
    - `:properties` - Map of property schemas (for object types, maps to McpServer.Schema.t())
    - `:required` - List of required property names (for object types)
    - `:description` - Human-readable description
    - `:items` - Schema for array items (for array types, must be McpServer.Schema.t())
    - `:enum` - List of allowed values (for string types)
    - `:default` - Default value

  ## Examples

      iex> McpServer.Schema.new(type: "string", description: "A name")
      %McpServer.Schema{type: "string", description: "A name"}

      iex> McpServer.Schema.new(
      ...>   type: "array",
      ...>   items: McpServer.Schema.new(type: "string")
      ...> )
      %McpServer.Schema{
        type: "array",
        items: %McpServer.Schema{type: "string"}
      }

      iex> McpServer.Schema.new(
      ...>   type: "object",
      ...>   properties: %{
      ...>     "name" => McpServer.Schema.new(type: "string", description: "User name")
      ...>   },
      ...>   required: ["name"]
      ...> )
      %McpServer.Schema{
        type: "object",
        properties: %{
          "name" => %McpServer.Schema{type: "string", description: "User name"}
        },
        required: ["name"]
      }
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      type: Keyword.fetch!(opts, :type),
      properties: Keyword.get(opts, :properties),
      required: Keyword.get(opts, :required),
      description: Keyword.get(opts, :description),
      items: Keyword.get(opts, :items),
      enum: Keyword.get(opts, :enum),
      default: Keyword.get(opts, :default)
    }
  end
end

defimpl Jason.Encoder, for: McpServer.Schema do
  def encode(value, opts) do
    map = %{
      "type" => value.type
    }

    map = maybe_put_description(map, value.description)
    map = maybe_put_properties(map, value.properties)
    map = maybe_put_required(map, value.required)
    map = maybe_put_items(map, value.items)
    map = maybe_put_enum(map, value.enum)
    map = maybe_put_default(map, value.default)

    Jason.Encode.map(map, opts)
  end

  # For properties, we need to recursively encode nested schemas
  defp maybe_put_properties(map, nil), do: map

  defp maybe_put_properties(map, properties) when is_map(properties) do
    encoded_properties =
      properties
      |> Enum.map(fn {key, schema} ->
        # If it's a Schema struct, Jason will encode it; if it's a plain map, use as-is
        {key, schema}
      end)
      |> Map.new()

    Map.put(map, "properties", encoded_properties)
  end

  # For items, recursively encode if it's a Schema
  defp maybe_put_items(map, nil), do: map
  defp maybe_put_items(map, items), do: Map.put(map, "items", items)

  defp maybe_put_description(map, nil), do: map
  defp maybe_put_description(map, description), do: Map.put(map, "description", description)

  defp maybe_put_required(map, nil), do: map
  defp maybe_put_required(map, required), do: Map.put(map, "required", required)

  defp maybe_put_enum(map, nil), do: map
  defp maybe_put_enum(map, enum), do: Map.put(map, "enum", enum)

  defp maybe_put_default(map, nil), do: map
  defp maybe_put_default(map, default), do: Map.put(map, "default", default)
end
