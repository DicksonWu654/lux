defmodule Lux.AgentTest do
  use UnitCase, async: true

  alias Lux.Agent
  alias Lux.Memory.SimpleMemory
  alias Lux.Schemas.Companies.ObjectiveSignal
  alias Lux.Schemas.Companies.TaskSignal

  @default_timeout 1_000

  defmodule SignalHandler1 do
    @moduledoc false
    use Lux.Prism,
      name: "Signal Handler 1",
      description: "A signal handler"

    def handler(signal, _context) do
      {:ok, signal}
    end
  end

  defmodule SignalHandler2 do
    @moduledoc false
    use Lux.Prism,
      name: "Signal Handler 2",
      description: "A signal handler"

    def handler(signal, _context) do
      {:ok, signal}
    end
  end

  defmodule TestLens do
    @moduledoc false
    use Lux.Lens,
      name: "Test Lens",
      description: "A test lens"
  end

  # Test modules
  defmodule TestPrism do
    @moduledoc false
    use Lux.Prism,
      name: "Test Prism",
      description: "A test prism"

    def handler(_params, _context), do: {:ok, %{result: "test"}}
  end

  defmodule TestBeam do
    @moduledoc false
    use Lux.Beam,
      name: "Test Beam",
      description: "A test beam"

    sequence do
      step(:test, TestPrism, %{})
    end
  end

  defmodule SimpleAgent do
    @moduledoc false
    use Lux.Agent,
      name: "Simple Agent",
      description: "A simple agent that keeps things simple.",
      goal: "You have one simple goal. Not making things too complicated.",
      prisms: [TestPrism],
      beams: [TestBeam],
      signal_handlers: [{TestSchema, TestPrism}]
  end

  defmodule MemoryAgent do
    @moduledoc false
    use Lux.Agent,
      name: "Memory Agent",
      description: "An agent with memory capabilities",
      goal: "Remember and use past interactions",
      memory_config: %{
        backend: SimpleMemory,
        name: :test_memory
      }

    # We override the chat functions to store the messages in memory here and do not actually call any LLM...
    @impl true
    def chat(agent, message, _opts) do
      response = "Response to: " <> message

      with {:ok, _} <-
             SimpleMemory.add(
               agent.memory_pid,
               message,
               :interaction,
               %{role: :user}
             ) do
        {:ok, _} =
          SimpleMemory.add(
            agent.memory_pid,
            response,
            :interaction,
            %{role: :assistant}
          )

        {:ok, response}
      end
    end
  end

  defmodule TestScheduledPrism do
    @moduledoc false
    use Lux.Prism,
      name: "Test Scheduled Prism",
      description: "A test prism for scheduled actions"

    def handler(params, _opts) do
      send(Process.whereis(:test_scheduler), {:prism_called, params})
      {:ok, %{result: "scheduled prism success"}}
    end
  end

  defmodule TestScheduledBeam do
    @moduledoc false
    use Lux.Beam,
      name: "Test Scheduled Beam",
      description: "A test beam for scheduled actions"

    sequence do
      step(:test, TestScheduledPrism, %{test: "beam"})
    end
  end

  defmodule CompanyAgent do
    @moduledoc false
    use Lux.Agent,
      template: :company_agent,
      template_opts: %{
        llm_config: %{temperature: 0.7}
      }

    @impl true
    def handle_task_update(signal, _context) do
      {:ok,
       %Lux.Signal{
         id: "response-1",
         schema_id: signal.schema_id,
         payload:
           Map.merge(signal.payload, %{
             "type" => "status_update",
             "status" => "in_progress"
           }),
         recipient: signal.sender
       }}
    end
  end

  describe "memory operations" do
    test "initializes memory on start", %{test: test_name} do
      {:ok, pid} = MemoryAgent.start_link(%{name: "Test Agent #{test_name}"})
      agent = MemoryAgent.get_state(pid)
      assert is_pid(agent.memory_pid)
    end

    test "stores and retrieves interactions", %{test: test_name} do
      {:ok, pid} = MemoryAgent.start_link(%{name: "Test Agent #{test_name}"})

      # Send a message
      {:ok, response} = MemoryAgent.send_message(pid, "Hello")
      assert response == "Response to: Hello"

      # Check stored messages
      agent = :sys.get_state(pid)
      {:ok, recent} = SimpleMemory.recent(agent.memory_pid, 2)

      assert length(recent) == 2
      [assistant_msg, user_msg] = recent

      assert assistant_msg.content == "Response to: Hello"
      assert assistant_msg.type == :interaction
      assert assistant_msg.metadata.role == :assistant

      assert user_msg.content == "Hello"
      assert user_msg.type == :interaction
      assert user_msg.metadata.role == :user
    end
  end

  describe "can be started with a unique name" do
    test "can be started with a unique name", %{test: test_name} do
      name1 = String.replace("Test_Agent_1_#{test_name}", " ", "_")
      name2 = String.replace("Test_Agent_2_#{test_name}", " ", "_")

      # Start two agents with different names
      pid1 = start_supervised!({SimpleAgent, %{name: name1}})
      pid2 = start_supervised!({SimpleAgent, %{name: name2}})

      # Verify they are different processes
      assert pid1 != pid2

      # Get their states to verify they have the correct names
      agent1 = :sys.get_state(pid1)
      agent2 = :sys.get_state(pid2)

      assert agent1.name == name1
      assert agent2.name == name2

      assert_raise RuntimeError, fn ->
        start_supervised!({SimpleAgent, %{name: name1}})
      end
    end
  end

  describe "scheduled actions" do
    setup do
      # Register process to receive test messages
      Process.register(self(), :test_scheduler)
      :ok
    end

    test "executes scheduled prism actions" do
      start_supervised!(
        {SimpleAgent,
         %{
           name: "Scheduled Agent",
           prisms: [TestScheduledPrism],
           scheduled_actions: [
             {TestScheduledPrism, 100, %{test: "prism"}, %{name: "test_prism"}}
           ]
         }}
      )

      # Wait for the scheduled action to run
      assert_receive {:prism_called, %{test: "prism"}}, @default_timeout
    end

    test "executes scheduled beam actions" do
      start_supervised!(
        {SimpleAgent,
         %{
           name: "Scheduled Agent",
           beams: [TestScheduledBeam],
           scheduled_actions: [
             {TestScheduledBeam, 100, %{test: "beam"}, %{name: "test_beam"}}
           ]
         }}
      )

      # Wait for the scheduled action to run. We match on prism_called because the beam is executed by the prism.
      assert_receive {:prism_called, %{test: "beam"}}, @default_timeout
    end

    test "handles invalid modules gracefully" do
      pid =
        start_supervised!(
          {SimpleAgent,
           %{
             name: "Scheduled Agent",
             scheduled_actions: [
               {InvalidModule, 100, %{}, %{name: "invalid"}}
             ]
           }}
        )

      # The agent should not crash
      assert Process.alive?(pid)
    end

    test "uses default name when not provided" do
      start_supervised!(
        {SimpleAgent,
         %{
           name: "Scheduled Agent",
           prisms: [TestScheduledPrism],
           scheduled_actions: [
             {TestScheduledPrism, 100, %{test: "default_name"}, %{}}
           ]
         }}
      )

      # Wait for the scheduled action to run
      assert_receive {:prism_called, %{test: "default_name"}}, @default_timeout
    end
  end

  describe "company agent template" do
    test "adds signal handling capabilities" do
      # No need to create an agent instance to test exported functions
      assert function_exported?(CompanyAgent, :handle_signal, 2)
      assert function_exported?(CompanyAgent, :handle_task_assignment, 2)
      assert function_exported?(CompanyAgent, :handle_task_update, 2)
      assert function_exported?(CompanyAgent, :handle_task_completion, 2)
      assert function_exported?(CompanyAgent, :handle_task_failure, 2)
      assert function_exported?(CompanyAgent, :handle_objective_evaluation, 2)
      assert function_exported?(CompanyAgent, :handle_objective_next_step, 2)
      assert function_exported?(CompanyAgent, :handle_objective_update, 2)
      assert function_exported?(CompanyAgent, :handle_objective_completion, 2)
    end

    test "properly routes signals through handler" do
      signal = %Lux.Signal{
        id: "test-1",
        schema_id: TaskSignal,
        payload: %{
          "type" => "status_update",
          "task_id" => "task-1",
          "objective_id" => "obj-1",
          "title" => "Test Task",
          "status" => "in_progress"
        },
        sender: "test-sender"
      }

      context = %{
        beams: [],
        lenses: [],
        prisms: []
      }

      # Test that the signal is routed through the handler
      assert {:ok, response} = CompanyAgent.handle_signal(signal, context)
      assert response.schema_id == TaskSignal
      assert response.payload["type"] == "status_update"
      assert response.payload["status"] == "in_progress"
      assert response.recipient == signal.sender
    end

    test "templated company agent has company signal handlers" do
      assert %Lux.Agent{
               signal_handlers: [
                 {ObjectiveSignal, {CompanyAgent, :handle_objective_signal}},
                 {Lux.Schemas.Companies.TaskSignal, {CompanyAgent, :handle_task_signal}}
               ]
             } = CompanyAgent.view()
    end

    test "template company agent with extra handlers has all handlers and they follow a correct order" do
      defmodule TestCompanyAgent2 do
        @moduledoc false
        use Lux.Agent,
          template: :company_agent,
          signal_handlers: [
            {FakeSignalSchema1, SignalHandler1},
            {FakeSignalSchema2, SignalHandler2}
          ]
      end

      assert %Lux.Agent{
               signal_handlers: [
                 {FakeSignalSchema1, SignalHandler1},
                 {FakeSignalSchema2, SignalHandler2},
                 {ObjectiveSignal, {TestCompanyAgent2, :handle_objective_signal}},
                 {Lux.Schemas.Companies.TaskSignal, {TestCompanyAgent2, :handle_task_signal}}
               ]
             } = TestCompanyAgent2.view()
    end

    test "templated agent can override a template signal handler" do
      defmodule TestCompanyAgent3 do
        @moduledoc false
        use Lux.Agent,
          template: :company_agent,
          signal_handlers: [{Lux.Schemas.Companies.TaskSignal, SignalHandler1}]
      end

      # The templated handler for Task signal is removed and replaced with the user-provided one
      assert %Lux.Agent{
               signal_handlers: [
                 {Lux.Schemas.Companies.TaskSignal, SignalHandler1},
                 {ObjectiveSignal, {TestCompanyAgent3, :handle_objective_signal}}
               ]
             } = TestCompanyAgent3.view()
    end

    test "includes template options in context" do
      signal = %Lux.Signal{
        id: "test-1",
        schema_id: TaskSignal,
        payload: %{
          "type" => "status_update",
          "task_id" => "task-1",
          "objective_id" => "obj-1",
          "title" => "Test Task",
          "status" => "in_progress"
        },
        sender: "test-sender"
      }

      context = %{
        beams: [],
        lenses: [],
        prisms: [],
        # Different from template opts
        llm_config: %{temperature: 0.5}
      }

      # Test that template options are merged into context
      assert {:ok, _response} = CompanyAgent.handle_signal(signal, context)
    end
  end

  describe "signal handlers" do
    test "can handle specified signal" do
      signal = Lux.Signal.new(%{schema_id: TestSchema, payload: %{test: "signal"}})
      pid = start_supervised!({SimpleAgent, %{name: "Signal Agent"}})

      # Perhaps, this should be updated to use :trace, available since OTP27
      # https://www.erlang.org/doc/apps/kernel/trace.html
      :erlang.trace(pid, true, [:call])

      :erlang.trace_pattern(
        {Lux.AgentTest.TestPrism, :handler, 2},
        [{:_, [], [{:return_trace}]}],
        [:global]
      )

      send(pid, {:signal, signal})

      assert_receive {:trace, ^pid, :return_from, {Lux.AgentTest.TestPrism, :handler, _},
                      {:ok, %{result: "test"}}},
                     5000
    end

    test "can handle python signal" do
      python_prism =
        __DIR__
        |> List.wrap()
        |> Enum.concat(["..", "..", "support", "python_prism.py"])
        |> Path.join()
        |> Path.expand()

      defmodule PythonAgent do
        @moduledoc false
        use Lux.Agent,
          name: "Python Agent",
          description: "An agent that handles Python signals",
          prisms: [TestPrism],
          signal_handlers: [{PythonSignal, {:python, python_prism}}]
      end

      signal = Lux.Signal.new(%{schema_id: PythonSignal, payload: %{test: "signal"}})
      assert {:ok, %{"message" => "Hello, prism!"}} = PythonAgent.handle_signal(signal, %{})
    end

    test "ignore unspecified signal" do
      # Would be nice to have this test using messages too.
      signal = %Lux.Signal{schema_id: Unsupported, payload: %{test: "signal"}}
      assert :ignore = SimpleAgent.handle_signal(signal, %{})
    end
  end
end
