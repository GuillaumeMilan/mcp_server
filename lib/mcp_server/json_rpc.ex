defmodule McpServer.JsonRpc do
  @moduledoc """
  The JSONRpc module handles JSON-RPC communication for the McpServer.

  This module provides functionality to process JSON-RPC requests and responses according to the
  JSON-RPC 2.0 specification. It handles request parsing, validation, method dispatch,
  and response formatting.
  """

  @jsonrpc_version "2.0"

  defmodule Request do
    @moduledoc """
    Represents a JSON-RPC 2.0 request object.
    """
    defstruct [:jsonrpc, :method, :params, :id]

    @type t :: %__MODULE__{
            jsonrpc: String.t(),
            method: String.t(),
            params: map() | list() | nil,
            id: String.t() | integer() | nil
          }
  end

  defmodule Response do
    @moduledoc """
    Represents a JSON-RPC 2.0 response object.
    """
    defstruct [:jsonrpc, :result, :error, :id]

    @type t :: %__MODULE__{
            jsonrpc: String.t(),
            result: any() | nil,
            error: map() | nil,
            id: String.t() | integer() | nil
          }
  end

  defmodule Error do
    @moduledoc """
    Represents a JSON-RPC 2.0 error object.
    """
    defstruct [:code, :message, :data]

    @type t :: %__MODULE__{
            code: integer(),
            message: String.t(),
            data: any() | nil
          }
  end

  @doc """
  Creates a new JSON-RPC request object.

  ## Parameters
  - `method`: The method name to call
  - `params`: Parameters for the method (optional)
  - `id`: Request identifier (optional, for notifications use nil)

  ## Examples
      iex> VibersServerMCP.JsonRpc.new_request("get_user", %{user_id: 123}, "req-1")
      %VibersServerMCP.JsonRpc.Request{
        jsonrpc: "2.0",
        method: "get_user",
        params: %{user_id: 123},
        id: "req-1"
      }
  """
  @spec new_request(String.t(), map() | list() | nil, String.t() | integer() | nil) :: Request.t()
  def new_request(method, params \\ nil, id \\ nil) do
    %Request{
      jsonrpc: @jsonrpc_version,
      method: method,
      params: params,
      id: id
    }
  end

  @doc """
  Creates a new JSON-RPC response object with a result.

  ## Parameters
  - `result`: The result of the method call
  - `id`: Request identifier

  ## Examples
      iex> VibersServerMCP.JsonRpc.new_response(%{name: "John"}, "req-1")
      %VibersServerMCP.JsonRpc.Response{
        jsonrpc: "2.0",
        result: %{name: "John"},
        error: nil,
        id: "req-1"
      }
  """
  @spec new_response(any(), String.t() | integer() | nil) :: Response.t()
  def new_response(result, id) do
    %Response{
      jsonrpc: @jsonrpc_version,
      result: result,
      error: nil,
      id: id
    }
  end

  @doc """
  Creates a new JSON-RPC error response object.

  ## Parameters
  - `code`: Error code
  - `message`: Error message
  - `data`: Additional error data (optional)
  - `id`: Request identifier

  ## Examples
      iex> VibersServerMCP.JsonRpc.new_error_response(-32601, "Method not found", nil, "req-1")
      %VibersServerMCP.JsonRpc.Response{
        jsonrpc: "2.0",
        result: nil,
        error: %VibersServerMCP.JsonRpc.Error{code: -32601, message: "Method not found", data: nil},
        id: "req-1"
      }
  """
  @spec new_error_response(integer(), String.t(), any(), String.t() | integer() | nil) ::
          Response.t()
  def new_error_response(code, message, data \\ nil, id) do
    error = %Error{
      code: code,
      message: message,
      data: data
    }

    %Response{
      jsonrpc: @jsonrpc_version,
      result: nil,
      error: error,
      id: id
    }
  end

  @doc """
  Decodes a map (from Jason) into a Request struct.

  ## Parameters
  - `map`: A map representing a JSON-RPC request

  ## Returns
  - `{:ok, Request.t()}` on success
  - `{:error, String.t()}` on failure

  ## Examples
      iex> VibersServerMCP.JsonRpc.decode_request(%{
      ...>   "jsonrpc" => "2.0",
      ...>   "method" => "get_user",
      ...>   "params" => %{"user_id" => 123},
      ...>   "id" => "req-1"
      ...> })
      {:ok, %VibersServerMCP.JsonRpc.Request{
        jsonrpc: "2.0",
        method: "get_user",
        params: %{"user_id" => 123},
        id: "req-1"
      }}
  """
  @spec decode_request(map()) :: {:ok, Request.t()} | {:error, String.t()}
  def decode_request(map) when is_map(map) do
    with {:ok, jsonrpc} <- validate_jsonrpc_version(map),
         {:ok, method} <- validate_method(map),
         {:ok, params} <- extract_params(map),
         {:ok, id} <- extract_id(map) do
      request = %Request{
        jsonrpc: jsonrpc,
        method: method,
        params: params,
        id: id
      }

      {:ok, request}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def decode_request(_), do: {:error, "Invalid request format"}

  @doc """
  Encodes a Request struct into a map that can be JSON encoded.

  ## Parameters
  - `request`: A Request struct

  ## Returns
  - A map representation of the request

  ## Examples
      iex> request = %VibersServerMCP.JsonRpc.Request{
      ...>   jsonrpc: "2.0",
      ...>   method: "get_user",
      ...>   params: %{user_id: 123},
      ...>   id: "req-1"
      ...> }
      iex> VibersServerMCP.JsonRpc.encode_request(request)
      %{
        "jsonrpc" => "2.0",
        "method" => "get_user",
        "params" => %{user_id: 123},
        "id" => "req-1"
      }
  """
  @spec encode_request(Request.t()) :: map()
  def encode_request(%Request{} = request) do
    %{
      "jsonrpc" => request.jsonrpc,
      "method" => request.method
    }
    |> maybe_add_field("params", request.params)
    |> maybe_add_field("id", request.id)
  end

  @doc """
  Decodes a map (from Jason) into a Response struct.

  ## Parameters
  - `map`: A map representing a JSON-RPC response

  ## Returns
  - `{:ok, Response.t()}` on success
  - `{:error, String.t()}` on failure

  ## Examples
      iex> VibersServerMCP.JsonRpc.decode_response(%{
      ...>   "jsonrpc" => "2.0",
      ...>   "result" => %{"name" => "John"},
      ...>   "id" => "req-1"
      ...> })
      {:ok, %VibersServerMCP.JsonRpc.Response{
        jsonrpc: "2.0",
        result: %{"name" => "John"},
        error: nil,
        id: "req-1"
      }}
  """
  @spec decode_response(map()) :: {:ok, Response.t()} | {:error, String.t()}
  def decode_response(map) when is_map(map) do
    with {:ok, jsonrpc} <- validate_jsonrpc_version(map),
         {:ok, result, error} <- extract_result_or_error(map),
         {:ok, id} <- extract_id(map) do
      response = %Response{
        jsonrpc: jsonrpc,
        result: result,
        error: error,
        id: id
      }

      {:ok, response}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def decode_response(_), do: {:error, "Invalid response format"}

  @doc """
  Encodes a Response struct into a map that can be JSON encoded.

  ## Parameters
  - `response`: A Response struct

  ## Returns
  - A map representation of the response

  ## Examples
      iex> response = %VibersServerMCP.JsonRpc.Response{
      ...>   jsonrpc: "2.0",
      ...>   result: %{name: "John"},
      ...>   error: nil,
      ...>   id: "req-1"
      ...> }
      iex> VibersServerMCP.JsonRpc.encode_response(response)
      %{
        "jsonrpc" => "2.0",
        "result" => %{name: "John"},
        "id" => "req-1"
      }
  """
  @spec encode_response(Response.t()) :: map()
  def encode_response(%Response{} = response) do
    %{
      "jsonrpc" => response.jsonrpc
    }
    |> maybe_add_result_or_error(response.result, response.error)
    |> maybe_add_field("id", response.id)
  end

  # Private helper functions

  defp validate_jsonrpc_version(%{"jsonrpc" => @jsonrpc_version}), do: {:ok, @jsonrpc_version}

  defp validate_jsonrpc_version(%{"jsonrpc" => version}),
    do: {:error, "Invalid JSON-RPC version: #{version}"}

  defp validate_jsonrpc_version(_), do: {:error, "Missing jsonrpc field"}

  defp validate_method(%{"method" => method}) when is_binary(method), do: {:ok, method}
  defp validate_method(%{"method" => _}), do: {:error, "Method must be a string"}
  defp validate_method(_), do: {:error, "Missing method field"}

  defp extract_params(%{"params" => params}), do: {:ok, params}
  defp extract_params(_), do: {:ok, nil}

  defp extract_id(%{"id" => id}), do: {:ok, id}
  defp extract_id(_), do: {:ok, nil}

  defp extract_result_or_error(%{"result" => _result, "error" => _error}) do
    {:error, "Response cannot have both result and error"}
  end

  defp extract_result_or_error(%{"result" => result}) do
    {:ok, result, nil}
  end

  defp extract_result_or_error(%{"error" => error_map}) do
    case decode_error(error_map) do
      {:ok, error} -> {:ok, nil, error}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_result_or_error(_) do
    {:error, "Response must have either result or error"}
  end

  defp decode_error(%{"code" => code, "message" => message} = error_map)
       when is_integer(code) and is_binary(message) do
    data = Map.get(error_map, "data")

    error = %Error{
      code: code,
      message: message,
      data: data
    }

    {:ok, error}
  end

  defp decode_error(_), do: {:error, "Invalid error format"}

  defp maybe_add_field(map, _key, nil), do: map
  defp maybe_add_field(map, key, value), do: Map.put(map, key, value)

  defp maybe_add_result_or_error(map, result, nil) when result != nil do
    Map.put(map, "result", result)
  end

  defp maybe_add_result_or_error(map, nil, %Error{} = error) do
    error_map =
      %{
        "code" => error.code,
        "message" => error.message
      }
      |> maybe_add_field("data", error.data)

    Map.put(map, "error", error_map)
  end

  defp maybe_add_result_or_error(map, nil, nil), do: map
end
