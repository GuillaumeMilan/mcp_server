defmodule McpServer.SchemaTest do
  use ExUnit.Case, async: true

  alias McpServer.Schema

  describe "new/1" do
    test "creates a schema with required type" do
      schema = Schema.new(type: "string")
      assert schema.type == "string"
      assert schema.properties == nil
      assert schema.required == nil
    end

    test "creates an object schema with properties" do
      properties = %{
        "name" => %{"type" => "string"},
        "age" => %{"type" => "integer"}
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

    test "creates a schema with enum" do
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

    test "encodes object schema with properties" do
      properties = %{
        "name" => %{"type" => "string", "description" => "User name"},
        "age" => %{"type" => "integer"}
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
      assert decoded["properties"] == properties
      assert decoded["required"] == ["name"]
      assert decoded["description"] == "User object"
    end

    test "encodes schema with enum" do
      schema =
        Schema.new(
          type: "string",
          enum: ["option1", "option2", "option3"]
        )

      json = Jason.encode!(schema)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "string"
      assert decoded["enum"] == ["option1", "option2", "option3"]
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
    end
  end
end
