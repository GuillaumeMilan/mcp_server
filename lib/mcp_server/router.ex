defmodule McpServer.Router do
  @moduledoc """
  A Domain-Specific Language (DSL) for defining Model Context Protocol (MCP) servers.

  `McpServer.Router` provides a declarative way to define MCP tools, prompts, and resources
  with automatic validation, schema generation, and request routing. It implements the
  `McpServer` behaviour and generates the necessary callback implementations at compile time.

  ## Overview

  The Router DSL allows you to define three main MCP capabilities:

  - **Tools** - Callable functions with typed input/output schemas and validation
  - **Prompts** - Interactive message templates with argument completion support
  - **Resources** - Data sources with URI-based access and optional templating

  All controller functions receive a `McpServer.Conn` struct as their first parameter,
  providing access to session information and connection context.

  ## Usage

  To create an MCP server, use `McpServer.Router` in your module and define your capabilities:

      defmodule MyApp.Router do
        use McpServer.Router

        # Define tools
        tool "calculator", "Performs arithmetic operations", MyApp.Calculator, :calculate do
          input_field("operation", "The operation to perform", :string,
            required: true,
            enum: ["add", "subtract", "multiply", "divide"])
          input_field("a", "First operand", :number, required: true)
          input_field("b", "Second operand", :number, required: true)
          output_field("result", "The calculation result", :number)
        end

        # Define prompts
        prompt "code_review", "Generates a code review prompt" do
          argument("language", "Programming language", required: true)
          argument("code", "Code to review", required: true)
          get MyApp.Prompts, :get_code_review
          complete MyApp.Prompts, :complete_code_review
        end

        # Define resources
        resource "config", "file:///app/config/{name}.json" do
          description "Application configuration files"
          mimeType "application/json"
          read MyApp.Resources, :read_config
          complete MyApp.Resources, :complete_config
        end
      end

  ## Connection Context

  All controller functions receive a `McpServer.Conn` struct as their first parameter:

      def my_tool(conn, args) do
        # Access session ID
        session_id = conn.session_id

        # Access private data stored in the connection
        user = McpServer.Conn.get_private(conn, :user)

        # Your tool logic here
      end

  The connection provides:
  - `session_id` - Unique identifier for the current session
  - `private` - A map for storing custom data (accessible via helper functions)

  ## Tools

  Tools are functions that clients can invoke with validated inputs. Each tool requires:

  1. A unique name
  2. A description
  3. A controller module and function (arity 2: conn, args)
  4. Input/output field definitions

  ### Tool Definition

      tool "name", "description", ControllerModule, :function_name do
        input_field("param", "Parameter description", :type, opts)
        output_field("result", "Result description", :type)
      end

  ### Supported Field Types

  - `:string` - Text values
  - `:integer` - Whole numbers
  - `:number` - Numeric values (integers and floats)
  - `:boolean` - True/false values
  - `:array` - Lists of values
  - `:object` - Nested structures

  ### Field Options

  - `required: true/false` - Whether the field is mandatory (default: false)
  - `enum: [...]` - Restrict values to a specific set
  - `default: value` - Default value if not provided

  ### Tool Hints

  Tools can include behavioral hints for clients:

      tool "read_file", "Reads a file", FileController, :read,
        title: "File Reader",
        hints: [:read_only, :idempotent, :closed_world] do
        # fields...
      end

  Available hints:
  - `:read_only` - Tool doesn't modify state
  - `:non_destructive` - Tool is safe to call
  - `:idempotent` - Tool can be called repeatedly with same result
  - `:closed_world` - Tool only works with known/predefined data

  ### Controller Implementation

      defmodule MyApp.Calculator do
        def calculate(conn, %{"operation" => op, "a" => a, "b" => b}) do
          # Access session info if needed
          IO.inspect(conn.session_id)

          case op do
            "add" -> a + b
            "subtract" -> a - b
            "multiply" -> a * b
            "divide" when b != 0 -> a / b
            "divide" -> {:error, "Division by zero"}
          end
        end
      end

  ## Prompts

  Prompts are interactive message templates that help structure conversations.
  They support argument completion for improved user experience.

  ### Prompt Definition

      prompt "name", "description" do
        argument("arg_name", "Argument description", required: true)
        get ControllerModule, :get_function
        complete ControllerModule, :complete_function
      end

  ### Controller Implementation

  Prompt controllers need two functions:

  #### Get Function (arity 2: conn, args)

  Returns a list of messages for the conversation:

      defmodule MyApp.Prompts do
        import McpServer.Controller, only: [message: 3]

        def get_code_review(conn, %{"language" => lang, "code" => code}) do
          [
            message("system", "text",
              "You are an expert " <> lang <> " code reviewer."),
            message("user", "text",
              "Please review this code:\\n\\n" <> code)
          ]
        end
      end

  #### Complete Function (arity 3: conn, argument_name, prefix)

  Provides completion suggestions for prompt arguments:

      defmodule MyApp.Prompts do
        import McpServer.Controller, only: [completion: 2]

        def complete_code_review(conn, "language", prefix) do
          languages = ["elixir", "python", "javascript", "rust", "go"]
          filtered = Enum.filter(languages, &String.starts_with?(&1, prefix))

          completion(filtered, total: length(languages), has_more: false)
        end

        def complete_code_review(_conn, _arg, _prefix), do: completion([], [])
      end

  ## Resources

  Resources represent data sources that clients can read. They support:
  - Static URIs for fixed resources
  - URI templates with variables (e.g., `{id}`) for dynamic resources
  - Optional completion for template variables

  ### Static Resource

      resource "readme", "file:///app/README.md" do
        description "Project README file"
        mimeType "text/markdown"
        read MyApp.Resources, :read_readme
      end

  ### Templated Resource

      resource "user", "https://api.example.com/users/{id}" do
        description "User profile data"
        mimeType "application/json"
        title "User Profile"
        read MyApp.Resources, :read_user
        complete MyApp.Resources, :complete_user_id
      end

  ### Controller Implementation

  #### Read Function (arity 2: conn, params)

  For static resources, params is typically an empty map.
  For templated resources, params contains the template variable values:

      defmodule MyApp.Resources do
        import McpServer.Controller, only: [content: 3]

        def read_user(conn, %{"id" => user_id}) do
          user_data = fetch_user_from_database(user_id)

          %{
            "contents" => [
              content(
                "User " <> user_id,
                "https://api.example.com/users/" <> user_id,
                mimeType: "application/json",
                text: Jason.encode!(user_data)
              )
            ]
          }
        end
      end

  #### Complete Function (arity 3: conn, variable_name, prefix)

  Provides completion suggestions for URI template variables:

      defmodule MyApp.Resources do
        import McpServer.Controller, only: [completion: 2]

        def complete_user_id(conn, "id", prefix) do
          # Fetch matching user IDs from your data source
          matching_ids = search_user_ids(prefix)

          completion(matching_ids, total: 1000, has_more: true)
        end
      end

  ## Generated Functions

  Using `McpServer.Router` generates the following functions in your module:

  - `list_tools/1` - Returns all defined tools with their schemas
  - `call_tool/3` - Executes a tool by name with arguments
  - `prompts_list/1` - Returns all defined prompts
  - `get_prompt/3` - Gets prompt messages for given arguments
  - `complete_prompt/4` - Gets completion suggestions for prompt arguments
  - `list_resources/1` - Returns all static resources
  - `list_templates_resource/1` - Returns all templated resources
  - `read_resource/3` - Reads a resource by name
  - `complete_resource/4` - Gets completion suggestions for resource URIs

  All generated functions require a `McpServer.Conn` as their first parameter.

  ## Validation

  The Router performs compile-time validation:

  - Controller modules must exist
  - Controller functions must be exported with correct arity
  - Tool/prompt/resource names must be unique
  - Field names within a tool must be unique
  - Required fields must be properly defined
  - Resource templates with completion must be valid

  Validation errors are raised as `CompileError` with helpful messages.

  ## Example: Complete Router

      defmodule MyApp.MCP do
        use McpServer.Router

        # Simple echo tool
        tool "echo", "Echoes back the input", MyApp.Tools, :echo do
          input_field("message", "Message to echo", :string, required: true)
          output_field("response", "Echoed message", :string)
        end

        # Tool with hints and validation
        tool "database_query", "Queries the database", MyApp.Tools, :query,
          hints: [:closed_world, :idempotent] do
          input_field("table", "Table name", :string,
            required: true,
            enum: ["users", "posts", "comments"])
          input_field("limit", "Max results", :integer, default: 10)
          output_field("results", "Query results", :array)
        end

        # Greeting prompt
        prompt "greet", "A friendly greeting" do
          argument("name", "Person's name", required: true)
          get MyApp.Prompts, :get_greeting
          complete MyApp.Prompts, :complete_name
        end

        # Static resource
        resource "config", "file:///etc/app/config.json" do
          description "Application configuration"
          mimeType "application/json"
          read MyApp.Resources, :read_config
        end

        # Dynamic resource
        resource "document", "file:///docs/{category}/{id}.md" do
          description "Documentation files"
          mimeType "text/markdown"
          read MyApp.Resources, :read_document
          complete MyApp.Resources, :complete_document_path
        end
      end

  ## See Also

  - `McpServer` - The behaviour implemented by routers
  - `McpServer.Conn` - Connection context structure
  - `McpServer.Controller` - Helper functions for controllers
  - `McpServer.HttpPlug` - HTTP transport for MCP servers
  """

  defmacro __using__(_opts) do
    quote do
      import McpServer.Router, only: [tool: 5, tool: 6, prompt: 3, resource: 2, resource: 3]
      @behaviour McpServer
      @before_compile McpServer.Router
    end
  end

  @doc """
  Same as tool/6 but with no options provided such as title or hints.
  """
  defmacro tool(name, description, controller, function, do: block) do
    define_tool(name, description, controller, function, [], block, __CALLER__)
  end

  @doc """
  Defines a tool

  ## Example
      tool "echo", "Echoes back the input", EchoController, :echo,
        title: "Echo",
        hints: [:read_only, :non_destructive, :idempotent, :closed_world] do
        input_field("message", "The message to echo", :string, required: true)
        output_field("message", "The echoed message", :string)
      end
  """
  defmacro tool(name, description, controller, function, opts, do: block) do
    define_tool(name, description, controller, function, opts, block, __CALLER__)
  end

  @doc """
  Defines a prompt

  ## Example
      prompt "greet", "A friendly greeting prompt that welcomes users" do
        argument("user_name", "The name of the user to greet", required: true)
        get MyApp.MyController, :get_greet_prompt
        complete MyApp.MyController, :complete_greet_prompt
      end
  """
  defmacro prompt(name, description, do: block) do
    define_prompt(name, description, block, __CALLER__)
  end

  @doc """
  Defines a resource with a URI and an optional block to describe metadata and handlers.

  ## Example
      resource "users", "https://example.com/users/{id}" do
        description "List of users"
        mimeType "application/json"
        title "User resource"
        read MyApp.ResourceController, :read_user
        complete MyApp.ResourceController, :complete_user
      end
  """
  defmacro resource(name, uri, do: block) do
    define_resource(name, uri, block, __CALLER__)
  end

  defmacro resource(name, uri) do
    define_resource(name, uri, nil, __CALLER__)
  end

  defp define_tool(name, description, controller, function, opts, block, caller) do
    statements = extract_tools_statements(block, %{name: name, caller: caller})
    tools = Module.get_attribute(caller.module, :tools, %{})

    if Map.has_key?(tools, name) do
      raise CompileError,
        description: "Tool \"#{name}\" is already defined",
        file: caller.file,
        line: caller.line
    end

    # Validate that the controller module is defined and exports the function
    validate_controller_function(controller, function, name, caller)

    tool = %{
      name: name,
      description: description,
      controller: controller,
      function: function,
      statements: statements,
      opts: opts
    }

    Module.put_attribute(caller.module, :tools, Map.put(tools, name, tool))
  end

  defp define_prompt(name, description, block, caller) do
    statements = extract_prompt_statements(block, %{name: name, caller: caller})
    prompts = Module.get_attribute(caller.module, :prompts, %{})

    if Map.has_key?(prompts, name) do
      raise CompileError,
        description: "Prompt \"#{name}\" is already defined",
        file: caller.file,
        line: caller.line
    end

    # Validate that both get and complete controller functions are defined
    validate_prompt_functions(statements, name, caller)

    prompt = %{
      name: name,
      description: description,
      statements: statements
    }

    Module.put_attribute(caller.module, :prompts, Map.put(prompts, name, prompt))
  end

  defp define_resource(name, uri_quoted, block, caller) do
    resources = Module.get_attribute(caller.module, :resources, %{})

    if Map.has_key?(resources, name) do
      raise CompileError,
        description: "Resource \"#{name}\" is already defined",
        file: caller.file,
        line: caller.line
    end

    statements =
      case block do
        nil ->
          %{
            description: nil,
            mimeType: nil,
            title: nil,
            read_controller: nil,
            read_function: nil,
            complete_controller: nil,
            complete_function: nil
          }

        _ ->
          extract_resource_statements(block, %{name: name, caller: caller})
      end

    # Evaluate URI now (must be a binary)
    uri =
      try do
        {v, _} = Code.eval_quoted(uri_quoted, [], caller)
        v
      catch
        _, _ ->
          raise CompileError,
            description: "Invalid URI for resource \"#{name}\": #{inspect(uri_quoted)}",
            file: caller.file,
            line: caller.line
      end

    unless is_binary(uri) do
      raise CompileError,
        description: "URI for resource \"#{name}\" must be a string",
        file: caller.file,
        line: caller.line
    end

    is_template = String.contains?(uri, "{")

    # Read handler is required
    unless statements.read_controller && statements.read_function do
      raise CompileError,
        description:
          "Resource \"#{name}\" must define a read handler using `read Module, :function`",
        file: caller.file,
        line: caller.line
    end

    # Evaluate and validate read controller/function
    read_controller_module =
      try do
        {m, _} = Code.eval_quoted(statements.read_controller, [], caller)
        m
      catch
        _, _ ->
          raise CompileError,
            description:
              "Invalid read controller for resource \"#{name}\": #{inspect(statements.read_controller)}",
            file: caller.file,
            line: caller.line
      end

    unless match?({:module, _}, Code.ensure_compiled(read_controller_module)) do
      raise CompileError,
        description:
          "Read controller module #{inspect(read_controller_module)} for resource \"#{name}\" is not defined",
        file: caller.file,
        line: caller.line
    end

    unless function_exported?(read_controller_module, statements.read_function, 2) do
      raise CompileError,
        description:
          "Function #{inspect(read_controller_module)}.#{statements.read_function}/2 for resource \"#{name}\" read is not exported",
        file: caller.file,
        line: caller.line
    end

    # If complete provided, ensure resource is a template and function arity is 2
    if statements.complete_controller && statements.complete_function do
      unless is_template do
        raise CompileError,
          description: "Complete handler provided for non-template resource \"#{name}\"",
          file: caller.file,
          line: caller.line
      end

      complete_controller_module =
        try do
          {m, _} = Code.eval_quoted(statements.complete_controller, [], caller)
          m
        catch
          _, _ ->
            raise CompileError,
              description:
                "Invalid complete controller for resource \"#{name}\": #{inspect(statements.complete_controller)}",
              file: caller.file,
              line: caller.line
        end

      unless match?({:module, _}, Code.ensure_compiled(complete_controller_module)) do
        raise CompileError,
          description:
            "Complete controller module #{inspect(complete_controller_module)} for resource \"#{name}\" is not defined",
          file: caller.file,
          line: caller.line
      end

      unless function_exported?(complete_controller_module, statements.complete_function, 3) do
        raise CompileError,
          description:
            "Function #{inspect(complete_controller_module)}.#{statements.complete_function}/3 for resource \"#{name}\" complete is not exported",
          file: caller.file,
          line: caller.line
      end
    end

    resource = %{
      name: name,
      uri: uri,
      description: statements.description,
      mimeType: statements.mimeType,
      title: statements.title,
      read_controller: read_controller_module,
      read_function: statements.read_function,
      complete_controller:
        if(statements.complete_controller,
          do: elem(Code.eval_quoted(statements.complete_controller, [], caller), 0),
          else: nil
        ),
      complete_function: statements.complete_function
    }

    Module.put_attribute(caller.module, :resources, Map.put(resources, name, resource))
  end

  defp extract_resource_statements(quoted, ctx) do
    do_extract_resource_statements(
      %{
        description: nil,
        mimeType: nil,
        title: nil,
        read_controller: nil,
        read_function: nil,
        complete_controller: nil,
        complete_function: nil
      },
      quoted,
      ctx
    )
  end

  defp do_extract_resource_statements(statements, {:__block__, _, content}, ctx) do
    content
    |> Enum.reduce(statements, fn block, statements ->
      do_extract_resource_statements(statements, block, ctx)
    end)
  end

  defp do_extract_resource_statements(statements, {:description, _, [desc]}, _ctx) do
    Map.put(statements, :description, desc)
  end

  defp do_extract_resource_statements(statements, {:mimeType, _, [mt]}, _ctx) do
    Map.put(statements, :mimeType, mt)
  end

  defp do_extract_resource_statements(statements, {:title, _, [t]}, _ctx) do
    Map.put(statements, :title, t)
  end

  defp do_extract_resource_statements(statements, {:read, _, [controller, function]}, _ctx) do
    statements
    |> Map.put(:read_controller, controller)
    |> Map.put(:read_function, function)
  end

  defp do_extract_resource_statements(statements, {:complete, _, [controller, function]}, _ctx) do
    statements
    |> Map.put(:complete_controller, controller)
    |> Map.put(:complete_function, function)
  end

  defp do_extract_resource_statements(_statements, other, %{caller: caller}) do
    raise %SyntaxError{
      description: "Unexpected statement in resource definition: #{Macro.to_string(other)}",
      file: caller.file,
      line: caller.line
    }
  end

  defp validate_controller_function(controller, function, tool_name, caller) do
    # Convert the controller from AST to atom if needed
    controller_module =
      try do
        {controller_module, _} = Code.eval_quoted(controller, [], caller)
        controller_module
      catch
        _, _ ->
          raise CompileError,
            description:
              "Invalid controller specification for tool \"#{tool_name}\": #{inspect(controller)}",
            file: caller.file,
            line: caller.line
      end

    # Check if the controller module exists
    unless match?({:module, _}, Code.ensure_compiled(controller_module)) do
      raise CompileError,
        description:
          "Controller module #{inspect(controller_module)} for tool \"#{tool_name}\" is not defined",
        file: caller.file,
        line: caller.line
    end

    # Check if the function exists with arity 2 (conn, args)
    unless function_exported?(controller_module, function, 2) do
      raise CompileError,
        description:
          "Function #{inspect(controller_module)}.#{function}/2 for tool \"#{tool_name}\" is not exported",
        file: caller.file,
        line: caller.line
    end
  end

  defp validate_prompt_functions(statements, prompt_name, caller) do
    get_controller = statements[:get_controller]
    get_function = statements[:get_function]
    complete_controller = statements[:complete_controller]
    complete_function = statements[:complete_function]

    # Convert controllers from AST to atoms if needed
    get_controller_module =
      try do
        {controller_module, _} = Code.eval_quoted(get_controller, [], caller)
        controller_module
      catch
        _, _ ->
          raise CompileError,
            description:
              "Invalid get controller specification for prompt \"#{prompt_name}\": #{inspect(get_controller)}",
            file: caller.file,
            line: caller.line
      end

    complete_controller_module =
      try do
        {controller_module, _} = Code.eval_quoted(complete_controller, [], caller)
        controller_module
      catch
        _, _ ->
          raise CompileError,
            description:
              "Invalid complete controller specification for prompt \"#{prompt_name}\": #{inspect(complete_controller)}",
            file: caller.file,
            line: caller.line
      end

    # Check if the controller modules exist
    unless match?({:module, _}, Code.ensure_compiled(get_controller_module)) do
      raise CompileError,
        description:
          "Get controller module #{inspect(get_controller_module)} for prompt \"#{prompt_name}\" is not defined",
        file: caller.file,
        line: caller.line
    end

    unless match?({:module, _}, Code.ensure_compiled(complete_controller_module)) do
      raise CompileError,
        description:
          "Complete controller module #{inspect(complete_controller_module)} for prompt \"#{prompt_name}\" is not defined",
        file: caller.file,
        line: caller.line
    end

    # Validate get function - should have arity 2 (conn, args)
    unless function_exported?(get_controller_module, get_function, 2) do
      raise CompileError,
        description:
          "Function #{inspect(get_controller_module)}.#{get_function}/2 for prompt \"#{prompt_name}\" get is not exported",
        file: caller.file,
        line: caller.line
    end

    # Validate complete function - should have arity 3 (conn, argument_name, prefix)
    unless function_exported?(complete_controller_module, complete_function, 3) do
      raise CompileError,
        description:
          "Function #{inspect(complete_controller_module)}.#{complete_function}/3 for prompt \"#{prompt_name}\" complete is not exported",
        file: caller.file,
        line: caller.line
    end
  end

  defp extract_prompt_statements(quoted, ctx) do
    do_extract_prompt_statements(%{arguments: %{}}, quoted, ctx)
  end

  defp do_extract_prompt_statements(statements, {:__block__, _, content}, ctx) do
    content
    |> Enum.reduce(statements, fn block, statements ->
      do_extract_prompt_statements(statements, block, ctx)
    end)
  end

  defp do_extract_prompt_statements(
         statements,
         {:argument, _, args},
         ctx
       ) do
    [name, description, opts] = parse_argument_args(args)

    arguments = Map.get(statements, :arguments, %{})

    if Map.has_key?(arguments, name) do
      raise %SyntaxError{
        description:
          "argument #{Macro.to_string(name)} duplicated in prompt #{Macro.to_string(ctx.name)}",
        file: ctx.caller.file,
        line: ctx.caller.line
      }
    end

    new_arguments =
      Map.put(arguments, name, %{description: description, opts: opts})

    Map.put(statements, :arguments, new_arguments)
  end

  defp do_extract_prompt_statements(
         statements,
         {:get, _, [controller, function]},
         _ctx
       ) do
    statements
    |> Map.put(:get_controller, controller)
    |> Map.put(:get_function, function)
  end

  defp do_extract_prompt_statements(
         statements,
         {:complete, _, [controller, function]},
         _ctx
       ) do
    statements
    |> Map.put(:complete_controller, controller)
    |> Map.put(:complete_function, function)
  end

  defp do_extract_prompt_statements(_statements, other, %{caller: caller}) do
    raise %SyntaxError{
      description: "Unexpected statement in prompt definition: #{Macro.to_string(other)}",
      file: caller.file,
      line: caller.line
    }
  end

  defp parse_argument_args(args) do
    case args do
      [name, description, opts] ->
        [name, description, opts]

      [name, description] ->
        [name, description, []]

      args ->
        reason = """
        Did you mean:
         - argument/2
         - argument/3
        """

        arity = length(args)

        raise %UndefinedFunctionError{
          module: __MODULE__,
          function: :argument,
          arity: arity,
          reason: reason
        }
    end
  end

  defp extract_tools_statements(quoted, ctx) do
    do_extract_tools_statements(%{input_fields: %{}, output_fields: %{}}, quoted, ctx)
  end

  defp do_extract_tools_statements(statements, {:__block__, _, content}, ctx) do
    content
    |> Enum.reduce(statements, fn block, statements ->
      do_extract_tools_statements(statements, block, ctx)
    end)
  end

  defp do_extract_tools_statements(
         statements,
         {:input_field, _, args},
         ctx
       ) do
    [name, description, type, opts] = parse_field_args(:input_field, args)

    input_fields = Map.get(statements, :input_fields, %{})

    if Map.has_key?(input_fields, name) do
      raise %SyntaxError{
        description:
          "input_field #{Macro.to_string(name)} duplicated in tool #{Macro.to_string(ctx.name)}",
        file: ctx.caller.file,
        line: ctx.caller.line
      }
    end

    new_input_fields =
      Map.put(input_fields, name, %{description: description, type: type, opts: opts})

    Map.put(statements, :input_fields, new_input_fields)
  end

  defp do_extract_tools_statements(
         statements,
         {:output_field, _, args},
         ctx
       ) do
    [name, description, type, opts] = parse_field_args(:output_field, args)
    output_fields = Map.get(statements, :output_fields, %{})

    if Map.has_key?(output_fields, name) do
      raise %SyntaxError{
        description:
          "output_field #{Macro.to_string(name)} duplicated in tool #{Macro.to_string(ctx.name)}",
        file: ctx.caller.file,
        line: ctx.caller.line
      }
    end

    new_output_fields =
      Map.put(output_fields, name, %{description: description, type: type, opts: opts})

    Map.put(statements, :output_fields, new_output_fields)
  end

  defp do_extract_tools_statements(_statements, other, %{caller: caller}) do
    raise %SyntaxError{
      description: "Unexpected statement in tool definition: #{Macro.to_string(other)}",
      file: caller.file,
      line: caller.line
    }
  end

  defp parse_field_args(function, args) do
    case args do
      [name, description, type, opts] ->
        [name, description, type, opts]

      [name, description, type] ->
        [name, description, type, []]

      args ->
        reason = """
        Did you mean:
         - #{function}/3
         - #{function}/4
        """

        arity = length(args)

        raise %UndefinedFunctionError{
          module: __MODULE__,
          function: function,
          arity: arity,
          reason: reason
        }
    end
  end

  defmacro __before_compile__(env) do
    tools =
      Module.get_attribute(env.module, :tools, %{})
      |> Map.values()

    prompts =
      Module.get_attribute(env.module, :prompts, %{})
      |> Map.values()

    resources =
      Module.get_attribute(env.module, :resources, %{})
      |> Map.values()

    if tools == [] and prompts == [] and resources == [] do
      raise CompileError,
        description: "No tools or prompts defined in #{inspect(env.module)}",
        file: env.file,
        line: env.line
    end

    default_call_tool_clause =
      quote do
        def call_tool(_conn, tool_name, _) do
          raise ArgumentError, "Tool '#{tool_name}' not found"
        end
      end

    call_tool_clauses =
      tools
      |> Enum.map(fn tool ->
        quote do
          def call_tool(conn, unquote(tool.name), args) do
            case McpServer.Router.check_tool_args(
                   args,
                   unquote(tool.name),
                   unquote(Macro.escape(tool.statements.input_fields))
                 ) do
              {:error, e} ->
                {:error, e}

              :ok ->
                unquote(tool.controller).unquote(tool.function)(conn, args)
            end
          end
        end
      end)
      |> Enum.concat([default_call_tool_clause])

    default_get_prompt_clause =
      quote do
        def get_prompt(_conn, prompt_name, _) do
          raise ArgumentError, "Prompt '#{prompt_name}' not found"
        end
      end

    get_prompt_clauses =
      prompts
      |> Enum.map(fn prompt ->
        quote do
          def get_prompt(conn, unquote(prompt.name), args) do
            case McpServer.Router.check_prompt_args(
                   args,
                   unquote(prompt.name),
                   unquote(Macro.escape(prompt.statements.arguments))
                 ) do
              {:error, e} ->
                {:error, e}

              :ok ->
                unquote(prompt.statements.get_controller).unquote(prompt.statements.get_function)(
                  conn,
                  args
                )
            end
          end
        end
      end)
      |> Enum.concat([default_get_prompt_clause])

    default_complete_prompt_clause =
      quote do
        def complete_prompt(_conn, prompt_name, _argument_name, _prefix) do
          raise ArgumentError, "Prompt '#{prompt_name}' not found"
        end
      end

    complete_prompt_clauses =
      prompts
      |> Enum.map(fn prompt ->
        quote do
          def complete_prompt(conn, unquote(prompt.name), argument_name, prefix) do
            # Validate that the argument exists for this prompt
            arguments = unquote(Macro.escape(prompt.statements.arguments))

            unless Map.has_key?(arguments, argument_name) do
              raise ArgumentError,
                    "Argument '#{argument_name}' not found for prompt '#{unquote(prompt.name)}'"
            end

            unquote(prompt.statements.complete_controller).unquote(
              prompt.statements.complete_function
            )(
              conn,
              argument_name,
              prefix
            )
          end
        end
      end)
      |> Enum.concat([default_complete_prompt_clause])

    # Resources
    default_read_resource_clause =
      quote do
        def read_resource(_conn, resource_name, _opts) do
          raise ArgumentError, "Resource '#{resource_name}' not found"
        end
      end

    read_resource_clauses =
      resources
      |> Enum.map(fn resource ->
        quote do
          def read_resource(conn, unquote(resource.name), opts) do
            unquote(resource.read_controller).unquote(resource.read_function)(conn, opts)
          end
        end
      end)
      |> Enum.concat([default_read_resource_clause])

    default_complete_resource_clause =
      quote do
        def complete_resource(_conn, resource_name, _argument_name, _prefix) do
          raise ArgumentError, "Resource '#{resource_name}' not found"
        end
      end

    complete_resource_clauses =
      resources
      |> Enum.filter(fn resource -> resource.complete_controller != nil end)
      |> Enum.map(fn resource ->
        quote do
          def complete_resource(conn, unquote(resource.name), argument_name, prefix) do
            unquote(resource.complete_controller).unquote(resource.complete_function)(
              conn,
              argument_name,
              prefix
            )
          end
        end
      end)
      |> Enum.concat([default_complete_resource_clause])

    resources_list_static_clause =
      quote do
        def list_resources(_conn) do
          unquote(resources_list_static(Module.get_attribute(env.module, :resources, %{})))
        end
      end

    resources_list_templates_clause =
      quote do
        def list_templates_resource(_conn) do
          unquote(resources_list_templates(Module.get_attribute(env.module, :resources, %{})))
          |> Enum.map(fn t ->
            uri = Map.get(t, "uri")

            t
            |> Map.delete("uri")
            |> Map.put("uriTemplate", uri)
          end)
        end
      end

    quote do
      def tools_debug do
        unquote(Macro.escape(Module.get_attribute(env.module, :tools, %{})))
      end

      def list_tools(_conn) do
        unquote(list_tools(Module.get_attribute(env.module, :tools, %{})))
      end

      def prompts_debug do
        unquote(Macro.escape(Module.get_attribute(env.module, :prompts, %{})))
      end

      def prompts_list(_conn) do
        unquote(prompts_list(Module.get_attribute(env.module, :prompts, %{})))
      end

      def resources_debug do
        unquote(Macro.escape(Module.get_attribute(env.module, :resources, %{})))
      end

      unquote(resources_list_static_clause)
      unquote(resources_list_templates_clause)

      # read_resource clauses are generated below (including default)

      unquote(call_tool_clauses)
      unquote(get_prompt_clauses)
      unquote(complete_prompt_clauses)
      unquote(read_resource_clauses)
      unquote(complete_resource_clauses)
    end
  end

  @doc false
  # TODO put in a dedicated module
  def format_schema(fields) do
    required_fields =
      fields
      |> Enum.filter(fn {_, %{opts: opts}} ->
        Keyword.get(opts, :required, false)
      end)
      |> Enum.map(fn {name, _} -> name end)

    properties =
      fields
      |> Map.new(fn {name, field} ->
        {name, format_field(field)}
      end)

    %{
      "type" => "object",
      "properties" => properties,
      "required" => required_fields
    }
  end

  @doc false
  # TODO put in a dedicated module
  def format_field(field) do
    enum = field.opts[:enum]

    %{
      "type" => "#{field.type}",
      "description" => field.description,
      "enum" => enum,
      "default" => field.opts[:default]
    }
    |> Map.reject(fn {_, v} -> is_nil(v) end)
  end

  @doc false
  # TODO put in a dedicated module
  def check_tool_args(args, tool_name, input_fields) do
    # Validate arguments
    required_fields =
      input_fields
      |> Enum.filter(fn {_k, v} -> Keyword.get(v.opts, :required, false) end)
      |> Enum.map(fn {k, _v} -> k end)

    Enum.filter(required_fields, fn k -> !Map.has_key?(args, k) end)
    |> case do
      [] ->
        :ok

      missings ->
        {:error, "Missing required arguments for tool '#{tool_name}': #{inspect(missings)}"}
    end
  end

  @doc false
  # TODO put in a dedicated module
  def check_prompt_args(args, prompt_name, arguments) do
    # Validate arguments
    required_arguments =
      arguments
      |> Enum.filter(fn {_k, v} -> Keyword.get(v.opts, :required, false) end)
      |> Enum.map(fn {k, _v} -> k end)

    Enum.filter(required_arguments, fn k -> !Map.has_key?(args, k) end)
    |> case do
      [] ->
        :ok

      missings ->
        {:error, "Missing required arguments for prompt '#{prompt_name}': #{inspect(missings)}"}
    end
  end

  defp list_tools(tools) do
    tools
    |> Enum.map(fn {name, tool} ->
      quote do
        hints = Keyword.get(unquote(tool.opts), :hints, [])
        title = Keyword.get(unquote(tool.opts), :title, unquote(name))

        input_schema =
          McpServer.Router.format_schema(unquote(input_fields(tool.statements.input_fields)))

        %{
          "name" => unquote(name),
          "description" => unquote(tool.description),
          "inputSchema" => input_schema,
          "annotations" => %{
            "title" => title,
            "readOnlyHint" => :read_only in hints,
            "destructiveHint" => :non_destructive not in hints,
            "idempotentHint" => :idempotent in hints,
            "openWorldHint" => :closed_world not in hints
          }
        }
      end
    end)
  end

  defp input_fields(fields) do
    fields
    |> Enum.map(fn {name, field} ->
      quote do
        {
          unquote(name),
          %{
            description: unquote(field.description),
            type: unquote(field.type),
            opts: unquote(field.opts)
          }
        }
      end
    end)
  end

  defp prompts_list(prompts) do
    prompts
    |> Enum.map(fn {name, prompt} ->
      quote do
        arguments = unquote(prompt_arguments(prompt.statements.arguments))

        %{
          "name" => unquote(name),
          "description" => unquote(prompt.description),
          "arguments" => arguments
        }
      end
    end)
  end

  defp resources_list_static(resources) do
    resources
    |> Enum.filter(fn {_name, resource} ->
      uri = resource.uri
      is_binary(uri) and McpServer.URITemplate.new(uri).vars == []
    end)
    |> Enum.map(fn {name, resource} ->
      quote do
        base = %{
          "name" => unquote(name),
          "uri" => unquote(resource.uri)
        }

        base =
          if unquote(resource.description) != nil,
            do: Map.put(base, "description", unquote(resource.description)),
            else: base

        base =
          if unquote(resource.title) != nil,
            do: Map.put(base, "title", unquote(resource.title)),
            else: base

        base =
          if unquote(resource.mimeType) != nil,
            do: Map.put(base, "mimeType", unquote(resource.mimeType)),
            else: base

        base
      end
    end)
  end

  defp resources_list_templates(resources) do
    resources
    |> Enum.filter(fn {_name, resource} ->
      uri = resource.uri
      is_binary(uri) and McpServer.URITemplate.new(uri).vars != []
    end)
    |> Enum.map(fn {name, resource} ->
      quote do
        base = %{
          "name" => unquote(name),
          "uri" => unquote(resource.uri)
        }

        base =
          if unquote(resource.description) != nil,
            do: Map.put(base, "description", unquote(resource.description)),
            else: base

        base =
          if unquote(resource.title) != nil,
            do: Map.put(base, "title", unquote(resource.title)),
            else: base

        base =
          if unquote(resource.mimeType) != nil,
            do: Map.put(base, "mimeType", unquote(resource.mimeType)),
            else: base

        base
      end
    end)
  end

  defp prompt_arguments(arguments) do
    arguments
    |> Enum.map(fn {name, arg} ->
      quote do
        %{
          "name" => unquote(name),
          "description" => unquote(arg.description),
          "required" => unquote(Keyword.get(arg.opts, :required, false))
        }
      end
    end)
  end
end
