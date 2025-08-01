defmodule McpServer.RouterTest do
  use ExUnit.Case, async: true

  # Mock controller for testing
  defmodule TestController do
    def echo(args) do
      Map.get(args, "message", "default")
    end

    def greet(args) do
      name = Map.get(args, "name", "World")
      "Hello, #{name}!"
    end

    def calculate(args) do
      a = Map.get(args, "a", 0)
      b = Map.get(args, "b", 0)
      a + b
    end
  end

  # Test module that uses the router
  defmodule TestRouter do
    use McpServer.Router

    tool "greet", "Greets a person", TestController, :greet do
      input_field("name", "The name to greet", :string, required: false)
      output_field("greeting", "The greeting message", :string)
    end

    tool "calculate", "Adds two numbers", TestController, :calculate do
      input_field("a", "First number", :integer, required: true)
      input_field("b", "Second number", :integer, required: true)
      output_field("result", "The sum of the numbers", :integer)
    end

    tool "echo", "Echoes back the input", TestController, :echo,
      title: "Echo",
      hints: [:read_only, :non_destructive, :idempotent, :closed_world] do
      input_field("message", "The message to echo", :string, required: true)
      output_field("response", "The echoed message", :string)
    end
  end

  describe "tools_list/0" do
    test "returns list of all defined tools" do
      tools = TestRouter.tools_list()

      assert length(tools) == 3

      tool_names = Enum.map(tools, & &1["name"])
      assert "echo" in tool_names
      assert "greet" in tool_names
      assert "calculate" in tool_names
    end

    test "each tool has correct structure" do
      tools = TestRouter.tools_list()
      echo_tool = Enum.find(tools, &(&1["name"] == "echo"))

      assert echo_tool["name"] == "echo"
      assert echo_tool["description"] == "Echoes back the input"
      # Note: The actual implementation returns JSON-formatted tools list
      # so we don't test internal structure like controller and function
      assert is_map(echo_tool["inputSchema"])
    end

    test "tool has correct input and output fields" do
      tools = TestRouter.tools_list()
      echo_tool = Enum.find(tools, &(&1["name"] == "echo"))

      # Check input schema structure
      input_schema = echo_tool["inputSchema"]
      assert input_schema["type"] == "object"
      assert Map.has_key?(input_schema["properties"], "message")

      message_field = input_schema["properties"]["message"]
      assert message_field["description"] == "The message to echo"
      assert message_field["type"] == "string"
      assert "message" in input_schema["required"]
    end
  end

  describe "tools_call/2" do
    test "successfully calls tool with valid arguments" do
      result = TestRouter.tools_call("echo", %{"message" => "Hello World"})
      assert result == "Hello World"
    end

    test "calls tool with optional arguments" do
      result = TestRouter.tools_call("greet", %{"name" => "Alice"})
      assert result == "Hello, Alice!"
    end

    test "calls tool without optional arguments" do
      result = TestRouter.tools_call("greet", %{})
      assert result == "Hello, World!"
    end

    test "calls tool with multiple required arguments" do
      result = TestRouter.tools_call("calculate", %{"a" => 5, "b" => 3})
      assert result == 8
    end

    test "raises error when tool not found" do
      assert_raise ArgumentError, "Tool 'nonexistent' not found", fn ->
        TestRouter.tools_call("nonexistent", %{})
      end
    end

    test "raises error when required arguments missing" do
      assert_raise ArgumentError,
                   ~r/Missing required arguments for tool 'echo': \["message"\]/,
                   fn ->
                     TestRouter.tools_call("echo", %{})
                   end
    end

    test "raises error when multiple required arguments missing" do
      assert_raise ArgumentError, ~r/Missing required arguments for tool 'calculate'/, fn ->
        TestRouter.tools_call("calculate", %{"a" => 5})
      end
    end
  end

  describe "tool macro validation" do
    test "raises error when duplicate tool is defined" do
      assert_raise CompileError, ~r/Tool "duplicate" is already defined/, fn ->
        defmodule DuplicateTool.TestController do
          def test(_args), do: "test"
        end

        defmodule DuplicateTool.Router do
          use McpServer.Router
          alias DuplicateTool.TestController

          tool "duplicate", "First tool", TestController, :test do
            input_field("param", "A parameter", :string, required: true)
          end

          tool "duplicate", "Second tool", TestController, :test do
            input_field("param", "A parameter", :string, required: true)
          end
        end
      end
    end

    test "raises error when duplicate input field is defined" do
      assert_raise SyntaxError, ~r/input_field "param" duplicated in tool "test"/, fn ->
        defmodule DuplicateField.TestController do
          def test(_args), do: "test"
        end

        defmodule DuplicateField.Router do
          use McpServer.Router
          alias DuplicateField.TestController

          tool "test", "Test tool", TestController, :test do
            input_field("param", "First param", :string, required: true)
            input_field("param", "Second param", :string, required: true)
          end
        end
      end
    end

    test "raises error when duplicate output field is defined" do
      assert_raise SyntaxError, ~r/output_field "result" duplicated in tool "test"/, fn ->
        defmodule DuplicateOutput.TestController do
          def test(_args), do: "test"
        end

        defmodule DuplicateOutput.Router do
          use McpServer.Router
          alias DuplicateOutput.TestController

          tool "test", "Test tool", TestController, :test do
            input_field("param", "A param", :string, required: true)
            output_field("result", "First result", :string)
            output_field("result", "Second result", :string)
          end
        end
      end
    end

    test "raises SyntaxError when unexpected statement is used in tool definition" do
      assert_raise SyntaxError, ~r/Unexpected statement in tool definition/, fn ->
        defmodule InvalidStatement.TestController do
          def test(_args), do: "test"
        end

        defmodule InvalidStatement.Router do
          use McpServer.Router
          alias InvalidStatement.TestController

          tool "test", "Test tool", TestController, :test do
            input_field("param", "A param", :string, required: true)
            # This should cause a CompileError since 'invalid_statement' is not recognized
            invalid_statement("something", "Invalid")
          end
        end
      end
    end
  end
end
