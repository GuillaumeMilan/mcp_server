defmodule McpServer.App.CSP do
  @moduledoc """
  Generates Content-Security-Policy headers from `McpServer.Resource.Meta.UI` configuration.

  Per the MCP Apps specification, UI resources run in sandboxed iframes with
  restrictive CSP defaults. Servers can declare additional domains in their
  resource metadata to relax specific directives.

  ## Default Policy

  When no CSP is configured, the following restrictive default is applied:

      default-src 'none';
      script-src 'self' 'unsafe-inline';
      style-src 'self' 'unsafe-inline';
      img-src 'self' data:;
      media-src 'self' data:;
      connect-src 'none'

  ## Custom Policy

  When a `Resource.Meta.UI` declares CSP domains, they are merged into the
  appropriate directives:

  - `connect_domains` → `connect-src`
  - `resource_domains` → `img-src`, `script-src`, `style-src`, `font-src`
  - `frame_domains` → `frame-src`
  - `base_uri_domains` → `base-uri`
  """

  alias McpServer.Resource.Meta.UI
  alias McpServer.Resource.Meta.UI.CSP, as: CSPStruct

  @doc """
  Generates a CSP header string from a `McpServer.Resource.Meta.UI` struct.

  Returns the restrictive default when `nil` is passed or when no CSP
  is configured on the struct.

  ## Examples

      iex> McpServer.App.CSP.generate(nil)
      "default-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; media-src 'self' data:; connect-src 'none'"

      iex> meta = McpServer.Resource.Meta.UI.new(csp: McpServer.Resource.Meta.UI.CSP.new(connect_domains: ["api.example.com"]))
      iex> McpServer.App.CSP.generate(meta)
      "default-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; media-src 'self' data:; connect-src 'self' api.example.com; font-src 'self'"
  """
  @spec generate(UI.t() | nil) :: String.t()
  def generate(nil) do
    default_csp()
  end

  def generate(%UI{csp: nil}) do
    default_csp()
  end

  def generate(%UI{csp: %CSPStruct{} = csp}) do
    connect_domains = csp.connect_domains
    resource_domains = csp.resource_domains
    frame_domains = csp.frame_domains
    base_uri_domains = csp.base_uri_domains

    directives = [
      {"default-src", ["'none'"]},
      {"script-src", ["'self'", "'unsafe-inline'"] ++ resource_domains},
      {"style-src", ["'self'", "'unsafe-inline'"] ++ resource_domains},
      {"img-src", ["'self'", "data:"] ++ resource_domains},
      {"media-src", ["'self'", "data:"] ++ resource_domains},
      {"connect-src", build_connect_src(connect_domains)},
      {"font-src", ["'self'"] ++ resource_domains}
    ]

    directives =
      if frame_domains != [] do
        directives ++ [{"frame-src", frame_domains}]
      else
        directives
      end

    directives =
      if base_uri_domains != [] do
        directives ++ [{"base-uri", base_uri_domains}]
      else
        directives
      end

    directives
    |> Enum.map(fn {directive, sources} ->
      directive <> " " <> Enum.join(sources, " ")
    end)
    |> Enum.join("; ")
  end

  defp default_csp do
    "default-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; media-src 'self' data:; connect-src 'none'"
  end

  defp build_connect_src([]), do: ["'none'"]
  defp build_connect_src(domains), do: ["'self'"] ++ domains
end
