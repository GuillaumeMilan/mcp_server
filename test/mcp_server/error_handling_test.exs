defmodule McpServer.ErrorHandlingTest do
  use ExUnit.Case, async: true
  import McpServer.Controller, only: [message: 3, completion: 2, content: 3]

  # Helper to create a mock connection
  defp mock_conn do
    %McpServer.Conn{session_id: "test-session-123", private: %{}}
  end

  # Controller that returns various error types
  defmodule ErrorController do
    def tool_returns_ok(_conn, _args) do
      {:ok, "success"}
    end

    def tool_returns_error(_conn, _args) do
      {:error, "Something went wrong"}
    end

    def tool_raises_exception(_conn, _args) do
      raise RuntimeError, "Tool crashed"
    end

    def tool_returns_bare_value(_conn, _args) do
      "bare value"
    end

    def prompt_returns_ok(_conn, _args) do
      {:ok, [message("user", "text", "Hello")]}
    end

    def prompt_returns_error(_conn, _args) do
      {:error, "Prompt failed"}
    end

    def prompt_raises_exception(_conn, _args) do
      raise RuntimeError, "Prompt crashed"
    end

    def prompt_returns_bare_list(_conn, _args) do
      [message("user", "text", "Hello")]
    end

    def prompt_returns_invalid(_conn, _args) do
      "not a list"
    end

    def complete_returns_ok(_conn, _arg, _prefix) do
      {:ok, completion(["value1", "value2"], total: 2, has_more: false)}
    end

    def complete_returns_error(_conn, _arg, _prefix) do
      {:error, "Completion failed"}
    end

    def complete_raises_exception(_conn, _arg, _prefix) do
      raise RuntimeError, "Completion crashed"
    end

    def complete_returns_bare_map(_conn, _arg, _prefix) do
      completion(["value"], [])
    end

    def resource_returns_ok(_conn, _opts) do
      {:ok, %{"contents" => [content("test", "https://example.com/test", text: "test")]}}
    end

    def resource_returns_error(_conn, _opts) do
      {:error, "Resource read failed"}
    end

    def resource_raises_exception(_conn, _opts) do
      raise RuntimeError, "Resource crashed"
    end

    def resource_returns_bare_map(_conn, _opts) do
      %{"contents" => [content("test", "https://example.com/test", text: "test")]}
    end
  end

  # Router for error testing
  defmodule ErrorRouter do
    use McpServer.Router

    tool "tool_ok", "Returns {:ok, result}", ErrorController, :tool_returns_ok do
      input_field("param", "A parameter", :string, required: false)
      output_field("result", "Result", :string)
    end

    tool "tool_error", "Returns {:error, message}", ErrorController, :tool_returns_error do
      input_field("param", "A parameter", :string, required: false)
      output_field("result", "Result", :string)
    end

    tool "tool_exception", "Raises an exception", ErrorController, :tool_raises_exception do
      input_field("param", "A parameter", :string, required: false)
      output_field("result", "Result", :string)
    end

    tool "tool_bare", "Returns bare value", ErrorController, :tool_returns_bare_value do
      input_field("param", "A parameter", :string, required: false)
      output_field("result", "Result", :string)
    end

    prompt "prompt_ok", "Returns {:ok, messages}" do
      argument("param", "A parameter", required: false)
      get(ErrorController, :prompt_returns_ok)
      complete(ErrorController, :complete_returns_ok)
    end

    prompt "prompt_error", "Returns {:error, message}" do
      argument("param", "A parameter", required: false)
      get(ErrorController, :prompt_returns_error)
      complete(ErrorController, :complete_returns_error)
    end

    prompt "prompt_exception", "Raises an exception" do
      argument("param", "A parameter", required: false)
      get(ErrorController, :prompt_raises_exception)
      complete(ErrorController, :complete_raises_exception)
    end

    prompt "prompt_bare", "Returns bare list" do
      argument("param", "A parameter", required: false)
      get(ErrorController, :prompt_returns_bare_list)
      complete(ErrorController, :complete_returns_bare_map)
    end

    prompt "prompt_invalid", "Returns invalid type" do
      argument("param", "A parameter", required: false)
      get(ErrorController, :prompt_returns_invalid)
      complete(ErrorController, :complete_returns_ok)
    end

    resource "resource_ok", "https://example.com/ok" do
      description("Returns {:ok, result}")
      read(ErrorController, :resource_returns_ok)
    end

    resource "resource_error", "https://example.com/error" do
      description("Returns {:error, message}")
      read(ErrorController, :resource_returns_error)
    end

    resource "resource_exception", "https://example.com/exception" do
      description("Raises an exception")
      read(ErrorController, :resource_raises_exception)
    end

    resource "resource_bare", "https://example.com/bare" do
      description("Returns bare map")
      read(ErrorController, :resource_returns_bare_map)
    end
  end

  describe "tool error handling" do
    test "tool returning {:ok, result} is handled correctly" do
      conn = mock_conn()
      assert {:ok, "success"} = ErrorRouter.call_tool(conn, "tool_ok", %{})
    end

    test "tool returning {:error, message} is handled correctly" do
      conn = mock_conn()
      assert {:error, "Something went wrong"} = ErrorRouter.call_tool(conn, "tool_error", %{})
    end

    test "tool raising exception is caught and returned as error" do
      conn = mock_conn()
      assert {:error, error_msg} = ErrorRouter.call_tool(conn, "tool_exception", %{})
      assert error_msg =~ "Tool execution failed"
      assert error_msg =~ "Tool crashed"
    end

    test "tool returning bare value is wrapped in {:ok, result}" do
      conn = mock_conn()
      assert {:error, error} = ErrorRouter.call_tool(conn, "tool_bare", %{})
      assert error =~ "Tool execution failed: Invalid tool response,"
    end

    test "missing required tool arguments returns error" do
      conn = mock_conn()

      defmodule RequiredToolController do
        def required_tool(_conn, _args), do: {:ok, "result"}
      end

      defmodule RequiredToolRouter do
        use McpServer.Router

        tool "required", "Tool with required param", RequiredToolController, :required_tool do
          input_field("required_param", "Required", :string, required: true)
          output_field("result", "Result", :string)
        end
      end

      assert {:error, message} = RequiredToolRouter.call_tool(conn, "required", %{})
      assert message =~ "Missing required arguments"
    end
  end

  describe "prompt error handling" do
    test "prompt returning {:ok, messages} is handled correctly" do
      conn = mock_conn()
      assert {:ok, messages} = ErrorRouter.get_prompt(conn, "prompt_ok", %{})
      assert is_list(messages)
    end

    test "prompt returning {:error, message} is handled correctly" do
      conn = mock_conn()
      assert {:error, "Prompt failed"} = ErrorRouter.get_prompt(conn, "prompt_error", %{})
    end

    test "prompt raising exception is caught and returned as error" do
      conn = mock_conn()
      assert {:error, error_msg} = ErrorRouter.get_prompt(conn, "prompt_exception", %{})
      assert error_msg =~ "Prompt execution failed"
      assert error_msg =~ "Prompt crashed"
    end

    test "prompt returning bare list is wrapped in {:ok, result}" do
      conn = mock_conn()
      assert {:ok, messages} = ErrorRouter.get_prompt(conn, "prompt_bare", %{})
      assert is_list(messages)
    end

    test "prompt returning invalid type is returned as error" do
      conn = mock_conn()
      assert {:error, error_msg} = ErrorRouter.get_prompt(conn, "prompt_invalid", %{})
      assert error_msg =~ "Invalid prompt response"
    end
  end

  describe "completion error handling" do
    test "completion returning {:ok, result} is handled correctly" do
      conn = mock_conn()
      assert {:ok, result} = ErrorRouter.complete_prompt(conn, "prompt_ok", "param", "")
      assert is_map(result)
    end

    test "completion returning {:error, message} is handled correctly" do
      conn = mock_conn()

      assert {:error, "Completion failed"} =
               ErrorRouter.complete_prompt(conn, "prompt_error", "param", "")
    end

    test "completion raising exception is caught and returned as error" do
      conn = mock_conn()

      assert {:error, error_msg} =
               ErrorRouter.complete_prompt(conn, "prompt_exception", "param", "")

      assert error_msg =~ "Completion execution failed"
      assert error_msg =~ "Completion crashed"
    end

    test "completion returning bare map is wrapped in {:ok, result}" do
      conn = mock_conn()
      assert {:ok, result} = ErrorRouter.complete_prompt(conn, "prompt_bare", "param", "")
      assert is_map(result)
    end

    test "completion for non-existent argument returns error" do
      conn = mock_conn()
      assert {:error, message} = ErrorRouter.complete_prompt(conn, "prompt_ok", "nonexistent", "")
      assert message =~ "Argument 'nonexistent' not found"
    end
  end

  describe "resource error handling" do
    test "resource returning {:ok, result} is handled correctly" do
      conn = mock_conn()
      assert {:ok, result} = ErrorRouter.read_resource(conn, "resource_ok", %{})
      assert is_map(result)
    end

    test "resource returning {:error, message} is handled correctly" do
      conn = mock_conn()

      assert {:error, "Resource read failed"} =
               ErrorRouter.read_resource(conn, "resource_error", %{})
    end

    test "resource raising exception is caught and returned as error" do
      conn = mock_conn()
      assert {:error, error_msg} = ErrorRouter.read_resource(conn, "resource_exception", %{})
      assert error_msg =~ "Resource read failed"
      assert error_msg =~ "Resource crashed"
    end

    test "resource returning bare map is wrapped in {:ok, result}" do
      conn = mock_conn()
      assert {:ok, result} = ErrorRouter.read_resource(conn, "resource_bare", %{})
      assert is_map(result)
    end
  end

  describe "list functions always succeed" do
    test "list_tools returns {:ok, list}" do
      conn = mock_conn()
      assert {:ok, tools} = ErrorRouter.list_tools(conn)
      assert is_list(tools)
      assert length(tools) == 4
    end

    test "prompts_list returns {:ok, list}" do
      conn = mock_conn()
      assert {:ok, prompts} = ErrorRouter.prompts_list(conn)
      assert is_list(prompts)
      assert length(prompts) == 5
    end

    test "list_resources returns {:ok, list}" do
      conn = mock_conn()
      assert {:ok, resources} = ErrorRouter.list_resources(conn)
      assert is_list(resources)
      assert length(resources) == 4
    end

    test "list_templates_resource returns {:ok, list}" do
      conn = mock_conn()
      assert {:ok, templates} = ErrorRouter.list_templates_resource(conn)
      assert is_list(templates)
      assert length(templates) == 0
    end
  end
end
