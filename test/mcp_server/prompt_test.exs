defmodule McpServer.PromptTest do
  use ExUnit.Case, async: true

  alias McpServer.Prompt
  alias McpServer.Prompt.{Argument, Message, MessageContent}

  describe "Prompt.new/1" do
    test "creates a prompt with minimal fields" do
      prompt =
        Prompt.new(
          name: "greet",
          description: "A friendly greeting"
        )

      assert prompt.name == "greet"
      assert prompt.description == "A friendly greeting"
      assert prompt.arguments == []
    end

    test "creates a prompt with arguments" do
      arg = Argument.new(name: "user_name", description: "The user's name")

      prompt =
        Prompt.new(
          name: "greet",
          description: "A friendly greeting",
          arguments: [arg]
        )

      assert length(prompt.arguments) == 1
      assert hd(prompt.arguments).name == "user_name"
    end

    test "raises error when required fields are missing" do
      assert_raise KeyError, fn ->
        Prompt.new(name: "greet")
      end
    end
  end

  describe "Argument.new/1" do
    test "creates an argument with required false by default" do
      arg = Argument.new(name: "option", description: "An optional parameter")

      assert arg.name == "option"
      assert arg.description == "An optional parameter"
      assert arg.required == false
    end

    test "creates a required argument" do
      arg =
        Argument.new(
          name: "code",
          description: "Code to review",
          required: true
        )

      assert arg.name == "code"
      assert arg.required == true
    end

    test "raises error when name is missing" do
      assert_raise KeyError, fn ->
        Argument.new(description: "A parameter")
      end
    end
  end

  describe "Message.new/1" do
    test "creates a user message" do
      content = MessageContent.new(type: "text", text: "Hello!")

      message =
        Message.new(
          role: "user",
          content: content
        )

      assert message.role == "user"
      assert message.content.type == "text"
      assert message.content.text == "Hello!"
    end

    test "creates a system message" do
      content = MessageContent.new(type: "text", text: "You are helpful.")

      message =
        Message.new(
          role: "system",
          content: content
        )

      assert message.role == "system"
    end

    test "creates an assistant message" do
      content = MessageContent.new(type: "text", text: "I'm here to help.")

      message =
        Message.new(
          role: "assistant",
          content: content
        )

      assert message.role == "assistant"
    end

    test "raises error when required fields are missing" do
      assert_raise KeyError, fn ->
        Message.new(role: "user")
      end
    end
  end

  describe "MessageContent.new/1" do
    test "creates text content" do
      content = MessageContent.new(type: "text", text: "Hello world!")

      assert content.type == "text"
      assert content.text == "Hello world!"
    end

    test "creates content with type only" do
      content = MessageContent.new(type: "image")

      assert content.type == "image"
      assert content.text == nil
    end

    test "raises error when type is missing" do
      assert_raise KeyError, fn ->
        MessageContent.new(text: "Hello")
      end
    end
  end

  describe "Jason.Encoder for Prompt" do
    test "encodes prompt without arguments" do
      prompt =
        Prompt.new(
          name: "simple",
          description: "A simple prompt"
        )

      json = Jason.encode!(prompt)
      decoded = Jason.decode!(json)

      assert decoded["name"] == "simple"
      assert decoded["description"] == "A simple prompt"
      assert decoded["arguments"] == []
    end

    test "encodes prompt with arguments" do
      arg1 = Argument.new(name: "lang", description: "Language", required: true)
      arg2 = Argument.new(name: "code", description: "Code")

      prompt =
        Prompt.new(
          name: "review",
          description: "Code review",
          arguments: [arg1, arg2]
        )

      json = Jason.encode!(prompt)
      decoded = Jason.decode!(json)

      assert decoded["name"] == "review"
      assert length(decoded["arguments"]) == 2
      assert hd(decoded["arguments"])["name"] == "lang"
      assert hd(decoded["arguments"])["required"] == true
    end
  end

  describe "Jason.Encoder for Argument" do
    test "encodes optional argument" do
      arg = Argument.new(name: "option", description: "An option")

      json = Jason.encode!(arg)
      decoded = Jason.decode!(json)

      assert decoded["name"] == "option"
      assert decoded["description"] == "An option"
      assert decoded["required"] == false
    end

    test "encodes required argument" do
      arg = Argument.new(name: "param", description: "Required param", required: true)

      json = Jason.encode!(arg)
      decoded = Jason.decode!(json)

      assert decoded["required"] == true
    end
  end

  describe "Jason.Encoder for Message" do
    test "encodes user message" do
      content = MessageContent.new(type: "text", text: "Hello!")
      message = Message.new(role: "user", content: content)

      json = Jason.encode!(message)
      decoded = Jason.decode!(json)

      assert decoded["role"] == "user"
      assert decoded["content"]["type"] == "text"
      assert decoded["content"]["text"] == "Hello!"
    end

    test "encodes message with nested content" do
      content = MessageContent.new(type: "text", text: "System message")
      message = Message.new(role: "system", content: content)

      json = Jason.encode!(message)
      decoded = Jason.decode!(json)

      assert decoded["role"] == "system"
      assert decoded["content"]["text"] == "System message"
    end
  end

  describe "Jason.Encoder for MessageContent" do
    test "encodes text content with text field matching type" do
      content = MessageContent.new(type: "text", text: "Hello world!")

      json = Jason.encode!(content)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "text"
      assert decoded["text"] == "Hello world!"
    end

    test "encodes content without text" do
      content = MessageContent.new(type: "image")

      json = Jason.encode!(content)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "image"
      refute Map.has_key?(decoded, "text")
    end

    test "content field uses type as key" do
      content = MessageContent.new(type: "text", text: "Message")

      json = Jason.encode!(content)

      # The JSON should have both "type" and "text" fields
      assert String.contains?(json, ~s("type":"text"))
      assert String.contains?(json, ~s("text":"Message"))
    end
  end
end
