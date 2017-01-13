alias Farmbot.BotState.Hardware.State,      as: Hardware
alias Farmbot.BotState.Configuration.State, as: Configuration
alias Experimental.GenStage
defmodule Farmbot.BotState.Monitor do
  @moduledoc """
    this is the master state tracker. It receives the states from
    various modules, and then pushes updated state to anything that cares
  """
  use GenStage
  require Logger

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
      hardware:      Hardware.t,
      configuration: Configuration.t
    }
    defstruct [
      hardware:      %Hardware{},
      configuration: %Configuration{}
    ]
  end

  @doc """
    Starts the state producer.
  """
  def start_link(), do: GenStage.start_link(__MODULE__, [], name: __MODULE__)
  def init([]), do: {:producer, %State{}}

  def handle_demand(_demand, state), do: dispatch state

  # When we get a state update from Hardware
  def handle_cast(%Hardware{} = new_things, %State{} = state) do
    if new_things != state.hardware do
      new_state = %State{state | hardware: new_things}
      dispatch(new_state)
    else
      no_dispatch(state)
    end
  end

  # When we get a state update from Configuration
  def handle_cast(%Configuration{} = new_things, %State{} = state) do
    if new_things != state.configuration do
      new_state = %State{state | configuration: new_things}
      dispatch(new_state)
    else
      no_dispatch(state)
    end
  end

  def handle_call(:get_state,_, state), do: {:reply, state, [state], state}

  @doc """
    Gets the current accumulated state.
  """
  def get_state, do: GenServer.call(__MODULE__, :get_state)

  @spec dispatch(State.t) :: no_return
  defp dispatch(%State{} = state), do: {:noreply, [state], state}

  @spec dispatch(State.t) :: no_return
  defp no_dispatch(%State{} = state), do: {:noreply, [], state}
end