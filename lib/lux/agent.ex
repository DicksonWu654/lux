defmodule Lux.Agent do
  @moduledoc """
  A Agent defines an autonomous agent's capabilities, behaviors and goals.
  The actual execution and supervision is handled by the Lux runtime.

  Agents can be configured with different templates that provide specialized behaviors:
  - :company_agent - Adds company-specific signal handling
  - (other templates to be added)

  ## Example
      defmodule MyCompanyAgent do
        use Lux.Agent,
          template: :company_agent,
          template_opts: %{
            llm_config: %{temperature: 0.7}
          } do

          def init(opts) do
            {:ok, opts}
          end

          # Can override template functions if needed
          def handle_task_assignment(signal, context) do
            # Custom implementation
          end
        end
      end
  """

  @behaviour Access

  alias Lux.LLM

  require Logger

  @type scheduled_beam :: {module(), String.t(), keyword()}
  @type collaboration_protocol :: :ask | :tell | :delegate | :request_review
  @type memory_config :: %{
          backend: module(),
          name: atom() | nil
        }

  # {module, interval_ms, input, opts}
  @type scheduled_action :: {module(), pos_integer(), map(), map()}
  @type signal_handler :: {module(), module()}

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          description: String.t(),
          goal: String.t(),
          module: module(),
          prisms: [Lux.Prism.t()],
          beams: [Lux.Beam.t()],
          lenses: [Lux.Lens.t()],
          accepts_signals: [Lux.SignalSchema.t()],
          llm_config: map(),
          memory_config: memory_config() | nil,
          memory_pid: pid() | nil,
          scheduled_actions: [scheduled_action()],
          signal_handlers: [signal_handler()]
        }

  defstruct id: nil,
            name: "",
            description: "",
            goal: "",
            module: nil,
            prisms: [],
            beams: [],
            lenses: [],
            accepts_signals: [],
            memory_config: nil,
            memory_pid: nil,
            scheduled_actions: [],
            signal_handlers: [],
            llm_config: %{
              provider: :openai,
              model: "gpt-4",
              temperature: 0.7
              # max_tokens: 1000
            }

  @callback chat(t(), message :: String.t(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Lux.Agent

      use GenServer

      alias Lux.Agent

      require Logger

      Module.register_attribute(__MODULE__, :signal_handler_functions, accumulate: true)
      Module.register_attribute(__MODULE__, :template_opts, accumulate: false)

      @template_opts %{}

      # First evaluate the user's block if provided
      unquote(opts[:do])

      @default_values %{
        module: __MODULE__
      }

      # @signal_handler_functions =
      #   for {schema, handler} <- Keyword.get(opts, :signal_handlers, []) do
      #     quote do
      #       @impl Lux.Agent
      #       def handle_signal(agent, %{schema_id: schema_id} = signal)
      #           when schema_id == unquote(schema) do
      #         module = unquote(handler)

      #         cond do
      #           # is it a prism?
      #           function_exported?(module, :handler, 2) ->
      #             module.handler(signal, agent)

      #           # is it a beam?
      #           function_exported?(module, :run, 2) ->
      #             module.run(signal, agent)

      #           # is it a lens?
      #           function_exported?(module, :focus, 2) ->
      #             module.focus(signal, agent)
      #         end
      #       end
      #     end
      #   end

      dbg(@signal_handler_functions)

      # Then inject template-specific functions
      case unquote(opts[:template]) do
        :company_agent ->
          # Inject company signal handlers and other functions
          use Lux.Agent.Companies.SignalHandler

          # Store template options in module attribute at compile time
          @template_opts (
                           opts = unquote(opts[:template_opts])

                           cond do
                             is_nil(opts) -> %{}
                             is_list(opts) -> Map.new(opts)
                             is_map(opts) -> opts
                             true -> %{}
                           end
                         )

        _ ->
          @template_opts %{}
      end

      dbg(@signal_handler_functions)

      # Accumulate signal handlers passed by the user
      for {schema, handler} <-
            unquote(opts) |> Keyword.get(:signal_handlers, []) |> Enum.reverse() do
        @signal_handler_functions {schema, handler}
      end

      dbg(@signal_handler_functions)

      @impl Lux.Agent

      @agent %Agent{
        id: Keyword.get(unquote(opts), :id, Lux.UUID.generate()),
        name: Keyword.get(unquote(opts), :name, "Anonymous Agent"),
        description: Keyword.get(unquote(opts), :description, ""),
        goal: Keyword.get(unquote(opts), :goal, ""),
        module: Keyword.get(unquote(opts), :module, __MODULE__),
        prisms: Keyword.get(unquote(opts), :prisms, []),
        beams: Keyword.get(unquote(opts), :beams, []),
        lenses: Keyword.get(unquote(opts), :lenses, []),
        accepts_signals: Keyword.get(unquote(opts), :accepts_signals, []),
        memory_config: Keyword.get(unquote(opts), :memory_config),
        memory_pid: nil,
        scheduled_actions: Keyword.get(unquote(opts), :scheduled_actions, []),
        signal_handlers: Enum.uniq_by(@signal_handler_functions, fn {schema, _} -> schema end),
        llm_config: Keyword.get(unquote(opts), :llm_config, %{})
      }

      dbg(@signal_handler_functions)

      @impl Agent
      def chat(agent, message, opts \\ []) do
        Agent.chat(agent, message, opts)
      end

      # unquote(signal_handler_functions)

      # for {schema, handler} <- @agent.signal_handlers do
      #   @impl Lux.Agent
      #   def handle_signal(agent, %{schema_id: schema_id} = signal) when schema_id == unqoute(schema) do
      #     cond do
      #       # is it a prism?
      #       function_exported?(handler, :handler, 2) ->
      #         handler.handler(signal, agent)

      #       # is it a beam?
      #       function_exported?(handler, :run, 2) ->
      #         handler.run(signal, agent)

      #       # is it a lens?
      #       function_exported?(handler, :focus, 2) ->
      #         handler.focus(signal, agent)
      #     end
      #   end
      # end

      handler_functions =
        for {schema, handler} <- @agent.signal_handlers do
          case Lux.Agent.get_handler_type(handler) do
            :prism ->
              quote do
                def handle_signal(agent, %{schema_id: schema_id} = signal)
                    when schema_id == schema do
                  handler.handler(agent, signal)
                end
              end

            :beam ->
              quote do
                def handle_signal(agent, %{schema_id: schema_id} = signal)
                    when schema_id == schema do
                  handler.run(agent, signal)
                end
              end

            :lens ->
              quote do
                def handle_signal(agent, %{schema_id: schema_id} = signal)
                    when schema_id == schema do
                  handler.focus(agent, signal)
                end
              end

            :module_function ->
              quote do
                def handle_signal(agent, %{schema_id: schema_id} = signal)
                    when schema_id == schema do
                  {module, function} = handler

                  apply(module, function, [agent, signal])
                end
              end

            :unknown ->
              raise "Unknown handler type: #{inspect(handler)}"
          end
        end

      dbg(handler_functions)

      def handle_signal(_agent, _signal), do: :ignore

      # GenServer Client API
      def start_link(attrs \\ %{}) do
        # Convert keyword list to map if needed
        attrs = Map.new(attrs)
        llm_config = attrs |> Map.get(:llm_config, %{}) |> Map.new()
        updated_llm_config = Map.merge(@agent.llm_config, llm_config)

        agent = struct(@agent, Map.put(attrs, :llm_config, updated_llm_config))

        GenServer.start_link(__MODULE__, agent, name: get_name(agent))
      end

      def child_spec(opts) do
        %{
          id: {__MODULE__, opts[:name] || :default},
          start: {__MODULE__, :start_link, [opts]},
          type: :worker,
          restart: :permanent,
          shutdown: 60_000
        }
      end

      def view, do: @agent

      def get_state(pid), do: :sys.get_state(pid)

      defp get_name(%{name: name}) when is_binary(name), do: String.to_atom(name)
      defp get_name(%{name: nil}), do: __MODULE__
      defp get_name(%{name: name}) when is_atom(name), do: name

      def send_message(pid, message, opts \\ []) do
        timeout = opts[:timeout] || 120_000
        GenServer.call(pid, {:chat, message, opts}, timeout)
      end

      # GenServer Callbacks
      @impl GenServer
      def init(agent) do
        # Initialize memory if configured
        agent =
          case agent.memory_config do
            %{backend: backend} = config when not is_nil(backend) ->
              case Process.whereis(config[:name]) do
                nil ->
                  {:ok, pid} = backend.initialize(name: config[:name])
                  %{agent | memory_pid: pid}

                pid ->
                  %{agent | memory_pid: pid}
              end

            _ ->
              agent
          end

        # Schedule initial runs for all scheduled actions
        for {module, interval_ms, input, opts} <- agent.scheduled_actions do
          name = opts[:name] || Agent.module_to_name(module)
          Agent.schedule_action(name, module, interval_ms, input, opts)
        end

        {:ok, agent}
      end

      @impl GenServer
      def handle_call({:chat, message, opts}, _from, agent) do
        case chat(agent, message, opts) do
          {:ok, response} = ok -> {:reply, ok, agent}
          {:error, _reason} = error -> {:reply, error, agent}
        end
      end

      @impl GenServer
      def handle_info({:signal, signal}, agent) do
        _ = handle_signal(agent, signal)
        {:noreply, agent}
      end

      @impl GenServer
      def handle_info(input, agent) do
        Agent.__handle_info__(input, agent)
      end

      @impl GenServer
      def terminate(_reason, %{memory_pid: pid}) when is_pid(pid) do
        Process.exit(pid, :normal)
        :ok
      end

      def terminate(_reason, _agent), do: :ok

      defoverridable chat: 3
    end
  end

  def handle_signal(agent, signal) do
    apply(agent.module, :handle_signal, [agent, signal])
  end

  def chat(agent, message, opts) do
    llm_config = build_llm_config(agent, opts)

    case LLM.call(message, agent.beams ++ agent.prisms, llm_config) do
      {:ok, %{payload: %{content: content}}} when is_map(content) ->
        store_interaction(agent, message, format_content(content), opts)
        {:ok, format_content(content)}

      {:ok, %{payload: %{content: content}}} when is_binary(content) ->
        store_interaction(agent, message, content, opts)
        {:ok, content}

      {:error, reason} ->
        {:error, reason}

      {:ok, %Req.Response{status: 401}} ->
        {:error, :invalid_api_key}

      {:ok, %Req.Response{body: %{"error" => error}}} ->
        {:error, error["message"] || "Unknown error"}

      {:ok, %Lux.Signal{payload: %{tool_calls_results: tool_call_results}} = signal} ->
        store_interaction(agent, message, format_content(tool_call_results), opts)
        {:ok, signal}

      unexpected ->
        {:error, {:unexpected_response, unexpected}}
    end
  end

  # Private function to build LLM config with memory context if enabled
  defp build_llm_config(agent, opts) do
    if agent.memory_pid && Keyword.get(opts, :use_memory, false) do
      max_context = Keyword.get(opts, :max_memory_context, 5)
      {:ok, recent} = agent.memory_config.backend.recent(agent.memory_pid, max_context)

      # Convert memory entries to chat messages
      memory_messages =
        recent
        |> Enum.reverse()
        |> Enum.map(fn entry ->
          %{role: entry.metadata.role, content: entry.content}
        end)

      # Add memory context to existing messages or create new messages list
      Map.update(agent.llm_config, :messages, memory_messages, fn existing ->
        memory_messages ++ existing
      end)
    else
      agent.llm_config
    end
  end

  # Private function to store interactions in memory if enabled
  defp store_interaction(agent, user_message, assistant_response, opts) do
    if agent.memory_pid && Keyword.get(opts, :use_memory, false) do
      {:ok, _} =
        agent.memory_config.backend.add(
          agent.memory_pid,
          user_message,
          :interaction,
          %{role: :user}
        )

      {:ok, _} =
        agent.memory_config.backend.add(
          agent.memory_pid,
          assistant_response,
          :interaction,
          %{role: :assistant}
        )
    end
  end

  # Helper function to format map content into a readable string
  defp format_content(content) when is_map(content) do
    Jason.encode!(content)
  end

  defp format_content(result) when is_list(result) do
    Enum.map_join(result, "\n", fn element -> format_content(element) end)
  end

  def schedule_action(name, module, interval_ms, input, opts) do
    Process.send_after(
      self(),
      {:run_scheduled_action, name, module, interval_ms, input, opts},
      interval_ms
    )
  end

  def module_to_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> String.downcase()
  end

  def beam?(module) when is_atom(module) do
    function_exported?(module, :steps, 0) and function_exported?(module, :run, 2)
  end

  def beam?(_), do: false

  def prism?(module) when is_atom(module) do
    function_exported?(module, :handler, 2)
  end

  def prism?(_), do: false

  def __handle_info__({:run_scheduled_action, name, module, interval_ms, input, opts}, agent) do
    timeout = opts[:timeout] || 60_000

    # Execute the action based on whether it's a Prism or Beam
    Task.Supervisor.async_nolink(
      Lux.ScheduledTasksSupervisor,
      fn ->
        try do
          result =
            case {Lux.Agent.prism?(module), Lux.Agent.beam?(module)} do
              {true, false} ->
                module.handler(input, agent)

              {false, true} ->
                module.run(input, agent)

              _ ->
                {:error, :invalid_module}
            end

          case result do
            {:ok, _} ->
              Logger.info("Scheduled action #{name} completed successfully")

            {:error, reason} ->
              Logger.warning("Scheduled action #{name} failed: #{inspect(reason)}")
          end
        catch
          kind, reason ->
            Logger.error("Scheduled action #{name} crashed: #{inspect({kind, reason})}")
        end
      end,
      timeout: timeout
    )

    # Schedule the next run
    Lux.Agent.schedule_action(name, module, interval_ms, input, opts)

    {:noreply, agent}
  end

  # to handle result from Task.Supervisor.async_nolink
  def __handle_info__({_ref, _result}, agent) do
    {:noreply, agent}
  end

  # to handle when the Task.Supervisor.async_nolink process is down without bringing down the agent
  def __handle_info__({:DOWN, _ref, :process, _pid, :normal}, agent) do
    {:noreply, agent}
  end

  # implements the access protocol for this struct...
  @impl Access
  defdelegate fetch(agent, key), to: Map

  @impl Access
  defdelegate get_and_update(data, key, function), to: Map

  @impl Access
  defdelegate pop(data, key), to: Map

  def get_handler_type({module, function}) when is_atom(module) and is_atom(function) do
    :module_function
  end

  def get_handler_type(module) when is_atom(module) do
    Code.ensure_compiled!(module)

    cond do
      function_exported?(module, :handler, 2) -> :prism
      function_exported?(module, :run, 2) -> :beam
      function_exported?(module, :focus, 2) -> :lens
      true -> :unknown
    end
  end
end
