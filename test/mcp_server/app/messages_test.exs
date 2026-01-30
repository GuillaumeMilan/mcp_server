defmodule McpServer.App.MessagesTest do
  use ExUnit.Case, async: true

  alias McpServer.App.Messages
  alias McpServer.App.AppCapabilities
  alias McpServer.App.HostCapabilities
  alias McpServer.App.HostContext
  alias McpServer.JsonRpc

  describe "ui/initialize" do
    test "encode_initialize_request produces valid request" do
      app_caps = AppCapabilities.new(tools: %{list_changed: true})
      request = Messages.encode_initialize_request(app_caps, 1)

      assert %JsonRpc.Request{} = request
      assert request.method == "ui/initialize"
      assert request.id == 1
      assert request.params["appCapabilities"] == app_caps
    end

    test "encode_initialize_response produces valid response" do
      host_caps = HostCapabilities.new(open_links: %{})
      host_ctx = HostContext.new(theme: "dark")
      response = Messages.encode_initialize_response(host_caps, host_ctx, 1)

      assert %JsonRpc.Response{} = response
      assert response.id == 1
      assert response.result["hostCapabilities"] == host_caps
      assert response.result["hostContext"] == host_ctx
    end

    test "decode_initialize_request extracts app capabilities" do
      params = %{
        "appCapabilities" => %{
          "tools" => %{"listChanged" => true},
          "availableDisplayModes" => ["inline", "fullscreen"]
        }
      }

      assert {:ok, app_caps} = Messages.decode_initialize_request(params)
      assert app_caps.tools == %{list_changed: true}
      assert app_caps.available_display_modes == ["inline", "fullscreen"]
    end

    test "decode_initialize_request handles missing appCapabilities" do
      assert {:ok, app_caps} = Messages.decode_initialize_request(%{})
      assert app_caps.tools == nil
      assert app_caps.available_display_modes == nil
    end

    test "decode_initialize_request errors on non-map" do
      assert {:error, _} = Messages.decode_initialize_request("invalid")
    end
  end

  describe "ui/open-link" do
    test "encode_open_link produces valid request" do
      request = Messages.encode_open_link("https://example.com", 1)
      assert request.method == "ui/open-link"
      assert request.params == %{"url" => "https://example.com"}
    end

    test "decode_open_link extracts URL" do
      assert {:ok, "https://example.com"} =
               Messages.decode_open_link(%{"url" => "https://example.com"})
    end

    test "decode_open_link errors on missing URL" do
      assert {:error, _} = Messages.decode_open_link(%{})
    end
  end

  describe "ui/message" do
    test "encode_message produces valid request" do
      content = %{"type" => "text", "text" => "Hello"}
      request = Messages.encode_message("user", content, 1)
      assert request.method == "ui/message"
      assert request.params["role"] == "user"
      assert request.params["content"] == content
    end

    test "decode_message extracts role and content" do
      params = %{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}

      assert {:ok, %{role: "user", content: %{"type" => "text"}}} =
               Messages.decode_message(params)
    end

    test "decode_message errors on missing role" do
      assert {:error, _} = Messages.decode_message(%{"content" => %{}})
    end

    test "decode_message errors on non-map content" do
      assert {:error, _} = Messages.decode_message(%{"role" => "user", "content" => "string"})
    end
  end

  describe "ui/request-display-mode" do
    test "encode_request_display_mode produces valid request" do
      request = Messages.encode_request_display_mode("fullscreen", 1)
      assert request.method == "ui/request-display-mode"
      assert request.params == %{"mode" => "fullscreen"}
    end

    test "decode_request_display_mode extracts mode" do
      assert {:ok, "fullscreen"} =
               Messages.decode_request_display_mode(%{"mode" => "fullscreen"})
    end

    test "decode_request_display_mode errors on missing mode" do
      assert {:error, _} = Messages.decode_request_display_mode(%{})
    end
  end

  describe "ui/update-model-context" do
    test "encode_update_model_context with content" do
      content = [%{"type" => "text", "text" => "context"}]
      request = Messages.encode_update_model_context(content, nil, 1)
      assert request.method == "ui/update-model-context"
      assert request.params["content"] == content
      refute Map.has_key?(request.params, "structuredContent")
    end

    test "encode_update_model_context with both content and structured" do
      content = [%{"type" => "text", "text" => "context"}]
      structured = %{"key" => "value"}
      request = Messages.encode_update_model_context(content, structured, 1)
      assert request.params["content"] == content
      assert request.params["structuredContent"] == structured
    end

    test "decode_update_model_context extracts fields" do
      params = %{
        "content" => [%{"type" => "text"}],
        "structuredContent" => %{"key" => "value"}
      }

      assert {:ok, %{content: [_], structured_content: %{"key" => "value"}}} =
               Messages.decode_update_model_context(params)
    end

    test "decode_update_model_context handles missing fields" do
      assert {:ok, %{content: nil, structured_content: nil}} =
               Messages.decode_update_model_context(%{})
    end
  end

  describe "ui/notifications/tool-input" do
    test "encode_tool_input produces notification" do
      msg = Messages.encode_tool_input(%{"location" => "NYC"})
      assert msg["jsonrpc"] == "2.0"
      assert msg["method"] == "ui/notifications/tool-input"
      assert msg["params"]["arguments"] == %{"location" => "NYC"}
    end

    test "decode_tool_input extracts arguments" do
      assert {:ok, %{"location" => "NYC"}} =
               Messages.decode_tool_input(%{"arguments" => %{"location" => "NYC"}})
    end

    test "decode_tool_input errors on missing arguments" do
      assert {:error, _} = Messages.decode_tool_input(%{})
    end
  end

  describe "ui/notifications/tool-input-partial" do
    test "encode_tool_input_partial produces notification" do
      msg = Messages.encode_tool_input_partial(%{"loc" => "NY"})
      assert msg["method"] == "ui/notifications/tool-input-partial"
      assert msg["params"]["arguments"] == %{"loc" => "NY"}
    end

    test "decode_tool_input_partial extracts arguments" do
      assert {:ok, %{"loc" => "NY"}} =
               Messages.decode_tool_input_partial(%{"arguments" => %{"loc" => "NY"}})
    end
  end

  describe "ui/notifications/tool-result" do
    test "encode_tool_result produces notification" do
      result = %{"content" => [%{"type" => "text", "text" => "72F"}], "isError" => false}
      msg = Messages.encode_tool_result(result)
      assert msg["method"] == "ui/notifications/tool-result"
      assert msg["params"] == result
    end
  end

  describe "ui/notifications/tool-cancelled" do
    test "encode_tool_cancelled produces notification" do
      msg = Messages.encode_tool_cancelled("user_cancelled")
      assert msg["method"] == "ui/notifications/tool-cancelled"
      assert msg["params"]["reason"] == "user_cancelled"
    end

    test "decode_tool_cancelled extracts reason" do
      assert {:ok, "user_cancelled"} =
               Messages.decode_tool_cancelled(%{"reason" => "user_cancelled"})
    end

    test "decode_tool_cancelled errors on missing reason" do
      assert {:error, _} = Messages.decode_tool_cancelled(%{})
    end
  end

  describe "ui/notifications/host-context-changed" do
    test "encode_host_context_changed produces notification" do
      partial = %{"theme" => "light"}
      msg = Messages.encode_host_context_changed(partial)
      assert msg["method"] == "ui/notifications/host-context-changed"
      assert msg["params"] == partial
    end
  end

  describe "ui/notifications/size-changed" do
    test "encode_size_changed produces notification" do
      msg = Messages.encode_size_changed(800, 600)
      assert msg["method"] == "ui/notifications/size-changed"
      assert msg["params"] == %{"width" => 800, "height" => 600}
    end

    test "decode_size_changed extracts dimensions" do
      assert {:ok, %{width: 800, height: 600}} =
               Messages.decode_size_changed(%{"width" => 800, "height" => 600})
    end

    test "decode_size_changed errors on missing dimensions" do
      assert {:error, _} = Messages.decode_size_changed(%{"width" => 800})
    end

    test "decode_size_changed errors on non-number dimensions" do
      assert {:error, _} = Messages.decode_size_changed(%{"width" => "800", "height" => "600"})
    end
  end

  describe "ui/resource-teardown" do
    test "encode_resource_teardown produces request" do
      request = Messages.encode_resource_teardown("navigation", 1)
      assert %JsonRpc.Request{} = request
      assert request.method == "ui/resource-teardown"
      assert request.params == %{"reason" => "navigation"}
    end

    test "decode_resource_teardown extracts reason" do
      assert {:ok, "navigation"} =
               Messages.decode_resource_teardown(%{"reason" => "navigation"})
    end

    test "decode_resource_teardown errors on missing reason" do
      assert {:error, _} = Messages.decode_resource_teardown(%{})
    end
  end
end
