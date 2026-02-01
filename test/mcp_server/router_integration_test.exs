defmodule McpServer.App.RouterIntegrationTest do
  use ExUnit.Case, async: true

  alias McpServer.Tool.CallResult
  alias McpServer.Tool.Content

  # Controller with standard return
  defmodule StandardController do
    def echo(_conn, args) do
      {:ok, [Content.text(Map.get(args, "message", "default"))]}
    end
  end

  # Controller returning CallResult with structuredContent
  defmodule UIController do
    def get_weather(_conn, args) do
      location = Map.get(args, "location", "unknown")

      {:ok,
       CallResult.new(
         content: [Content.text("Weather in #{location}: 72F")],
         structured_content: %{
           "temperature" => 72,
           "unit" => "fahrenheit",
           "location" => location
         }
       )}
    end

    def get_weather_with_meta(_conn, args) do
      location = Map.get(args, "location", "unknown")

      {:ok,
       CallResult.new(
         content: [Content.text("Weather: 72F")],
         structured_content: %{"temperature" => 72},
         _meta: %{"source" => "weather-api", "timestamp" => "2024-01-01T00:00:00Z"}
       )}
    end
  end

  # Resource controller
  defmodule DashboardController do
    import McpServer.Controller, only: [content: 3]

    def read_dashboard(_conn, _params) do
      McpServer.Resource.ReadResult.new(
        contents: [
          content(
            "Dashboard",
            "ui://weather/dashboard",
            mimeType: "text/html;profile=mcp-app",
            text: "<html>Dashboard</html>"
          )
        ]
      )
    end

    def read_config(_conn, _params) do
      McpServer.Resource.ReadResult.new(
        contents: [
          content("Config", "file:///config.json", mimeType: "application/json", text: "{}")
        ]
      )
    end
  end

  # Router with UI tools and resources
  defmodule UIRouter do
    use McpServer.Router

    # Tool with UI metadata
    tool "get_weather", "Gets weather data", UIController, :get_weather,
      ui: "ui://weather/dashboard",
      visibility: [:model, :app] do
      input_field("location", "Location", :string, required: true)
    end

    # Tool with UI but app-only visibility
    tool "get_weather_meta", "Gets weather with meta", UIController, :get_weather_with_meta,
      ui: "ui://weather/dashboard",
      visibility: [:app] do
      input_field("location", "Location", :string, required: true)
    end

    # Tool without UI (backward compat)
    tool "echo", "Echoes input", StandardController, :echo do
      input_field("message", "Message", :string, required: true)
    end

    # UI resource with CSP and permissions
    resource "dashboard", "ui://weather/dashboard" do
      description("Interactive weather dashboard")
      mimeType("text/html;profile=mcp-app")
      read(DashboardController, :read_dashboard)

      csp(connect_domains: ["api.weather.com"], resource_domains: ["cdn.weather.com"])
      permissions(camera: true)
      app_domain("a904794854a047f6.example.com")
      prefers_border(true)
    end

    # Non-UI resource (backward compat)
    resource "config", "file:///config.json" do
      description("App configuration")
      mimeType("application/json")
      read(DashboardController, :read_config)
    end
  end

  defp mock_conn, do: %McpServer.Conn{session_id: "test-session"}

  describe "list_tools with UI metadata" do
    test "tools with ui option include _meta.ui with resourceUri" do
      {:ok, tools} = UIRouter.list_tools(mock_conn())

      weather_tool = Enum.find(tools, &(&1.name == "get_weather"))
      assert weather_tool._meta != nil
      assert weather_tool._meta.ui.resource_uri == "ui://weather/dashboard"
    end

    test "tools with visibility option include visibility in _meta.ui" do
      {:ok, tools} = UIRouter.list_tools(mock_conn())

      weather_tool = Enum.find(tools, &(&1.name == "get_weather"))
      assert weather_tool._meta.ui.visibility == [:model, :app]

      app_only_tool = Enum.find(tools, &(&1.name == "get_weather_meta"))
      assert app_only_tool._meta.ui.visibility == [:app]
    end

    test "tools without ui option have nil _meta" do
      {:ok, tools} = UIRouter.list_tools(mock_conn())

      echo_tool = Enum.find(tools, &(&1.name == "echo"))
      assert echo_tool._meta == nil
    end

    test "_meta.ui serializes to correct JSON" do
      {:ok, tools} = UIRouter.list_tools(mock_conn())

      weather_tool = Enum.find(tools, &(&1.name == "get_weather"))
      json = Jason.decode!(Jason.encode!(weather_tool))

      assert json["_meta"]["ui"]["resourceUri"] == "ui://weather/dashboard"
      assert json["_meta"]["ui"]["visibility"] == ["model", "app"]
    end
  end

  describe "call_tool with CallResult" do
    test "returns CallResult when controller uses it" do
      {:ok, result} = UIRouter.call_tool(mock_conn(), "get_weather", %{"location" => "NYC"})

      assert %CallResult{} = result
      assert length(result.content) == 1
      assert result.structured_content["temperature"] == 72
      assert result.structured_content["location"] == "NYC"
    end

    test "returns CallResult with _meta" do
      {:ok, result} =
        UIRouter.call_tool(mock_conn(), "get_weather_meta", %{"location" => "NYC"})

      assert %CallResult{} = result
      assert result._meta["source"] == "weather-api"
    end

    test "returns content list for backward compat controllers" do
      {:ok, result} = UIRouter.call_tool(mock_conn(), "echo", %{"message" => "hello"})

      assert is_list(result)
      assert length(result) == 1
    end

    test "validates content inside CallResult" do
      {:ok, result} = UIRouter.call_tool(mock_conn(), "get_weather", %{"location" => "NYC"})

      assert %CallResult{} = result
      [content_item] = result.content
      assert %Content.Text{} = content_item
    end
  end

  describe "list_resources with UI metadata" do
    test "UI resources include _meta" do
      {:ok, resources} = UIRouter.list_resources(mock_conn())

      dashboard = Enum.find(resources, &(&1.name == "dashboard"))
      assert dashboard._meta != nil
      assert dashboard._meta.ui.domain == "a904794854a047f6.example.com"
      assert dashboard._meta.ui.prefers_border == true
    end

    test "UI resources _meta serializes CSP correctly" do
      {:ok, resources} = UIRouter.list_resources(mock_conn())

      dashboard = Enum.find(resources, &(&1.name == "dashboard"))
      json = Jason.decode!(Jason.encode!(dashboard))

      assert json["_meta"]["ui"]["csp"]["connectDomains"] == ["api.weather.com"]
      assert json["_meta"]["ui"]["csp"]["resourceDomains"] == ["cdn.weather.com"]
      assert json["_meta"]["ui"]["permissions"]["camera"] == %{}
      assert json["_meta"]["ui"]["domain"] == "a904794854a047f6.example.com"
      assert json["_meta"]["ui"]["prefersBorder"] == true
    end

    test "non-UI resources have nil _meta" do
      {:ok, resources} = UIRouter.list_resources(mock_conn())

      config = Enum.find(resources, &(&1.name == "config"))
      assert config._meta == nil
    end
  end
end
