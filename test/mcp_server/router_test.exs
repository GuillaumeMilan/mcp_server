defmodule McpServer.RouterTest do
  use ExUnit.Case, async: true
  import McpServer.Controller, only: [message: 3, completion: 2, content: 3]

  # Helper to create a mock connection
  defp mock_conn do
    %McpServer.Conn{session_id: "test-session-123", private: %{}}
  end

  # Mock controller for testing
  defmodule TestController do
    def echo(_conn, args) do
      Map.get(args, "message", "default")
    end

    def greet(_conn, args) do
      name = Map.get(args, "name", "World")
      "Hello, #{name}!"
    end

    def calculate(_conn, args) do
      a = Map.get(args, "a", 0)
      b = Map.get(args, "b", 0)
      a + b
    end

    # Prompt controller functions
    def get_greet_prompt(_conn, %{"user_name" => user_name}) do
      [
        message(
          "user",
          "text",
          "Hello #{user_name}! Welcome to our MCP server. How can I assist you today?"
        ),
        message(
          "assistant",
          "text",
          "I'm here to help you with any questions or tasks you might have."
        )
      ]
    end

    def complete_greet_prompt(_conn, "user_name", user_name_prefix) do
      names = ["Alice", "Bob", "Charlie", "David"]
      filtered_names = Enum.filter(names, &String.starts_with?(&1, user_name_prefix))
      completion(filtered_names, total: 100, has_more: true)
    end

    def get_system_prompt(_conn, _args) do
      [
        message("system", "text", "You are a helpful assistant."),
        message("user", "text", "Hello!")
      ]
    end

    def complete_system_prompt(_conn, "mode", mode_prefix) do
      modes = ["debug", "production", "development"]
      filtered_modes = Enum.filter(modes, &String.starts_with?(&1, mode_prefix))
      completion(filtered_modes, [])
    end
  end

  # Resource controller for testing
  defmodule TestResourceController do
    def read_user(_conn, %{"id" => id}) do
      McpServer.Resource.ReadResult.new(
        contents: [
          content(
            "User #{id}",
            "https://example.com/users/#{id}",
            mimeType: "application/json",
            text: "{\"id\": \"#{id}\", \"name\": \"User #{id}\"}",
            title: "User title #{id}"
          )
        ]
      )
    end

    def complete_user(_conn, "id", prefix) do
      ids = ["42", "43", "100"]
      filtered = Enum.filter(ids, &String.starts_with?(&1, prefix))
      completion(filtered, total: 100, has_more: false)
    end

    def read_static(_conn, _opts) do
      McpServer.Resource.ReadResult.new(
        contents: [
          content(
            "static.txt",
            "https://example.com/static",
            mimeType: "text/plain",
            text: "static content"
          )
        ]
      )
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
      get(TestController, :get_greet_prompt)
      complete(TestController, :complete_greet_prompt)
    end

    prompt "system", "System configuration prompt" do
      argument("mode", "The system mode", required: false)
      get(TestController, :get_system_prompt)
      complete(TestController, :complete_system_prompt)
    end

    # Define resources
    resource "user", "https://example.com/users/{id}" do
      description("User resource")
      mimeType("application/json")
      title("User title")
      read(TestResourceController, :read_user)
      complete(TestResourceController, :complete_user)
    end

    resource "static", "https://example.com/static" do
      description("Static resource")
      mimeType("text/plain")
      title("Static content")
      read(TestResourceController, :read_static)
    end
  end

  describe "list_tools/1" do
    test "returns list of all defined tools" do
      conn = mock_conn()
      assert {:ok, tools} = TestRouter.list_tools(conn)

      assert length(tools) == 3

      tool_names = Enum.map(tools, & &1.name)
      assert "echo" in tool_names
      assert "greet" in tool_names
      assert "calculate" in tool_names
    end

    test "each tool has correct structure" do
      conn = mock_conn()
      assert {:ok, tools} = TestRouter.list_tools(conn)
      echo_tool = Enum.find(tools, &(&1.name == "echo"))

      assert %McpServer.Tool{} = echo_tool
      assert echo_tool.name == "echo"
      assert echo_tool.description == "Echoes back the input"
      assert %McpServer.Schema{} = echo_tool.input_schema
    end

    test "tool has correct input and output fields" do
      conn = mock_conn()
      assert {:ok, tools} = TestRouter.list_tools(conn)
      echo_tool = Enum.find(tools, &(&1.name == "echo"))

      # Check input schema structure
      input_schema = echo_tool.input_schema
      assert input_schema.type == "object"
      assert Map.has_key?(input_schema.properties, "message")

      message_field = input_schema.properties["message"]
      assert message_field["description"] == "The message to echo"
      assert message_field["type"] == "string"
      assert "message" in input_schema.required
    end
  end

  describe "call_tool/3" do
    test "successfully calls tool with valid arguments" do
      conn = mock_conn()
      assert {:ok, result} = TestRouter.call_tool(conn, "echo", %{"message" => "Hello World"})
      assert result == "Hello World"
    end

    test "calls tool with optional arguments" do
      conn = mock_conn()
      assert {:ok, result} = TestRouter.call_tool(conn, "greet", %{"name" => "Alice"})
      assert result == "Hello, Alice!"
    end

    test "calls tool without optional arguments" do
      conn = mock_conn()
      assert {:ok, result} = TestRouter.call_tool(conn, "greet", %{})
      assert result == "Hello, World!"
    end

    test "calls tool with multiple required arguments" do
      conn = mock_conn()
      assert {:ok, result} = TestRouter.call_tool(conn, "calculate", %{"a" => 5, "b" => 3})
      assert result == 8
    end

    test "returns error when tool not found" do
      conn = mock_conn()

      assert {:error, message} = TestRouter.call_tool(conn, "nonexistent", %{})
      assert message == "Tool 'nonexistent' not found"
    end

    test "returns error when required arguments missing" do
      conn = mock_conn()
      assert {:error, message} = TestRouter.call_tool(conn, "echo", %{})
      assert message =~ "Missing required arguments for tool 'echo'"
    end

    test "returns error when multiple required arguments missing" do
      conn = mock_conn()
      assert {:error, message} = TestRouter.call_tool(conn, "calculate", %{"a" => 5})
      assert message =~ "Missing required arguments for tool 'calculate'"
    end
  end

  describe "tool macro validation" do
    test "raises error when duplicate tool is defined" do
      assert_raise CompileError, ~r/Tool "duplicate" is already defined/, fn ->
        defmodule DuplicateTool.TestController do
          def test(_conn, _args), do: "test"
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
          def test(_conn, _args), do: "test"
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
          def test(_conn, _args), do: "test"
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
          def test(_conn, _args), do: "test"
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

  describe "prompts_list/1" do
    test "returns list of all defined prompts" do
      conn = mock_conn()
      assert {:ok, prompts} = TestRouter.prompts_list(conn)

      assert length(prompts) == 2

      prompt_names = Enum.map(prompts, & &1.name)
      assert "greet" in prompt_names
      assert "system" in prompt_names
    end

    test "each prompt has correct structure" do
      conn = mock_conn()
      assert {:ok, prompts} = TestRouter.prompts_list(conn)
      greet_prompt = Enum.find(prompts, &(&1.name == "greet"))

      assert %McpServer.Prompt{} = greet_prompt
      assert greet_prompt.name == "greet"
      assert greet_prompt.description == "A friendly greeting prompt that welcomes users"
      assert is_list(greet_prompt.arguments)
    end

    test "prompt has correct arguments" do
      conn = mock_conn()
      assert {:ok, prompts} = TestRouter.prompts_list(conn)
      greet_prompt = Enum.find(prompts, &(&1.name == "greet"))

      arguments = greet_prompt.arguments
      assert length(arguments) == 1

      user_name_arg = Enum.find(arguments, &(&1.name == "user_name"))
      assert %McpServer.Prompt.Argument{} = user_name_arg
      assert user_name_arg.name == "user_name"
      assert user_name_arg.description == "The name of the user to greet"
      assert user_name_arg.required == true
    end
  end

  describe "get_prompt/3" do
    test "successfully gets prompt with valid arguments" do
      conn = mock_conn()
      assert {:ok, result} = TestRouter.get_prompt(conn, "greet", %{"user_name" => "Alice"})

      assert is_list(result)
      assert length(result) == 2

      [first_message, second_message] = result
      assert %McpServer.Prompt.Message{} = first_message
      assert first_message.role == "user"
      assert first_message.content.text =~ "Alice"
      assert %McpServer.Prompt.Message{} = second_message
      assert second_message.role == "assistant"

      # Verify JSON encoding works correctly
      json = Jason.encode!(result)
      decoded = Jason.decode!(json)
      assert is_list(decoded)
      assert hd(decoded)["role"] == "user"
      assert hd(decoded)["content"]["text"] =~ "Alice"
    end

    test "returns error when prompt not found" do
      conn = mock_conn()

      assert {:error, message} = TestRouter.get_prompt(conn, "nonexistent", %{})
      assert message == "Prompt 'nonexistent' not found"
    end

    test "returns error when required arguments missing" do
      conn = mock_conn()
      assert {:error, message} = TestRouter.get_prompt(conn, "greet", %{})
      assert message =~ "Missing required arguments for prompt 'greet'"
    end
  end

  describe "complete_prompt/4" do
    test "successfully completes prompt argument" do
      conn = mock_conn()
      assert {:ok, result} = TestRouter.complete_prompt(conn, "greet", "user_name", "A")

      # Result is now a Completion struct
      assert %McpServer.Completion{} = result
      assert result.values == ["Alice"]
      assert result.total == 100
      assert result.has_more == true

      # Verify JSON encoding works correctly
      json = Jason.encode!(result)
      decoded = Jason.decode!(json)
      assert decoded["values"] == ["Alice"]
      assert decoded["total"] == 100
      assert decoded["hasMore"] == true
    end

    test "returns error when prompt not found" do
      conn = mock_conn()

      assert {:error, message} = TestRouter.complete_prompt(conn, "nonexistent", "arg", "")
      assert message == "Prompt 'nonexistent' not found"
    end

    test "returns error when argument not found" do
      conn = mock_conn()

      assert {:error, message} = TestRouter.complete_prompt(conn, "greet", "nonexistent", "")
      assert message == "Argument 'nonexistent' not found for prompt 'greet'"
    end
  end

  describe "resources_list/1 and read_resource/3" do
    test "resources_list returns defined resources" do
      conn = mock_conn()
      assert {:ok, static_resources} = TestRouter.list_resources(conn)
      static_names = Enum.map(static_resources, & &1.name)
      static_titles = Enum.map(static_resources, & &1.title)
      static_descriptions = Enum.map(static_resources, & &1.description)
      static_mime_types = Enum.map(static_resources, & &1.mime_type)

      assert "static" in static_names
      assert "Static content" in static_titles
      assert "Static resource" in static_descriptions
      assert "text/plain" in static_mime_types

      assert {:ok, template_resources} = TestRouter.list_templates_resource(conn)
      template_names = Enum.map(template_resources, & &1.name)
      templates_titles = Enum.map(template_resources, & &1.title)
      templates_descriptions = Enum.map(template_resources, & &1.description)
      templates_mime_types = Enum.map(template_resources, & &1.mime_type)

      assert "user" in template_names
      assert "User title" in templates_titles
      assert "User resource" in templates_descriptions
      assert "application/json" in templates_mime_types
    end

    test "read_resource delegates to controller and returns contents" do
      conn = mock_conn()
      assert {:ok, result} = TestRouter.read_resource(conn, "user", %{"id" => "42"})

      # Result is now a ReadResult struct
      assert %McpServer.Resource.ReadResult{} = result
      assert is_list(result.contents)
      assert length(result.contents) == 1

      content = hd(result.contents)
      assert %McpServer.Resource.Content{} = content
      assert content.uri == "https://example.com/users/42"
      assert content.mime_type == "application/json"
      assert content.text == "{\"id\": \"42\", \"name\": \"User 42\"}"
      assert content.title == "User title 42"
      assert content.name == "User 42"

      # Verify JSON encoding works correctly
      json = Jason.encode!(result)
      decoded = Jason.decode!(json)
      assert decoded["contents"]
      decoded_content = hd(decoded["contents"])
      assert decoded_content["uri"] == "https://example.com/users/42"
      assert decoded_content["mimeType"] == "application/json"
    end

    test "read_resource returns error for unknown resource" do
      conn = mock_conn()

      assert {:error, message} = TestRouter.read_resource(conn, "unknown", %{})
      assert message == "Resource 'unknown' not found"
    end

    test "complete_resource delegates to controller complete function" do
      conn = mock_conn()
      assert {:ok, result} = TestRouter.complete_resource(conn, "user", "id", "4")

      # Result is now a Completion struct
      assert %McpServer.Completion{} = result
      assert result.values == ["42", "43"] or result.values == ["42"]
      assert result.total == 100
      assert result.has_more == false

      # Verify JSON encoding works correctly
      json = Jason.encode!(result)
      decoded = Jason.decode!(json)
      assert decoded["values"]
      assert decoded["total"] == 100
      assert decoded["hasMore"] == false
    end
  end

  describe "prompt macro validation" do
    test "raises error when duplicate prompt is defined" do
      assert_raise CompileError, ~r/Prompt "duplicate" is already defined/, fn ->
        defmodule DuplicatePrompt.TestController do
          def get_test(_conn, _args), do: []
          def complete_test(_conn, _arg, _prefix), do: completion([], [])
        end

        defmodule DuplicatePrompt.Router do
          use McpServer.Router
          alias DuplicatePrompt.TestController

          prompt "duplicate", "First prompt" do
            argument("param", "A parameter", required: true)
            get(TestController, :get_test)
            complete(TestController, :complete_test)
          end

          prompt "duplicate", "Second prompt" do
            argument("param", "A parameter", required: true)
            get(TestController, :get_test)
            complete(TestController, :complete_test)
          end
        end
      end
    end

    test "raises error when duplicate argument is defined" do
      assert_raise SyntaxError, ~r/argument "param" duplicated in prompt "test"/, fn ->
        defmodule DuplicateArgument.TestController do
          def get_test(_conn, _args), do: []
          def complete_test(_conn, _arg, _prefix), do: completion([], [])
        end

        defmodule DuplicateArgument.Router do
          use McpServer.Router
          alias DuplicateArgument.TestController

          prompt "test", "Test prompt" do
            argument("param", "First param", required: true)
            argument("param", "Second param", required: true)
            get(TestController, :get_test)
            complete(TestController, :complete_test)
          end
        end
      end
    end

    test "raises error when get function is not defined" do
      assert_raise CompileError, ~r/Function .* for prompt "test" .* is not exported/, fn ->
        defmodule MissingGet.TestController do
          def complete_test(_conn, _arg, _prefix), do: completion([], [])
        end

        defmodule MissingGet.Router do
          use McpServer.Router
          alias MissingGet.TestController

          prompt "test", "Test prompt" do
            argument("param", "A param", required: true)
            get(TestController, :nonexistent_get)
            complete(TestController, :complete_test)
          end
        end
      end
    end

    test "raises error when complete function is not defined" do
      assert_raise CompileError, ~r/Function .* for prompt "test" .* is not exported/, fn ->
        defmodule MissingComplete.TestController do
          def get_test(_conn, _args), do: []
        end

        defmodule MissingComplete.Router do
          use McpServer.Router
          alias MissingComplete.TestController

          prompt "test", "Test prompt" do
            argument("param", "A param", required: true)
            get(TestController, :get_test)
            complete(TestController, :nonexistent_complete)
          end
        end
      end
    end
  end

  describe "empty router validation" do
    test "raises error when no tools or prompts are defined" do
      assert_raise CompileError, ~r/No tools or prompts defined/, fn ->
        defmodule EmptyRouter do
          use McpServer.Router
          # No tools or prompts defined - should raise CompileError
        end
      end
    end
  end

  describe "router with only tools (no prompts)" do
    defmodule OnlyToolsController do
      def echo(_conn, args) do
        Map.get(args, "message", "default")
      end
    end

    defmodule OnlyToolsRouter do
      use McpServer.Router

      tool "echo", "Echoes back the input", OnlyToolsController, :echo do
        input_field("message", "The message to echo", :string, required: true)
        output_field("response", "The echoed message", :string)
      end
    end

    test "compiles successfully with only tools defined" do
      # If this test runs, it means the module compiled successfully
      conn = mock_conn()
      assert {:ok, tools} = OnlyToolsRouter.list_tools(conn)
      assert length(tools) == 1
    end

    test "call_tool works correctly" do
      conn = mock_conn()
      assert {:ok, result} = OnlyToolsRouter.call_tool(conn, "echo", %{"message" => "Hello"})
      assert result == "Hello"
    end

    test "get_prompt returns error for unknown prompt" do
      conn = mock_conn()

      assert {:error, message} = OnlyToolsRouter.get_prompt(conn, "unknown", %{})
      assert message == "Prompt 'unknown' not found"
    end

    test "complete_prompt returns error for unknown prompt" do
      conn = mock_conn()

      assert {:error, message} = OnlyToolsRouter.complete_prompt(conn, "unknown", "arg", "prefix")
      assert message == "Prompt 'unknown' not found"
    end

    test "prompts_list returns empty list" do
      conn = mock_conn()
      assert {:ok, prompts} = OnlyToolsRouter.prompts_list(conn)
      assert prompts == []
    end
  end

  describe "router with only prompts (no tools)" do
    defmodule OnlyPromptsController do
      def get_greet_prompt(_conn, %{"user_name" => user_name}) do
        [
          message("user", "text", "Hello #{user_name}!")
        ]
      end

      def complete_greet_prompt(_conn, "user_name", user_name_prefix) do
        names = ["Alice", "Bob", "Charlie"]
        filtered_names = Enum.filter(names, &String.starts_with?(&1, user_name_prefix))

        completion(filtered_names, has_more: false)
      end
    end

    defmodule OnlyPromptsRouter do
      use McpServer.Router

      prompt "greet", "A friendly greeting prompt" do
        argument("user_name", "The name of the user to greet", required: true)
        get(OnlyPromptsController, :get_greet_prompt)
        complete(OnlyPromptsController, :complete_greet_prompt)
      end
    end

    test "compiles successfully with only prompts defined" do
      # If this test runs, it means the module compiled successfully
      conn = mock_conn()
      assert {:ok, prompts} = OnlyPromptsRouter.prompts_list(conn)
      assert length(prompts) == 1
    end

    test "get_prompt works correctly" do
      conn = mock_conn()

      assert {:ok, result} =
               OnlyPromptsRouter.get_prompt(conn, "greet", %{"user_name" => "Alice"})

      assert is_list(result)
      assert length(result) == 1
    end

    test "complete_prompt works correctly" do
      conn = mock_conn()
      assert {:ok, result} = OnlyPromptsRouter.complete_prompt(conn, "greet", "user_name", "A")
      assert %McpServer.Completion{} = result
      assert result.values == ["Alice"]
    end

    test "call_tool returns error for unknown tool" do
      conn = mock_conn()

      assert {:error, message} = OnlyPromptsRouter.call_tool(conn, "unknown", %{})
      assert message == "Tool 'unknown' not found"
    end

    test "list_tools returns empty list" do
      conn = mock_conn()
      assert {:ok, tools} = OnlyPromptsRouter.list_tools(conn)
      assert tools == []
    end
  end

  describe "nested structures - objects" do
    defmodule NestedController do
      def create_user(_conn, %{"user" => user_data}) do
        {:ok, %{"id" => "user_123", "data" => user_data}}
      end

      def get_config(_conn, %{"settings" => _settings}) do
        {:ok, %{"status" => "configured"}}
      end
    end

    defmodule NestedObjectRouter do
      use McpServer.Router

      tool "create_user", "Creates a user with nested data", NestedController, :create_user do
        input_field("user", "User data", :object, required: true) do
          field("name", "Full name", :string, required: true)
          field("email", "Email address", :string, required: true)
          field("age", "Age in years", :integer)

          field("address", "Mailing address", :object, required: true) do
            field("street", "Street address", :string)
            field("city", "City name", :string, required: true)
            field("country", "Country code", :string, required: true)
            field("postal_code", "Postal code", :string)
          end

          field("preferences", "User preferences", :object) do
            field("theme", "UI theme", :string, enum: ["light", "dark"], default: "light")
            field("notifications", "Enable notifications", :boolean, default: true)
          end
        end

        output_field("result", "Creation result", :object) do
          field("id", "User ID", :string)
          field("created", "Was created", :boolean)
        end
      end

      tool "configure", "Configure settings", NestedController, :get_config do
        input_field("settings", "Settings object", :object) do
          field("database", "Database settings", :object) do
            field("host", "Database host", :string, required: true)
            field("port", "Database port", :integer, default: 5432)
          end
        end
      end
    end

    test "generates correct nested object schema" do
      conn = mock_conn()
      assert {:ok, tools} = NestedObjectRouter.list_tools(conn)

      create_user_tool = Enum.find(tools, &(&1.name == "create_user"))
      assert create_user_tool != nil

      input_schema = create_user_tool.input_schema
      assert input_schema.type == "object"
      assert "user" in input_schema.required

      user_field = input_schema.properties["user"]
      assert user_field["type"] == "object"
      assert user_field["description"] == "User data"

      # Check nested properties
      assert is_map(user_field["properties"])
      assert Map.has_key?(user_field["properties"], "name")
      assert Map.has_key?(user_field["properties"], "email")
      assert Map.has_key?(user_field["properties"], "address")

      # Check required fields in nested object
      assert "name" in user_field["required"]
      assert "email" in user_field["required"]
      assert "address" in user_field["required"]

      # Check deeply nested address object
      address_field = user_field["properties"]["address"]
      assert address_field["type"] == "object"
      assert is_map(address_field["properties"])
      assert Map.has_key?(address_field["properties"], "city")
      assert Map.has_key?(address_field["properties"], "country")
      assert "city" in address_field["required"]
      assert "country" in address_field["required"]

      # Check preferences with enum and default
      preferences_field = user_field["properties"]["preferences"]
      assert preferences_field["type"] == "object"
      theme_field = preferences_field["properties"]["theme"]
      assert theme_field["enum"] == ["light", "dark"]
      assert theme_field["default"] == "light"
    end

    test "calls tool with nested data successfully" do
      conn = mock_conn()

      args = %{
        "user" => %{
          "name" => "John Doe",
          "email" => "john@example.com",
          "age" => 30,
          "address" => %{
            "city" => "New York",
            "country" => "US"
          }
        }
      }

      assert {:ok, result} = NestedObjectRouter.call_tool(conn, "create_user", args)
      assert result["id"] == "user_123"
      assert result["data"]["name"] == "John Doe"
    end

    test "multi-level nesting works correctly" do
      conn = mock_conn()
      assert {:ok, tools} = NestedObjectRouter.list_tools(conn)

      configure_tool = Enum.find(tools, &(&1.name == "configure"))
      input_schema = configure_tool.input_schema

      settings_field = input_schema.properties["settings"]
      database_field = settings_field["properties"]["database"]

      assert database_field["type"] == "object"
      assert Map.has_key?(database_field["properties"], "host")
      assert Map.has_key?(database_field["properties"], "port")
      assert "host" in database_field["required"]

      port_field = database_field["properties"]["port"]
      assert port_field["default"] == 5432
    end
  end

  describe "nested structures - arrays" do
    defmodule ArrayController do
      def process_tags(_conn, %{"tags" => tags}) do
        {:ok, %{"count" => length(tags)}}
      end

      def batch_create(_conn, %{"users" => users}) do
        {:ok, %{"created" => length(users)}}
      end

      def create_project(_conn, %{"project" => _project}) do
        {:ok, %{"project_id" => "proj_123"}}
      end
    end

    defmodule NestedArrayRouter do
      use McpServer.Router

      # Simple array with primitive items
      tool "process_tags", "Process tags", ArrayController, :process_tags do
        input_field("tags", "List of tags", :array, required: true, items: :string)
        input_field("scores", "Score values", :array, items: :number)
      end

      # Array with complex object items
      tool "batch_create", "Batch create users", ArrayController, :batch_create do
        input_field("users", "List of users", :array, required: true) do
          items :object do
            field("name", "User name", :string, required: true)
            field("email", "Email", :string, required: true)
            field("roles", "User roles", :array, items: :string)
          end
        end
      end

      # Complex nested structure
      tool "create_project", "Creates a project", ArrayController, :create_project do
        input_field("project", "Project data", :object, required: true) do
          field("name", "Project name", :string, required: true)

          field("team", "Team members", :array) do
            items :object do
              field("user_id", "User ID", :string, required: true)
              field("role", "Role", :string, enum: ["admin", "developer", "viewer"])
              field("permissions", "Permissions", :array, items: :string)
            end
          end

          field("metadata", "Metadata", :object) do
            field("tags", "Tags", :array, items: :string)
          end
        end
      end
    end

    test "generates correct schema for simple array items" do
      conn = mock_conn()
      assert {:ok, tools} = NestedArrayRouter.list_tools(conn)

      process_tool = Enum.find(tools, &(&1.name == "process_tags"))
      input_schema = process_tool.input_schema

      tags_field = input_schema.properties["tags"]
      assert tags_field["type"] == "array"
      assert tags_field["items"]["type"] == "string"

      scores_field = input_schema.properties["scores"]
      assert scores_field["type"] == "array"
      assert scores_field["items"]["type"] == "number"
    end

    test "generates correct schema for array with object items" do
      conn = mock_conn()
      assert {:ok, tools} = NestedArrayRouter.list_tools(conn)

      batch_tool = Enum.find(tools, &(&1.name == "batch_create"))
      input_schema = batch_tool.input_schema

      users_field = input_schema.properties["users"]
      assert users_field["type"] == "array"

      items_schema = users_field["items"]
      assert items_schema["type"] == "object"
      assert Map.has_key?(items_schema["properties"], "name")
      assert Map.has_key?(items_schema["properties"], "email")
      assert Map.has_key?(items_schema["properties"], "roles")

      assert "name" in items_schema["required"]
      assert "email" in items_schema["required"]

      # Check nested array in items
      roles_field = items_schema["properties"]["roles"]
      assert roles_field["type"] == "array"
      assert roles_field["items"]["type"] == "string"
    end

    test "calls tool with array data successfully" do
      conn = mock_conn()

      args = %{
        "tags" => ["elixir", "mcp", "server"]
      }

      assert {:ok, result} = NestedArrayRouter.call_tool(conn, "process_tags", args)
      assert result["count"] == 3
    end

    test "calls tool with complex array items" do
      conn = mock_conn()

      args = %{
        "users" => [
          %{"name" => "Alice", "email" => "alice@example.com", "roles" => ["admin"]},
          %{"name" => "Bob", "email" => "bob@example.com", "roles" => ["developer", "viewer"]}
        ]
      }

      assert {:ok, result} = NestedArrayRouter.call_tool(conn, "batch_create", args)
      assert result["created"] == 2
    end

    test "complex nested structure with arrays and objects" do
      conn = mock_conn()
      assert {:ok, tools} = NestedArrayRouter.list_tools(conn)

      project_tool = Enum.find(tools, &(&1.name == "create_project"))
      input_schema = project_tool.input_schema

      project_field = input_schema.properties["project"]
      team_field = project_field["properties"]["team"]

      assert team_field["type"] == "array"
      team_items = team_field["items"]
      assert team_items["type"] == "object"
      assert "user_id" in team_items["required"]

      role_field = team_items["properties"]["role"]
      assert role_field["enum"] == ["admin", "developer", "viewer"]

      permissions_field = team_items["properties"]["permissions"]
      assert permissions_field["type"] == "array"
      assert permissions_field["items"]["type"] == "string"

      # Check metadata.tags
      metadata_field = project_field["properties"]["metadata"]
      tags_field = metadata_field["properties"]["tags"]
      assert tags_field["type"] == "array"
      assert tags_field["items"]["type"] == "string"
    end
  end

  describe "backward compatibility" do
    defmodule BackwardCompatController do
      def simple_tool(_conn, %{"name" => name}), do: {:ok, name}
    end

    defmodule BackwardCompatRouter do
      use McpServer.Router

      # Old-style simple field definitions should still work
      tool "simple", "Simple tool", BackwardCompatController, :simple_tool do
        input_field("name", "Name", :string, required: true)
        input_field("age", "Age", :integer)
        input_field("active", "Is active", :boolean, default: true)
        output_field("result", "Result", :string)
      end
    end

    test "old-style field definitions still work" do
      conn = mock_conn()
      assert {:ok, tools} = BackwardCompatRouter.list_tools(conn)

      simple_tool = Enum.find(tools, &(&1.name == "simple"))
      assert simple_tool != nil

      input_schema = simple_tool.input_schema
      assert input_schema.type == "object"

      name_field = input_schema.properties["name"]
      assert name_field["type"] == "string"
      assert name_field["description"] == "Name"
      assert "name" in input_schema.required

      age_field = input_schema.properties["age"]
      assert age_field["type"] == "integer"

      active_field = input_schema.properties["active"]
      assert active_field["type"] == "boolean"
      assert active_field["default"] == true
    end

    test "old-style tools can be called" do
      conn = mock_conn()

      assert {:ok, result} = BackwardCompatRouter.call_tool(conn, "simple", %{"name" => "test"})
      assert result == "test"
    end
  end

  describe "nested field validation" do
    test "raises error when duplicate nested field is defined" do
      assert_raise SyntaxError, ~r/field "name" duplicated/, fn ->
        defmodule DuplicateNestedField.Controller do
          def test(_conn, _args), do: {:ok, "test"}
        end

        defmodule DuplicateNestedField.Router do
          use McpServer.Router

          tool "test", "Test", DuplicateNestedField.Controller, :test do
            input_field("user", "User", :object) do
              field("name", "First name", :string)
              field("name", "Second name", :string)
            end
          end
        end
      end
    end

    test "raises error for unexpected statement in nested field" do
      assert_raise SyntaxError, ~r/Unexpected statement in nested field definition/, fn ->
        defmodule InvalidNestedStatement.Controller do
          def test(_conn, _args), do: {:ok, "test"}
        end

        defmodule InvalidNestedStatement.Router do
          use McpServer.Router

          tool "test", "Test", InvalidNestedStatement.Controller, :test do
            input_field("user", "User", :object) do
              field("name", "Name", :string)
              invalid_macro("bad", "statement")
            end
          end
        end
      end
    end

    test "raises error when items missing from array block" do
      assert_raise SyntaxError, ~r/Expected 'items' definition in array field/, fn ->
        defmodule MissingItems.Controller do
          def test(_conn, _args), do: {:ok, "test"}
        end

        defmodule MissingItems.Router do
          use McpServer.Router

          tool "test", "Test", MissingItems.Controller, :test do
            input_field("data", "Data", :array) do
              field("name", "Name", :string)
            end
          end
        end
      end
    end
  end
end
