defmodule McpServer.URITemplate do
  @moduledoc """
  Utility for simple URI templates.

  Supports templates with named segments using either `:name` or `{name}`.
  Examples:
    "/users/:id"
    "/posts/{post_id}/comments/{id}"

  Provides:
  - `new/1` to create a parsed template struct
  - `interpolate/2` to build a URI from variables
  - `match/2` to check and extract variables from a uri string

  Examples:

    iex> tpl = McpServer.URITemplate.new("/users/:id/posts/{post}")
    iex> tpl.vars
    ["id", "post"]
    iex> {:ok, uri} = McpServer.URITemplate.interpolate(tpl, %{id: 42, post: "hello"})
    iex> uri
    "/users/42/posts/hello"
    iex> McpServer.URITemplate.match(tpl, "/users/42/posts/hello")
    {:ok, %{"id" => "42", "post" => "hello"}}
  """

  defstruct [:template, :segments, :vars]

  @type t :: %__MODULE__{template: String.t(), segments: [any()], vars: [String.t()]}

  @doc """
  Create a parsed URI template from a string.

  Examples:

      iex> tpl = McpServer.URITemplate.new("/users/:id/profile/{section}")
      iex> tpl.template
      "/users/:id/profile/{section}"
      iex> tpl.vars
      ["id", "section"]
  """
  @spec new(String.t()) :: t()
  def new(template) when is_binary(template) do
    # Extract a trailing query expression like `{?q,lang}` if present
    {path_template, query_vars} =
      case Regex.run(~r/\{\?([^}]+)\}\s*$/, template) do
        nil -> {template, []}
        [_, vars] -> {String.replace(template, "{" <> "?" <> vars <> "}", ""), String.split(vars, ",") |> Enum.map(&String.trim/1)}
      end

    segments =
      path_template
      |> String.split("/")
      |> normalize_segments()
      |> Enum.map(&parse_segment/1)

    segments =
      if query_vars == [], do: segments, else: segments ++ [{:query, query_vars}]

    vars =
      segments
      |> Enum.flat_map(fn
        {:var, name} -> [name]
        {:var, name, _opts} -> [name]
        {:query, qvars} -> qvars
        _ -> []
      end)

    %__MODULE__{template: template, segments: segments, vars: vars}
  end

  defp parse_segment(<<":"::utf8, rest::binary>>) when rest != "" do
    {:var, rest}
  end

  # Brace expression that occupies the whole segment, possibly with a modifier
  defp parse_segment(seg) when is_binary(seg) do
    case Regex.run(~r/^\{([^}]+)\}$/, seg) do
      nil -> {:lit, seg}
      [_, inner] ->
        # Check for prefix modifier name:length
        case String.split(inner, ":", parts: 2) do
          [name, len_str] ->
            case Integer.parse(len_str) do
              {n, ""} -> {:var, name, {:prefix, n}}
              _ -> {:var, inner}
            end

          [name] -> {:var, name}
        end
    end
  end

  @doc """
  Interpolate a template with a map of variables (string or atom keys).

  Returns `{:ok, uri}` or `{:error, reason}` when variables are missing.

  Examples:

      iex> tpl = McpServer.URITemplate.new("/users/:id/posts/{post_id}")
      iex> McpServer.URITemplate.interpolate(tpl, %{id: 42, post_id: 7})
      {:ok, "/users/42/posts/7"}

  iex> tpl = McpServer.URITemplate.new("/a/:x/b/{y}")
  iex> McpServer.URITemplate.interpolate(tpl, %{"x" => "one"})
  {:error, "missing variable: y"}
  """
  @spec interpolate(t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def interpolate(%__MODULE__{} = tpl, vars) when is_map(vars) do
    vars = stringify_keys(vars)

    result =
      Enum.reduce_while(tpl.segments, {:ok, []}, fn
        {:lit, ""}, {:ok, acc} ->
          {:cont, {:ok, acc ++ [""]}}

        {:lit, seg}, {:ok, acc} ->
          {:cont, {:ok, acc ++ [seg]}}

        {:var, name}, {:ok, acc} ->
          case Map.fetch(vars, name) do
            {:ok, v} when not is_nil(v) -> {:cont, {:ok, acc ++ [to_string(v)]}}
            _ -> {:halt, {:error, "missing variable: #{name}"}}
          end

        {:var, name, {:prefix, n}}, {:ok, acc} ->
          case Map.fetch(vars, name) do
            {:ok, v} when not is_nil(v) ->
              s = to_string(v)
              if String.length(s) >= n do
                {:cont, {:ok, acc ++ [String.slice(s, 0, n)]}}
              else
                {:halt, {:error, "variable #{name} shorter than prefix #{n}"}}
              end

            _ -> {:halt, {:error, "missing variable: #{name}"}}
          end

        {:query, qvars}, {:ok, acc} ->
          case build_query(qvars, vars) do
            {:ok, ""} -> {:cont, {:ok, acc}}
            {:ok, qs} ->
              new_acc =
                case acc do
                  [] -> ["?" <> qs]
                  _ ->
                    {init, [last]} = Enum.split(acc, length(acc) - 1)
                    init ++ [last <> "?" <> qs]
                end

              {:cont, {:ok, new_acc}}

            {:error, _} = err -> {:halt, err}
          end
      end)

    case result do
      {:ok, parts} ->
        uri = parts |> Enum.join("/")
        # Ensure we don't output a stray slash before the query string
        uri = String.replace(uri, "/?", "?")
        uri = if String.starts_with?(tpl.template, "/"), do: "/" <> String.trim_leading(uri, "/"), else: uri
        {:ok, uri}

      {:error, _} = err -> err
    end
  end

  @doc """
  Match a uri string against the template and return `{:ok, vars_map}` or `:nomatch`.

  Examples:

      iex> tpl = McpServer.URITemplate.new("/users/:id/posts/{post}")
      iex> McpServer.URITemplate.match(tpl, "/users/123/posts/abc")
      {:ok, %{"id" => "123", "post" => "abc"}}

      iex> tpl = McpServer.URITemplate.new("/users/:id")
      iex> McpServer.URITemplate.match(tpl, "/accounts/1")
      :nomatch
  """
  @spec match(t(), String.t()) :: {:ok, map()} | :nomatch
  def match(%__MODULE__{} = tpl, uri) when is_binary(uri) do
    # Split off query string if present
    {path, query} =
      case String.split(uri, "?", parts: 2) do
        [p] -> {p, ""}
        [p, q] -> {p, q}
      end

    uri_segments = String.split(path, "/") |> normalize_segments()

    case match_segments(tpl.segments, uri_segments, %{}) do
      {:ok, vars} ->
        # If template included query vars, extract those from the URI query string
        vars =
          case Enum.find(tpl.segments, fn s -> match?({:query, _}, s) end) do
            {:query, qvars} when is_list(qvars) and query != "" ->
              qs_map = parse_query(query)
              Map.merge(vars, Map.take(qs_map, qvars))

            _ -> vars
          end

        {:ok, vars}

      :nomatch -> :nomatch
    end
  end

  defp normalize_segments(segments) do
    segments
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
  end

  defp match_segments([], [], acc), do: {:ok, acc}

  defp match_segments([{:lit, seg} | rest_tpl], [seg | rest_uri], acc) do
    match_segments(rest_tpl, rest_uri, acc)
  end

  defp match_segments([{:lit, _} | _], [], _), do: :nomatch

  defp match_segments([{:var, name} | rest_tpl], [val | rest_uri], acc) do
    match_segments(rest_tpl, rest_uri, Map.put(acc, name, val))
  end

  defp match_segments([{:var, name, {:prefix, n}} | rest_tpl], [val | rest_uri], acc) do
    # For prefix matching, the value at this segment must be exactly n characters
    if String.length(val) == n do
      match_segments(rest_tpl, rest_uri, Map.put(acc, name, val))
    else
      :nomatch
    end
  end

  defp match_segments([{:query, _qvars} | rest_tpl], uri_segments, acc) do
    # query segment doesn't consume a path segment; continue matching with rest
    match_segments(rest_tpl, uri_segments, acc)
  end

  defp match_segments(_, _, _), do: :nomatch

  defp stringify_keys(map) do
    for {k, v} <- map, into: %{} do
      key = if is_atom(k), do: Atom.to_string(k), else: to_string(k)
      {key, v}
    end
  end

  defp build_query(qvars, vars) when is_list(qvars) and is_map(vars) do
    # Treat query variables as optional: include only those present
    pairs =
      qvars
      |> Enum.map(fn q ->
        case Map.fetch(vars, q) do
          {:ok, v} when not is_nil(v) -> {q, to_string(v)}
          _ -> nil
        end
      end)
      |> Enum.filter(& &1)

    qs = pairs |> Enum.map(fn {k, v} -> URI.encode(k) <> "=" <> URI.encode(v) end) |> Enum.join("&")
    {:ok, qs}
  end

  defp parse_query("") , do: %{}

  defp parse_query(qs) when is_binary(qs) do
    qs
    |> String.split("&")
    |> Enum.map(fn pair ->
      case String.split(pair, "=", parts: 2) do
        [k, v] -> {URI.decode(k), URI.decode(v)}
        [k] -> {URI.decode(k), ""}
      end
    end)
    |> Enum.into(%{})
  end
end
