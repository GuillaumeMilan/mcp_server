defmodule McpServer.ToolTest do
  use ExUnit.Case, async: true

  alias McpServer.Tool
  alias McpServer.Tool.Annotations

  describe "Tool.new/1" do
    test "creates a tool with required fields" do
      tool =
        Tool.new(
          name: "echo",
          description: "Echoes back the input",
          input_schema: %{"type" => "object"}
        )

      assert tool.name == "echo"
      assert tool.description == "Echoes back the input"
      assert tool.input_schema == %{"type" => "object"}
      assert tool.annotations == nil
      assert tool.callback == nil
    end

    test "creates a tool with annotations" do
      annotations = Annotations.new(title: "Echo Tool")

      tool =
        Tool.new(
          name: "echo",
          description: "Echoes back the input",
          input_schema: %{"type" => "object"},
          annotations: annotations
        )

      assert tool.annotations == annotations
    end

    test "creates a tool with callback information" do
      tool =
        Tool.new(
          name: "echo",
          description: "Echoes back the input",
          input_schema: %{"type" => "object"},
          callback: {MyController, :echo}
        )

      assert tool.callback == {MyController, :echo}
    end

    test "creates a tool with callback and annotations" do
      annotations = Annotations.new(title: "Echo Tool")

      tool =
        Tool.new(
          name: "echo",
          description: "Echoes back the input",
          input_schema: %{"type" => "object"},
          annotations: annotations,
          callback: {MyController, :echo}
        )

      assert tool.callback == {MyController, :echo}
      assert tool.annotations == annotations
    end

    test "raises error when required fields are missing" do
      assert_raise KeyError, fn ->
        Tool.new(name: "echo")
      end
    end
  end

  describe "Tool.Annotations.new/1" do
    test "creates annotations with default values" do
      annotations = Annotations.new()

      assert annotations.title == nil
      assert annotations.read_only_hint == false
      assert annotations.destructive_hint == true
      assert annotations.idempotent_hint == false
      assert annotations.open_world_hint == true
    end

    test "creates annotations with custom title" do
      annotations = Annotations.new(title: "My Tool")

      assert annotations.title == "My Tool"
    end

    test "creates annotations with custom hints" do
      annotations =
        Annotations.new(
          read_only_hint: true,
          destructive_hint: false,
          idempotent_hint: true,
          open_world_hint: false
        )

      assert annotations.read_only_hint == true
      assert annotations.destructive_hint == false
      assert annotations.idempotent_hint == true
      assert annotations.open_world_hint == false
    end
  end

  describe "Jason.Encoder for Tool" do
    test "encodes minimal tool" do
      tool =
        Tool.new(
          name: "echo",
          description: "Echoes back the input",
          input_schema: %{"type" => "object"}
        )

      json = Jason.encode!(tool)
      decoded = Jason.decode!(json)

      assert decoded["name"] == "echo"
      assert decoded["description"] == "Echoes back the input"
      assert decoded["inputSchema"] == %{"type" => "object"}
      refute Map.has_key?(decoded, "annotations")
      refute Map.has_key?(decoded, "callback")
    end

    test "encodes tool with annotations" do
      annotations = Annotations.new(title: "Echo Tool", read_only_hint: true)

      tool =
        Tool.new(
          name: "echo",
          description: "Echoes back the input",
          input_schema: %{"type" => "object"},
          annotations: annotations
        )

      json = Jason.encode!(tool)
      decoded = Jason.decode!(json)

      assert decoded["name"] == "echo"
      assert decoded["annotations"]["title"] == "Echo Tool"
      assert decoded["annotations"]["readOnlyHint"] == true
    end

    test "encodes tool with callback but does NOT include callback in JSON" do
      tool =
        Tool.new(
          name: "echo",
          description: "Echoes back the input",
          input_schema: %{"type" => "object"},
          callback: {MyController, :echo}
        )

      json = Jason.encode!(tool)
      decoded = Jason.decode!(json)

      # Verify callback is in the struct but NOT in JSON
      assert tool.callback == {MyController, :echo}
      refute Map.has_key?(decoded, "callback")
      assert decoded["name"] == "echo"
      assert decoded["description"] == "Echoes back the input"
    end

    test "encodes tool with callback and annotations but only includes annotations in JSON" do
      annotations = Annotations.new(title: "Calculator", idempotent_hint: true)

      tool =
        Tool.new(
          name: "calculate",
          description: "Performs calculations",
          input_schema: %{"type" => "object"},
          annotations: annotations,
          callback: {MathController, :calculate}
        )

      json = Jason.encode!(tool)
      decoded = Jason.decode!(json)

      # Verify callback is stored internally
      assert tool.callback == {MathController, :calculate}

      # Verify annotations appear in JSON
      assert decoded["annotations"]["title"] == "Calculator"
      assert decoded["annotations"]["idempotentHint"] == true

      # Verify callback is NOT in JSON
      refute Map.has_key?(decoded, "callback")
    end

    test "encodes tool with complex input schema" do
      input_schema = %{
        "type" => "object",
        "properties" => %{
          "message" => %{
            "type" => "string",
            "description" => "Message to echo"
          }
        },
        "required" => ["message"]
      }

      tool =
        Tool.new(
          name: "echo",
          description: "Echoes back the input",
          input_schema: input_schema
        )

      json = Jason.encode!(tool)
      decoded = Jason.decode!(json)

      assert decoded["inputSchema"]["type"] == "object"
      assert decoded["inputSchema"]["properties"]["message"]["type"] == "string"
      assert decoded["inputSchema"]["required"] == ["message"]
    end
  end

  describe "Jason.Encoder for Tool.Annotations" do
    test "encodes annotations with default values" do
      annotations = Annotations.new()

      json = Jason.encode!(annotations)
      decoded = Jason.decode!(json)

      assert decoded["readOnlyHint"] == false
      assert decoded["destructiveHint"] == true
      assert decoded["idempotentHint"] == false
      assert decoded["openWorldHint"] == true
      refute Map.has_key?(decoded, "title")
    end

    test "encodes annotations with title" do
      annotations = Annotations.new(title: "Calculator")

      json = Jason.encode!(annotations)
      decoded = Jason.decode!(json)

      assert decoded["title"] == "Calculator"
    end

    test "encodes annotations with custom hints" do
      annotations =
        Annotations.new(
          title: "Safe Tool",
          read_only_hint: true,
          destructive_hint: false,
          idempotent_hint: true,
          open_world_hint: false
        )

      json = Jason.encode!(annotations)
      decoded = Jason.decode!(json)

      assert decoded["title"] == "Safe Tool"
      assert decoded["readOnlyHint"] == true
      assert decoded["destructiveHint"] == false
      assert decoded["idempotentHint"] == true
      assert decoded["openWorldHint"] == false
    end
  end
end
