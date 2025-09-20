defmodule McpServer.Router do
  @moduledoc """
  A DSL to define a router for the Model Context Protocol (MCP) server.
  """

  defmacro __using__(_opts) do
    quote do
      import McpServer.Router, only: [tool: 5, tool: 6, prompt: 3, resource: 5]
      @before_compile McpServer.Router
    end
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
  defmacro tool(name, description, controller, function, do: block) do
    define_tool(name, description, controller, function, [], block, __CALLER__)
  end

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
  Defines a resource

  ## Example
      resource "users", "List of users", MyApp.ResourceController, :read_user, uri: "https://example.com/users/{id}" do
        # optional block for future statements
      end
  """
  defmacro resource(name, description, controller, function, do: block) do
    define_resource(name, description, controller, function, [], block, __CALLER__)
  end

  defmacro resource(name, description, controller, function, opts) do
    define_resource(name, description, controller, function, opts, nil, __CALLER__)
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

  defp define_resource(name, description, controller, function, opts, _block, caller) do
    resources = Module.get_attribute(caller.module, :resources, %{})

    if Map.has_key?(resources, name) do
      raise CompileError,
        description: "Resource \"#{name}\" is already defined",
        file: caller.file,
        line: caller.line
    end

    # Validate controller and function exist (read function should have arity 1)
    validate_controller_function(controller, function, name, caller)

    resource = %{
      name: name,
      description: description,
      controller: controller,
      function: function,
      opts: opts
    }

    Module.put_attribute(caller.module, :resources, Map.put(resources, name, resource))
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

    # Check if the function exists with arity 1
    unless function_exported?(controller_module, function, 1) do
      raise CompileError,
        description:
          "Function #{inspect(controller_module)}.#{function}/1 for tool \"#{tool_name}\" is not exported",
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

    # Validate get function - should have arity 1
    unless function_exported?(get_controller_module, get_function, 1) do
      raise CompileError,
        description:
          "Function #{inspect(get_controller_module)}.#{get_function}/1 for prompt \"#{prompt_name}\" get is not exported",
        file: caller.file,
        line: caller.line
    end

    # Validate complete function - should have arity 2 (argument_name, prefix)
    unless function_exported?(complete_controller_module, complete_function, 2) do
      raise CompileError,
        description:
          "Function #{inspect(complete_controller_module)}.#{complete_function}/2 for prompt \"#{prompt_name}\" complete is not exported",
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

    default_tools_call_clause =
      quote do
        def tools_call(tool_name, _) do
          raise ArgumentError, "Tool '#{tool_name}' not found"
        end
      end

    tools_call_clauses =
      tools
      |> Enum.map(fn tool ->
        quote do
          def tools_call(unquote(tool.name), args) do
            case McpServer.Router.check_tool_args(
                   args,
                   unquote(tool.name),
                   unquote(Macro.escape(tool.statements.input_fields))
                 ) do
              {:error, e} ->
                {:error, e}

              :ok ->
                unquote(tool.controller).unquote(tool.function)(args)
            end
          end
        end
      end)
      |> Enum.concat([default_tools_call_clause])

    default_prompts_get_clause =
      quote do
        def prompts_get(prompt_name, _) do
          raise ArgumentError, "Prompt '#{prompt_name}' not found"
        end
      end

    prompts_get_clauses =
      prompts
      |> Enum.map(fn prompt ->
        quote do
          def prompts_get(unquote(prompt.name), args) do
            case McpServer.Router.check_prompt_args(
                   args,
                   unquote(prompt.name),
                   unquote(Macro.escape(prompt.statements.arguments))
                 ) do
              {:error, e} ->
                {:error, e}

              :ok ->
                unquote(prompt.statements.get_controller).unquote(prompt.statements.get_function)(
                  args
                )
            end
          end
        end
      end)
      |> Enum.concat([default_prompts_get_clause])

    default_prompts_complete_clause =
      quote do
        def prompts_complete(prompt_name, _argument_name, _prefix) do
          raise ArgumentError, "Prompt '#{prompt_name}' not found"
        end
      end

    prompts_complete_clauses =
      prompts
      |> Enum.map(fn prompt ->
        quote do
          def prompts_complete(unquote(prompt.name), argument_name, prefix) do
            # Validate that the argument exists for this prompt
            arguments = unquote(Macro.escape(prompt.statements.arguments))

            unless Map.has_key?(arguments, argument_name) do
              raise ArgumentError,
                    "Argument '#{argument_name}' not found for prompt '#{unquote(prompt.name)}'"
            end

            unquote(prompt.statements.complete_controller).unquote(
              prompt.statements.complete_function
            )(
              argument_name,
              prefix
            )
          end
        end
      end)
      |> Enum.concat([default_prompts_complete_clause])

    # Resources
    default_resources_read_clause =
      quote do
        def resources_read(resource_name, _opts) do
          raise ArgumentError, "Resource '#{resource_name}' not found"
        end
      end

    resources_read_clauses =
      resources
      |> Enum.map(fn resource ->
        quote do
          def resources_read(unquote(resource.name), opts) do
            unquote(resource.controller).unquote(resource.function)(opts)
          end
        end
      end)
      |> Enum.concat([default_resources_read_clause])

    resources_list_static_clause =
      quote do
        def list_resource do
          unquote(resources_list_static(Module.get_attribute(env.module, :resources, %{})))
        end
      end

    resources_list_templates_clause =
      quote do
        def list_templates_resource do
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

      def tools_list do
        unquote(tools_list(Module.get_attribute(env.module, :tools, %{})))
      end

      def prompts_debug do
        unquote(Macro.escape(Module.get_attribute(env.module, :prompts, %{})))
      end

      def prompts_list do
        unquote(prompts_list(Module.get_attribute(env.module, :prompts, %{})))
      end

      def resources_debug do
        unquote(Macro.escape(Module.get_attribute(env.module, :resources, %{})))
      end

      unquote(resources_list_static_clause)
      unquote(resources_list_templates_clause)

      # resources_read clauses are generated below (including default)

      unquote(tools_call_clauses)
      unquote(prompts_get_clauses)
      unquote(prompts_complete_clauses)
      unquote(resources_read_clauses)
    end
  end

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

  defp tools_list(tools) do
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
      uri = Keyword.get(resource.opts, :uri)
      is_binary(uri) and not String.contains?(uri, "{")
    end)
    |> Enum.map(fn {name, resource} ->
      quote do
        %{
          "name" => unquote(name),
          "description" => unquote(resource.description),
          "uri" => Keyword.get(unquote(resource.opts), :uri)
        }
      end
    end)
  end

  defp resources_list_templates(resources) do
    resources
    |> Enum.filter(fn {_name, resource} ->
      uri = Keyword.get(resource.opts, :uri)
      is_binary(uri) and String.contains?(uri, "{")
    end)
    |> Enum.map(fn {name, resource} ->
      quote do
        %{
          "name" => unquote(name),
          "description" => unquote(resource.description),
          "uri" => Keyword.get(unquote(resource.opts), :uri)
        }
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
