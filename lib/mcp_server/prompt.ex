defmodule McpServer.Prompt do
  @moduledoc """
  Helper functions for working with MCP prompts.

  This module provides utility functions for creating prompt messages and completions
  in controller functions that implement prompt handlers.

  ## Examples

      import McpServer.Prompt, only: [message: 3, completion: 2]

      def get_greet_prompt(%{"user_name" => user_name}) do
        [
          message("user", "text", "Hello \#{user_name}! Welcome to our MCP server. How can I assist you today?"),
          message("assistant", "text", "I'm here to help you with any questions or tasks you might have.")
        ]
      end

      def complete_greet_prompt("user_name", user_name_prefix) do
        completion(["Alice", "Bob", "Charlie"], total: 10, has_more: true)
      end
  """

  @doc """
  Creates a message for a prompt response.

  ## Parameters

  - `role` - The role of the message sender ("user", "assistant", "system")
  - `type` - The type of content ("text", "image", etc.)
  - `content` - The actual content of the message

  ## Examples

      message("user", "text", "Hello world!")
      #=> %{
      #     "role" => "user",
      #     "content" => %{
      #       "type" => "text",
      #       "text" => "Hello world!"
      #     }
      #   }
  """
  def message(role, type, content) when is_binary(role) and is_binary(type) and is_binary(content) do
    %{
      "role" => role,
      "content" => %{
        "type" => type,
        type => content
      }
    }
  end

  @doc """
  Creates a completion response for prompt argument completion.

  ## Parameters

  - `values` - A list of completion values
  - `opts` - Optional parameters:
    - `:total` - Total number of possible completions
    - `:has_more` - Whether there are more completions available

  ## Examples

      completion(["Alice", "Bob", "Charlie"])
      #=> %{
      #     "values" => ["Alice", "Bob", "Charlie"],
      #     "total" => nil,
      #     "hasMore" => false
      #   }

      completion(["Alice", "Bob"], total: 10, has_more: true)
      #=> %{
      #     "values" => ["Alice", "Bob"],
      #     "total" => 10,
      #     "hasMore" => true
      #   }
  """
  def completion(values, opts \\ []) when is_list(values) do
    total = Keyword.get(opts, :total)
    has_more = Keyword.get(opts, :has_more, false)

    %{
      "values" => values,
      "total" => total,
      "hasMore" => has_more
    }
    |> Map.reject(fn {_, v} -> is_nil(v) end)
  end
end
