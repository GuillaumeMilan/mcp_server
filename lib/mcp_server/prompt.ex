defmodule McpServer.Prompt do
  @moduledoc """
  Represents a prompt template definition.

  This module defines the structure for MCP prompts, which are interactive
  message templates with argument completion support.

  ## Fields

  - `name` - Unique prompt identifier
  - `description` - Human-readable description
  - `arguments` - List of argument definitions for the prompt

  ## Examples

      iex> prompt = McpServer.Prompt.new(
      ...>   name: "code_review",
      ...>   description: "Generates a code review prompt",
      ...>   arguments: [
      ...>     McpServer.Prompt.Argument.new(
      ...>       name: "language",
      ...>       description: "Programming language",
      ...>       required: true
      ...>     )
      ...>   ]
      ...> )
      %McpServer.Prompt{
        name: "code_review",
        description: "Generates a code review prompt",
        arguments: [%McpServer.Prompt.Argument{...}]
      }
  """

  @enforce_keys [:name, :description]
  defstruct [
    :name,
    :description,
    arguments: []
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          arguments: list(McpServer.Prompt.Argument.t())
        }

  @doc """
  Creates a new Prompt struct.

  ## Parameters

  - `opts` - Keyword list of prompt options:
    - `:name` (required) - Unique prompt identifier
    - `:description` (required) - Human-readable description
    - `:arguments` - List of Prompt.Argument structs (default: [])

  ## Examples

      iex> McpServer.Prompt.new(
      ...>   name: "greet",
      ...>   description: "A friendly greeting"
      ...> )
      %McpServer.Prompt{
        name: "greet",
        description: "A friendly greeting",
        arguments: []
      }

      iex> McpServer.Prompt.new(
      ...>   name: "greet",
      ...>   description: "A friendly greeting",
      ...>   arguments: [
      ...>     McpServer.Prompt.Argument.new(
      ...>       name: "user_name",
      ...>       description: "Name of the user",
      ...>       required: true
      ...>     )
      ...>   ]
      ...> )
      %McpServer.Prompt{name: "greet", arguments: [%McpServer.Prompt.Argument{...}]}
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      description: Keyword.fetch!(opts, :description),
      arguments: Keyword.get(opts, :arguments, [])
    }
  end
end

defmodule McpServer.Prompt.Argument do
  @moduledoc """
  Represents an argument definition for a prompt.

  Arguments define the parameters that can be passed to a prompt template.
  They include metadata about whether the argument is required and a description
  to help users understand what value to provide.

  ## Fields

  - `name` - Argument identifier
  - `description` - Human-readable description
  - `required` - Whether the argument is mandatory

  ## Examples

      iex> arg = McpServer.Prompt.Argument.new(
      ...>   name: "language",
      ...>   description: "Programming language",
      ...>   required: true
      ...> )
      %McpServer.Prompt.Argument{
        name: "language",
        description: "Programming language",
        required: true
      }
  """

  @enforce_keys [:name, :description]
  defstruct [
    :name,
    :description,
    required: false
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          required: boolean()
        }

  @doc """
  Creates a new Prompt.Argument struct.

  ## Parameters

  - `opts` - Keyword list of argument options:
    - `:name` (required) - Argument identifier
    - `:description` (required) - Human-readable description
    - `:required` - Whether the argument is mandatory (default: false)

  ## Examples

      iex> McpServer.Prompt.Argument.new(
      ...>   name: "user_name",
      ...>   description: "The user's name"
      ...> )
      %McpServer.Prompt.Argument{
        name: "user_name",
        description: "The user's name",
        required: false
      }

      iex> McpServer.Prompt.Argument.new(
      ...>   name: "code",
      ...>   description: "Code to review",
      ...>   required: true
      ...> )
      %McpServer.Prompt.Argument{
        name: "code",
        description: "Code to review",
        required: true
      }
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      description: Keyword.fetch!(opts, :description),
      required: Keyword.get(opts, :required, false)
    }
  end
end

