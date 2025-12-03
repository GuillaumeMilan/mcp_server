defmodule McpServer.SchemaTest do
  use ExUnit.Case, async: true

  alias McpServer.Schema

  describe "new/1" do
    test "creates a schema with required type" do
      schema = Schema.new(type: "string")
      assert schema.type == "string"
      assert schema.properties == nil
      assert schema.required == nil
      assert schema.items == nil
    end

    test "creates a string schema with enum" do
      schema =
        Schema.new(
          type: "string",
          enum: ["red", "green", "blue"]
        )

      assert schema.type == "string"
      assert schema.enum == ["red", "green", "blue"]
    end

    test "creates a schema with default value" do
      schema =
        Schema.new(
          type: "integer",
          default: 42
        )

      assert schema.type == "integer"
      assert schema.default == 42
    end

    test "creates a schema with description" do
      schema =
        Schema.new(
          type: "string",
          description: "A user's name"
        )

      assert schema.type == "string"
      assert schema.description == "A user's name"
    end

    test "creates an object schema with properties as Schema structs" do
      properties = %{
        "name" => Schema.new(type: "string", description: "User name"),
        "age" => Schema.new(type: "integer", description: "User age")
      }

      schema =
        Schema.new(
          type: "object",
          properties: properties,
          required: ["name"]
        )

      assert schema.type == "object"
      assert schema.properties == properties
      assert schema.required == ["name"]
    end

    test "creates an array schema with items" do
      items_schema = Schema.new(type: "string")

      schema =
        Schema.new(
          type: "array",
          items: items_schema
        )

      assert schema.type == "array"
      assert schema.items == items_schema
    end

    test "creates an array schema with object items" do
      items_properties = %{
        "id" => Schema.new(type: "integer"),
        "name" => Schema.new(type: "string")
      }

      items_schema =
        Schema.new(
          type: "object",
          properties: items_properties,
          required: ["id"]
        )

      schema =
        Schema.new(
          type: "array",
          items: items_schema
        )

      assert schema.type == "array"
      assert schema.items == items_schema
      assert schema.items.type == "object"
    end

    test "raises error when type is missing" do
      assert_raise KeyError, fn ->
        Schema.new([])
      end
    end
  end

  describe "Jason.Encoder" do
    test "encodes minimal schema" do
      schema = Schema.new(type: "string")
      json = Jason.encode!(schema)
      decoded = Jason.decode!(json)

      assert decoded == %{"type" => "string"}
    end

    test "encodes string schema with description and enum" do
      schema =
        Schema.new(
          type: "string",
          description: "A color",
          enum: ["red", "green", "blue"]
        )

      json = Jason.encode!(schema)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "string"
      assert decoded["description"] == "A color"
      assert decoded["enum"] == ["red", "green", "blue"]
    end

    test "encodes object schema with nested Schema properties" do
      properties = %{
        "name" => Schema.new(type: "string", description: "User name"),
        "age" => Schema.new(type: "integer", description: "User age")
      }

      schema =
        Schema.new(
          type: "object",
          properties: properties,
          required: ["name"],
          description: "User object"
        )

      json = Jason.encode!(schema)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "object"
      assert decoded["description"] == "User object"
      assert decoded["required"] == ["name"]
      assert decoded["properties"]["name"]["type"] == "string"
      assert decoded["properties"]["name"]["description"] == "User name"
      assert decoded["properties"]["age"]["type"] == "integer"
      assert decoded["properties"]["age"]["description"] == "User age"
    end

    test "encodes array schema with items" do
      items_schema = Schema.new(type: "string")

      schema =
        Schema.new(
          type: "array",
          items: items_schema
        )

      json = Jason.encode!(schema)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "array"
      assert decoded["items"]["type"] == "string"
    end

    test "encodes array of objects schema" do
      items_properties = %{
        "id" => Schema.new(type: "integer"),
        "name" => Schema.new(type: "string")
      }

      items_schema =
        Schema.new(
          type: "object",
          properties: items_properties,
          required: ["id"]
        )

      schema =
        Schema.new(
          type: "array",
          items: items_schema
        )

      json = Jason.encode!(schema)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "array"
      assert decoded["items"]["type"] == "object"
      assert decoded["items"]["required"] == ["id"]
      assert decoded["items"]["properties"]["id"]["type"] == "integer"
      assert decoded["items"]["properties"]["name"]["type"] == "string"
    end

    test "encodes schema with default value" do
      schema =
        Schema.new(
          type: "boolean",
          default: true
        )

      json = Jason.encode!(schema)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "boolean"
      assert decoded["default"] == true
    end

    test "omits nil fields from JSON" do
      schema = Schema.new(type: "string")
      json = Jason.encode!(schema)
      decoded = Jason.decode!(json)

      refute Map.has_key?(decoded, "properties")
      refute Map.has_key?(decoded, "required")
      refute Map.has_key?(decoded, "description")
      refute Map.has_key?(decoded, "enum")
      refute Map.has_key?(decoded, "default")
      refute Map.has_key?(decoded, "items")
    end

    test "complex nested schema example" do
      address_schema =
        Schema.new(
          type: "object",
          properties: %{
            "street" => Schema.new(type: "string"),
            "city" => Schema.new(type: "string"),
            "zip" => Schema.new(type: "string")
          },
          required: ["street", "city"]
        )

      user_schema =
        Schema.new(
          type: "object",
          properties: %{
            "name" => Schema.new(type: "string", description: "Full name"),
            "email" => Schema.new(type: "string"),
            "age" => Schema.new(type: "integer"),
            "address" => address_schema,
            "tags" => Schema.new(type: "array", items: Schema.new(type: "string"))
          },
          required: ["name", "email"]
        )

      json = Jason.encode!(user_schema)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "object"
      assert decoded["required"] == ["name", "email"]
      assert decoded["properties"]["name"]["type"] == "string"
      assert decoded["properties"]["address"]["type"] == "object"
      assert decoded["properties"]["address"]["required"] == ["street", "city"]
      assert decoded["properties"]["address"]["properties"]["street"]["type"] == "string"
      assert decoded["properties"]["tags"]["type"] == "array"
      assert decoded["properties"]["tags"]["items"]["type"] == "string"
    end
  end
end
