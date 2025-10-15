defmodule McpServer.Conn do
  @moduledoc """
  Protocol defining the MCP connection interface.

  This protocol abstracts the connection details for different transport mechanisms
  (e.g., HTTP, STDIO, custom transports). It provides a unified way to access
  session information and other connection-specific data.
  """

  defstruct [:session_id, private: %{}]

  @type t :: %__MODULE__{
          session_id: String.t(),
          private: map()
        }

  @doc """
  Retrieves the session ID associated with the connection.

  The session ID is a unique identifier for the current MCP session.

  ## Examples

      iex> conn = %McpServer.Conn{session_id: "abc123"}
      iex> McpServer.Conn.get_session_id(conn)
      "abc123"
  """
  @spec get_session_id(t()) :: String.t()
  def get_session_id(%__MODULE__{session_id: session_id}) do
    session_id
  end

  @doc """
  Stores private data into the connection for later usage.
  This function allows you to associate arbitrary key-value pairs with the connection.

  ## Examples

      iex> conn = %McpServer.Conn{}
      iex> conn = McpServer.Conn.put_private(conn, :user_role, :admin)
      iex> conn.private
      %{user_role: :admin}
  """
  @spec put_private(t(), any(), any()) :: t()
  def put_private(conn, key, value) do
    %{conn | private: Map.put(conn.private, key, value)}
  end

  @doc """
  Retrieves private data associated with the connection.
  This function allows you to access previously stored key-value pairs.
  If the key does not exist, it returns the provided default value (or `nil` if no default is given).
  ## Examples

      iex> conn = %McpServer.Conn{private: %{user_role: :admin}}
      iex> McpServer.Conn.get_private(conn, :user_role)
      :admin
      iex> McpServer.Conn.get_private(conn, :nonexistent_key, :default_value)
      :default_value
  """
  @spec get_private(t(), any(), any()) :: any()
  def get_private(conn, key, default \\ nil) do
    Map.get(conn.private, key, default)
  end
end