defmodule McpServer.Prompt.Message do
  @moduledoc """
  Represents a single message in a prompt response.

  Messages are the building blocks of prompt conversations. Each message has
  a role (user, assistant, or system) and content.

  ## Fields

  - `role` - The role of the message sender ("user", "assistant", or "system")
  - `content` - The message content (MessageContent struct)

  ## Examples

      iex> message = McpServer.Prompt.Message.new(
      ...>   role: "user",
      ...>   content: McpServer.Prompt.MessageContent.new(
      ...>     type: "text",
      ...>     text: "Hello world!"
      ...>   )
      ...> )
      %McpServer.Prompt.Message{
        role: "user",
        content: %McpServer.Prompt.MessageContent{type: "text", text: "Hello world!"}
      }
  """

  @enforce_keys [:role, :content]
  defstruct [:role, :content]

  @type t :: %__MODULE__{
          role: String.t(),
          content: McpServer.Prompt.MessageContent.t()
        }

  @doc """
  Creates a new Prompt.Message struct.

  ## Parameters

  - `opts` - Keyword list of message options:
    - `:role` (required) - The role ("user", "assistant", or "system")
    - `:content` (required) - MessageContent struct

  ## Examples

      iex> McpServer.Prompt.Message.new(
      ...>   role: "system",
      ...>   content: McpServer.Prompt.MessageContent.new(
      ...>     type: "text",
      ...>     text: "You are a helpful assistant."
      ...>   )
      ...> )
      %McpServer.Prompt.Message{role: "system", content: %McpServer.Prompt.MessageContent{...}}

      iex> McpServer.Prompt.Message.new(
      ...>   role: "user",
      ...>   content: McpServer.Prompt.MessageContent.new(
      ...>     type: "text",
      ...>     text: "What is the weather?"
      ...>   )
      ...> )
      %McpServer.Prompt.Message{role: "user", content: %McpServer.Prompt.MessageContent{...}}
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      role: Keyword.fetch!(opts, :role),
      content: Keyword.fetch!(opts, :content)
    }
  end
end

defmodule McpServer.Prompt.MessageContent do
  @moduledoc """
  Represents the content of a prompt message.

  Message content can be of various types (text, image, etc.). Currently,
  text content is the primary supported type.

  ## Fields

  - `type` - The content type ("text", "image", etc.)
  - `text` - The text content (for text type)
  - Additional fields can be added for other content types

  ## Examples

      iex> content = McpServer.Prompt.MessageContent.new(
      ...>   type: "text",
      ...>   text: "Hello world!"
      ...> )
      %McpServer.Prompt.MessageContent{
        type: "text",
        text: "Hello world!"
      }
  """

  @enforce_keys [:type]
  defstruct [
    :type,
    :text
  ]

  @type t :: %__MODULE__{
          type: String.t(),
          text: String.t() | nil
        }

  @doc """
  Creates a new Prompt.MessageContent struct.

  ## Parameters

  - `opts` - Keyword list of content options:
    - `:type` (required) - The content type
    - `:text` - The text content (for text type)

  ## Examples

      iex> McpServer.Prompt.MessageContent.new(
      ...>   type: "text",
      ...>   text: "This is a text message"
      ...> )
      %McpServer.Prompt.MessageContent{
        type: "text",
        text: "This is a text message"
      }

      iex> McpServer.Prompt.MessageContent.new(type: "text")
      %McpServer.Prompt.MessageContent{type: "text", text: nil}
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      type: Keyword.fetch!(opts, :type),
      text: Keyword.get(opts, :text)
    }
  end
end

# Jason Encoders

defimpl Jason.Encoder, for: McpServer.Prompt do
  def encode(value, opts) do
    map = %{
      "name" => value.name,
      "description" => value.description,
      "arguments" => value.arguments
    }

    Jason.Encode.map(map, opts)
  end
end

defimpl Jason.Encoder, for: McpServer.Prompt.Argument do
  def encode(value, opts) do
    map = %{
      "name" => value.name,
      "description" => value.description,
      "required" => value.required
    }

    Jason.Encode.map(map, opts)
  end
end

defimpl Jason.Encoder, for: McpServer.Prompt.Message do
  def encode(value, opts) do
    map = %{
      "role" => value.role,
      "content" => value.content
    }

    Jason.Encode.map(map, opts)
  end
end

defimpl Jason.Encoder, for: McpServer.Prompt.MessageContent do
  def encode(value, opts) do
    map = %{
      "type" => value.type
    }

    # Add the text field with the same key as the type
    map =
      if value.text do
        Map.put(map, value.type, value.text)
      else
        map
      end

    Jason.Encode.map(map, opts)
  end
end
