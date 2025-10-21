defmodule McpServer.Schema do
  @moduledoc """
  Represents a JSON Schema object for validating tool parameters.

  This module provides a structured way to define JSON schemas that are used
  for input and output validation in MCP tools. It supports standard JSON Schema
  properties and can be nested for complex object structures.

  ## Fields

  - `type` - The JSON type: "object", "string", "number", "integer", "boolean", "array", "null"
  - `properties` - Map of property definitions for object types
  - `required` - List of required property names
  - `description` - Human-readable description
  - `enum` - List of allowed values
  - `default` - Default value if not provided

  ## Examples

      iex> schema = McpServer.Schema.new(
      ...>   type: "object",
      ...>   properties: %{
      ...>     "name" => %{"type" => "string", "description" => "User name"},
      ...>     "age" => %{"type" => "integer", "description" => "User age"}
      ...>   },
      ...>   required: ["name"]
      ...> )
      %McpServer.Schema{
        type: "object",
        properties: %{
          "name" => %{"type" => "string", "description" => "User name"},
          "age" => %{"type" => "integer", "description" => "User age"}
        },
        required: ["name"]
      }

      iex> string_schema = McpServer.Schema.new(
      ...>   type: "string",
      ...>   description: "A simple string field",
      ...>   enum: ["option1", "option2", "option3"]
      ...> )
      %McpServer.Schema{
        type: "string",
        description: "A simple string field",
        enum: ["option1", "option2", "option3"]
      }
  """

  @enforce_keys [:type]
  defstruct [
    :type,
    :properties,
    :required,
    :description,
    :enum,
    :default
  ]

  @type t :: %__MODULE__{
          type: String.t(),
          properties: map() | nil,
          required: list(String.t()) | nil,
          description: String.t() | nil,
          enum: list() | nil,
          default: any() | nil
        }

  @doc """
  Creates a new Schema struct.

  ## Parameters

  - `opts` - Keyword list of schema options:
    - `:type` (required) - The JSON type
    - `:properties` - Map of property definitions (for object types)
    - `:required` - List of required property names
    - `:description` - Human-readable description
    - `:enum` - List of allowed values
    - `:default` - Default value

  ## Examples

      iex> McpServer.Schema.new(type: "string", description: "A name")
      %McpServer.Schema{type: "string", description: "A name"}

      iex> McpServer.Schema.new(
      ...>   type: "string",
      ...>   enum: ["red", "green", "blue"],
      ...>   default: "blue"
      ...> )
      %McpServer.Schema{
        type: "string",
        enum: ["red", "green", "blue"],
        default: "blue"
      }
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      type: Keyword.fetch!(opts, :type),
      properties: Keyword.get(opts, :properties),
      required: Keyword.get(opts, :required),
      description: Keyword.get(opts, :description),
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

    map = maybe_put(map, "properties", value.properties)
    map = maybe_put(map, "required", value.required)
    map = maybe_put(map, "description", value.description)
    map = maybe_put(map, "enum", value.enum)
    map = maybe_put(map, "default", value.default)

    Jason.Encode.map(map, opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
