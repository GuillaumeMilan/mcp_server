defmodule McpServer.CompletionTest do
  use ExUnit.Case, async: true

  alias McpServer.Completion

  describe "new/1" do
    test "creates a completion with values only" do
      completion = Completion.new(values: ["Alice", "Bob", "Charlie"])

      assert completion.values == ["Alice", "Bob", "Charlie"]
      assert completion.total == nil
      assert completion.has_more == nil
    end

    test "creates a completion with all fields" do
      completion =
        Completion.new(
          values: ["option1", "option2"],
          total: 100,
          has_more: true
        )

      assert completion.values == ["option1", "option2"]
      assert completion.total == 100
      assert completion.has_more == true
    end

    test "creates an empty completion" do
      completion = Completion.new(values: [])

      assert completion.values == []
      assert completion.total == nil
      assert completion.has_more == nil
    end

    test "creates a completion with has_more false" do
      completion =
        Completion.new(
          values: ["last_item"],
          total: 1,
          has_more: false
        )

      assert completion.values == ["last_item"]
      assert completion.total == 1
      assert completion.has_more == false
    end

    test "raises error when values is missing" do
      assert_raise KeyError, fn ->
        Completion.new(total: 100)
      end
    end
  end

  describe "Jason.Encoder" do
    test "encodes minimal completion" do
      completion = Completion.new(values: ["Alice", "Bob"])

      json = Jason.encode!(completion)
      decoded = Jason.decode!(json)

      assert decoded["values"] == ["Alice", "Bob"]
      refute Map.has_key?(decoded, "total")
      refute Map.has_key?(decoded, "hasMore")
    end

    test "encodes completion with all fields" do
      completion =
        Completion.new(
          values: ["item1", "item2", "item3"],
          total: 50,
          has_more: true
        )

      json = Jason.encode!(completion)
      decoded = Jason.decode!(json)

      assert decoded["values"] == ["item1", "item2", "item3"]
      assert decoded["total"] == 50
      assert decoded["hasMore"] == true
    end

    test "encodes empty completion" do
      completion = Completion.new(values: [], total: 0, has_more: false)

      json = Jason.encode!(completion)
      decoded = Jason.decode!(json)

      assert decoded["values"] == []
      assert decoded["total"] == 0
      assert decoded["hasMore"] == false
    end

    test "uses camelCase for hasMore field" do
      completion =
        Completion.new(
          values: ["test"],
          has_more: true
        )

      json = Jason.encode!(completion)

      assert String.contains?(json, "hasMore")
      refute String.contains?(json, "has_more")
    end

    test "omits nil fields from JSON" do
      completion = Completion.new(values: ["test"])

      json = Jason.encode!(completion)
      decoded = Jason.decode!(json)

      assert Map.has_key?(decoded, "values")
      refute Map.has_key?(decoded, "total")
      refute Map.has_key?(decoded, "hasMore")
    end
  end
end
