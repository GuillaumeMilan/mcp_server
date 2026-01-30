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
end
