defmodule McpServer.Resource.Meta.UI.Permissions do
  @moduledoc """
  Sandbox permissions requested by a UI resource.

  Each field represents a browser capability that the sandboxed iframe
  may request access to. Set a field to `true` to request the permission.

  ## Fields

  - `camera` - Camera access
  - `microphone` - Microphone access
  - `geolocation` - Location access
  - `clipboard_write` - Clipboard write access

  ## Examples

      iex> McpServer.Resource.Meta.UI.Permissions.new(camera: true, geolocation: true)
      %McpServer.Resource.Meta.UI.Permissions{camera: true, geolocation: true}
  """

  defstruct [
    camera: false,
    microphone: false,
    geolocation: false,
    clipboard_write: false
  ]

  @type t :: %__MODULE__{
          camera: boolean(),
          microphone: boolean(),
          geolocation: boolean(),
          clipboard_write: boolean()
        }

  @doc """
  Creates a new Permissions struct.

  ## Parameters

  - `opts` - Keyword list of options:
    - `:camera` - Request camera access (default: `false`)
    - `:microphone` - Request microphone access (default: `false`)
    - `:geolocation` - Request geolocation access (default: `false`)
    - `:clipboard_write` - Request clipboard write access (default: `false`)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      camera: Keyword.get(opts, :camera, false),
      microphone: Keyword.get(opts, :microphone, false),
      geolocation: Keyword.get(opts, :geolocation, false),
      clipboard_write: Keyword.get(opts, :clipboard_write, false)
    }
  end
end

defimpl Jason.Encoder, for: McpServer.Resource.Meta.UI.Permissions do
  def encode(value, opts) do
    map = %{}

    map = maybe_put(map, "camera", value.camera)
    map = maybe_put(map, "microphone", value.microphone)
    map = maybe_put(map, "geolocation", value.geolocation)
    map = maybe_put(map, "clipboardWrite", value.clipboard_write)

    Jason.Encode.map(map, opts)
  end

  defp maybe_put(map, _key, false), do: map
  defp maybe_put(map, key, true), do: Map.put(map, key, %{})
end
