defmodule McpServer.Tool.CallResultTest do
  use ExUnit.Case, async: true

  alias McpServer.Tool.CallResult
  alias McpServer.Tool.Content

  describe "new/1" do
    test "creates with content only" do
      result = CallResult.new(content: [Content.text("hello")])
      assert length(result.content) == 1
      assert result.structured_content == nil
      assert result._meta == nil
    end

    test "creates with content and structured_content" do
      result =
        CallResult.new(
          content: [Content.text("Weather: 72F")],
          structured_content: %{"temperature" => 72, "unit" => "fahrenheit"}
        )

      assert length(result.content) == 1
      assert result.structured_content == %{"temperature" => 72, "unit" => "fahrenheit"}
      assert result._meta == nil
    end

    test "creates with all fields" do
      result =
        CallResult.new(
          content: [Content.text("Result")],
          structured_content: %{"data" => "value"},
          _meta: %{"timestamp" => "2024-01-01"}
        )

      assert result.content != nil
      assert result.structured_content == %{"data" => "value"}
      assert result._meta == %{"timestamp" => "2024-01-01"}
    end

    test "raises on missing content" do
      assert_raise KeyError, fn ->
        CallResult.new([])
      end
    end
  end

  describe "handle_tool_result/2" do
    test "passes a {:ok, content_list} return through (validated)" do
      content = [Content.text("hello")]
      assert {:ok, ^content} = CallResult.handle_tool_result({:ok, content}, "t")
    end

    test "validates and rewraps a {:ok, %CallResult{}} return" do
      content = [Content.text("hello")]
      call_result = %CallResult{content: content, structured_content: %{"a" => 1}}

      assert {:ok, %CallResult{content: ^content, structured_content: %{"a" => 1}}} =
               CallResult.handle_tool_result({:ok, call_result}, "t")
    end

    test "passes an {:error, reason} return through unchanged" do
      assert {:error, "boom"} = CallResult.handle_tool_result({:error, "boom"}, "t")
    end

    # This is the load-bearing test for the compile-time type enforcement. `handle_tool_result/2`
    # deliberately has NO catch-all clause: that is exactly what keeps its inferred parameter type
    # restricted to `{:ok, _} | {:error, _}`, so Elixir >= 1.20 reports a malformed tool return as
    # an "incompatible types" warning at the consumer's `use McpServer.Router` site. A catch-all
    # would silence that enforcement — and would also stop this raising. So pinning the raise here
    # pins the enforcement.
    test "raises (no catch-all) on a malformed, non-{:ok | :error} return" do
      assert_raise FunctionClauseError, fn ->
        CallResult.handle_tool_result(:not_a_valid_return, "t")
      end

      assert_raise FunctionClauseError, fn ->
        CallResult.handle_tool_result({:weird, 1, 2}, "t")
      end
    end
  end
end
