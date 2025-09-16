defmodule McpServer.RouterTest do
  use ExUnit.Case, async: true
  import McpServer.Prompt, only: [message: 3, completion: 2]

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

    # Prompt controller functions
    def get_greet_prompt(%{"user_name" => user_name}) do
      [
        message("user", "text", "Hello #{user_name}! Welcome to our MCP server. How can I assist you today?"),
        message("assistant", "text", "I'm here to help you with any questions or tasks you might have.")
      ]
    end

    def complete_greet_prompt("user_name", user_name_prefix) do
      names = ["Alice", "Bob", "Charlie", "David"]
      filtered_names = Enum.filter(names, &String.starts_with?(&1, user_name_prefix))
      completion(filtered_names, total: 100, has_more: true)
    end

    def get_system_prompt(_args) do
      [
        message("system", "text", "You are a helpful assistant."),
        message("user", "text", "Hello!")
      ]
    end

    def complete_system_prompt("mode", mode_prefix) do
      modes = ["debug", "production", "development"]
      filtered_modes = Enum.filter(modes, &String.starts_with?(&1, mode_prefix))
      completion(filtered_modes, [])
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

    prompt "greet", "A friendly greeting prompt that welcomes users" do
      argument("user_name", "The name of the user to greet", required: true)
      get TestController, :get_greet_prompt
      complete TestController, :complete_greet_prompt
    end

    prompt "system", "System configuration prompt" do
      argument("mode", "The system mode", required: false)
      get TestController, :get_system_prompt
      complete TestController, :complete_system_prompt
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
      assert {:error, message} = TestRouter.tools_call("echo", %{})
      assert message =~ "Missing required arguments for tool 'echo'"
    end

    test "raises error when multiple required arguments missing" do
      assert {:error, message} = TestRouter.tools_call("calculate", %{"a" => 5})
      assert message =~ "Missing required arguments for tool 'calculate'"
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

  # Test prompt functionality separately for now until we implement the macro
  describe "prompt helper functions" do
    test "message/3 creates proper message structure" do
      msg = message("user", "text", "Hello world!")

      assert msg == %{
        "role" => "user",
        "content" => %{
          "type" => "text",
          "text" => "Hello world!"
        }
      }
    end

    test "completion/2 creates proper completion structure with defaults" do
      comp = completion(["Alice", "Bob"], [])

      assert comp == %{
        "values" => ["Alice", "Bob"],
        "hasMore" => false
      }
    end

    test "completion/2 creates proper completion structure with options" do
      comp = completion(["Alice", "Bob"], total: 10, has_more: true)

      assert comp == %{
        "values" => ["Alice", "Bob"],
        "total" => 10,
        "hasMore" => true
      }
    end
  end

  describe "prompts_list/0" do
    test "returns list of all defined prompts" do
      prompts = TestRouter.prompts_list()

      assert length(prompts) == 2

      prompt_names = Enum.map(prompts, & &1["name"])
      assert "greet" in prompt_names
      assert "system" in prompt_names
    end

    test "each prompt has correct structure" do
      prompts = TestRouter.prompts_list()
      greet_prompt = Enum.find(prompts, &(&1["name"] == "greet"))

      assert greet_prompt["name"] == "greet"
      assert greet_prompt["description"] == "A friendly greeting prompt that welcomes users"
      assert is_list(greet_prompt["arguments"])
    end

    test "prompt has correct arguments" do
      prompts = TestRouter.prompts_list()
      greet_prompt = Enum.find(prompts, &(&1["name"] == "greet"))

      arguments = greet_prompt["arguments"]
      assert length(arguments) == 1

      user_name_arg = Enum.find(arguments, &(&1["name"] == "user_name"))
      assert user_name_arg["name"] == "user_name"
      assert user_name_arg["description"] == "The name of the user to greet"
      assert user_name_arg["required"] == true
    end
  end

  describe "prompts_get/2" do
    test "successfully gets prompt with valid arguments" do
      result = TestRouter.prompts_get("greet", %{"user_name" => "Alice"})

      assert is_list(result)
      assert length(result) == 2

      [first_message, second_message] = result
      assert first_message["role"] == "user"
      assert first_message["content"]["text"] =~ "Alice"
      assert second_message["role"] == "assistant"
    end

    test "raises error when prompt not found" do
      assert_raise ArgumentError, "Prompt 'nonexistent' not found", fn ->
        TestRouter.prompts_get("nonexistent", %{})
      end
    end

    test "raises error when required arguments missing" do
      assert {:error, message} = TestRouter.prompts_get("greet", %{})
      assert message =~ "Missing required arguments for prompt 'greet'"
    end
  end

  describe "prompts_complete/3" do
    test "successfully completes prompt argument" do
      result = TestRouter.prompts_complete("greet", "user_name", "A")

      assert result["values"] == ["Alice"]
      assert result["total"] == 100
      assert result["hasMore"] == true
    end

    test "raises error when prompt not found" do
      assert_raise ArgumentError, "Prompt 'nonexistent' not found", fn ->
        TestRouter.prompts_complete("nonexistent", "arg", "")
      end
    end

    test "raises error when argument not found" do
      assert_raise ArgumentError, "Argument 'nonexistent' not found for prompt 'greet'", fn ->
        TestRouter.prompts_complete("greet", "nonexistent", "")
      end
    end
  end

  describe "prompt macro validation" do
    test "raises error when duplicate prompt is defined" do
      assert_raise CompileError, ~r/Prompt "duplicate" is already defined/, fn ->
        defmodule DuplicatePrompt.TestController do
          def get_test(_args), do: []
          def complete_test(_arg, _prefix), do: completion([], [])
        end

        defmodule DuplicatePrompt.Router do
          use McpServer.Router
          alias DuplicatePrompt.TestController

          prompt "duplicate", "First prompt" do
            argument("param", "A parameter", required: true)
            get TestController, :get_test
            complete TestController, :complete_test
          end

          prompt "duplicate", "Second prompt" do
            argument("param", "A parameter", required: true)
            get TestController, :get_test
            complete TestController, :complete_test
          end
        end
      end
    end

    test "raises error when duplicate argument is defined" do
      assert_raise SyntaxError, ~r/argument "param" duplicated in prompt "test"/, fn ->
        defmodule DuplicateArgument.TestController do
          def get_test(_args), do: []
          def complete_test(_arg, _prefix), do: completion([], [])
        end

        defmodule DuplicateArgument.Router do
          use McpServer.Router
          alias DuplicateArgument.TestController

          prompt "test", "Test prompt" do
            argument("param", "First param", required: true)
            argument("param", "Second param", required: true)
            get TestController, :get_test
            complete TestController, :complete_test
          end
        end
      end
    end

    test "raises error when get function is not defined" do
      assert_raise CompileError, ~r/Function .* for prompt "test" .* is not exported/, fn ->
        defmodule MissingGet.TestController do
          def complete_test(_arg, _prefix), do: completion([], [])
        end

        defmodule MissingGet.Router do
          use McpServer.Router
          alias MissingGet.TestController

          prompt "test", "Test prompt" do
            argument("param", "A param", required: true)
            get TestController, :nonexistent_get
            complete TestController, :complete_test
          end
        end
      end
    end

    test "raises error when complete function is not defined" do
      assert_raise CompileError, ~r/Function .* for prompt "test" .* is not exported/, fn ->
        defmodule MissingComplete.TestController do
          def get_test(_args), do: []
        end

        defmodule MissingComplete.Router do
          use McpServer.Router
          alias MissingComplete.TestController

          prompt "test", "Test prompt" do
            argument("param", "A param", required: true)
            get TestController, :get_test
            complete TestController, :nonexistent_complete
          end
        end
      end
    end
  end
end
