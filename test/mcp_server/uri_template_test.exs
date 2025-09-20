defmodule McpServer.URITemplateTest do
  use ExUnit.Case, async: true
  doctest McpServer.URITemplate

  alias McpServer.URITemplate

  describe "new/1 and parsing" do
    test "parses literals and variables" do
      tpl = URITemplate.new("/users/:id/profile/{section}")

      assert tpl.template == "/users/:id/profile/{section}"
      assert tpl.vars == ["id", "section"]
      assert Enum.count(tpl.segments) == 4
    end
  end

  describe "interpolate/2" do
    test "builds uri from variables with atom keys" do
      tpl = URITemplate.new("/users/:id/posts/{post_id}")
      assert {:ok, "/users/42/posts/7"} = URITemplate.interpolate(tpl, %{id: 42, post_id: 7})
    end

    test "builds uri from variables with string keys" do
      tpl = URITemplate.new("/users/:id/posts/{post_id}")

      assert {:ok, "/users/42/posts/7"} =
               URITemplate.interpolate(tpl, %{"id" => 42, "post_id" => 7})
    end

    test "returns error when missing var" do
      tpl = URITemplate.new("/a/:x/b/{y}")
      assert {:error, msg} = URITemplate.interpolate(tpl, %{"x" => "one"})
      assert msg =~ "missing variable"
    end
  end

  describe "match/2" do
    test "matches and extracts variables" do
      tpl = URITemplate.new("/users/:id/posts/{post}")
      assert {:ok, vars} = URITemplate.match(tpl, "/users/123/posts/abc")
      assert vars["id"] == "123"
      assert vars["post"] == "abc"
    end

    test "nomatch on literal mismatch" do
      tpl = URITemplate.new("/users/:id")
      assert :nomatch = URITemplate.match(tpl, "/accounts/1")
    end

    test "nomatch on segment count mismatch" do
      tpl = URITemplate.new("/a/:b/c")
      assert :nomatch = URITemplate.match(tpl, "/a/1")
    end
  end

  describe "examples" do
    test "with prefix length and full" do
      tpl = URITemplate.new("http://example.com/dictionary/{term:1}/{term}")

      # valid interpolations
      assert {:ok, "http://example.com/dictionary/c/cat"} =
               URITemplate.interpolate(tpl, %{"term" => "cat"})

      assert {:ok, "http://example.com/dictionary/d/dog"} =
               URITemplate.interpolate(tpl, %{term: "dog"})

      # invalid match: the URI with swapped segments should not match the template
      assert :nomatch = URITemplate.match(tpl, "http://example.com/dictionary/duck/c")

      # matching should extract variables when segments align
      assert {:ok, vars} = URITemplate.match(tpl, "http://example.com/dictionary/c/cat")
      assert vars["term"] == "cat"
    end

    test "with query template interpolation" do
      tpl = URITemplate.new("http://example.com/search{?q,lang}")

      assert {:ok, "http://example.com/search?q=question&lang=fr"} =
               URITemplate.interpolate(tpl, %{"q" => "question", "lang" => "fr"})

      # matching should accept and extract query params
      assert {:ok, vars} = URITemplate.match(tpl, "http://example.com/search?q=question&lang=fr")
      assert vars["q"] == "question"
      assert vars["lang"] == "fr"
    end

    test "with optional query variables" do
      tpl = URITemplate.new("http://example.com/search{?q,lang}")

      # only q provided
      assert {:ok, "http://example.com/search?q=question"} =
               URITemplate.interpolate(tpl, %{"q" => "question"})

      # none provided -> no query string
      assert {:ok, "http://example.com/search"} = URITemplate.interpolate(tpl, %{})

      # matching with only q present
      assert {:ok, vars} = URITemplate.match(tpl, "http://example.com/search?q=question")
      assert vars["q"] == "question"
      assert Map.get(vars, "lang") == nil
    end

    test "with query param order reversed" do
      tpl = URITemplate.new("http://example.com/search{?q,lang}")

      # params in reversed order should still be matched and extracted
      assert {:ok, vars} = URITemplate.match(tpl, "http://example.com/search?lang=fr&q=question")
      assert vars["q"] == "question"
      assert vars["lang"] == "fr"
    end
  end
end
