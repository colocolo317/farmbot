defmodule Farmbot.BotState.Hardware do
  @moduledoc """
    tracks mcu_params, pins, location
  """

  require Logger
  alias Farmbot.StateTracker

  @behaviour StateTracker
  use StateTracker,
      name: __MODULE__,
      model: [
        location: [-1,-1,-1],
        end_stops: {-1,-1,-1,-1,-1,-1},
        mcu_params: %{},
        pins: %{}
      ]

  @type t :: %__MODULE__.State{
    location: location,
    end_stops: end_stops,
    mcu_params: mcu_params,
    pins: pins
  }

  @type location :: [number, ...]
  @type mcu_params :: map
  @type pins :: map
  @type end_stops :: {integer,integer,integer,integer,integer,integer}

  # Callback that happens when this module comes up
  def load([]) do
    {:ok, p} = get_config("params")
    initial_state = %State{mcu_params: p}

    spawn fn() ->
      case set_initial_params(initial_state) do
        {:ok, :no_params} ->
          Logger.debug ">> is reading default Hardware params."
          Farmbot.CeleryScript.Command.read_all_params(%{}, [])
        :ok ->
          Logger.debug ">> Hardware Params set"
        {:error, reason} ->
          Logger.error(">> Error setting Hardware Params: #{inspect reason}")
      end
    end

    {:ok, initial_state}
  end

  @doc """
    Takes a Hardware State object, and makes it happen
  """
  @spec set_initial_params(State.t) :: {:ok, :no_params} | :ok | {:error, term}
  def set_initial_params(%State{} = state) do
    if Enum.empty?(state.mcu_params) do
      {:ok, :no_params}
    else
      # BUG(Connor): The first param is rather unstable for some reason.
      # Try to send a fake packet just to make sure we have a good
      # Connection to the Firmware

      # Its magic
      Farmbot.CeleryScript.Command.read_param(%{label: "param_version"}, [])

      # iterate over mcu_params and read each one
      config_pairs = Enum.map(state.mcu_params, fn({param, val}) ->
        %Farmbot.CeleryScript.Ast{kind: "pair",
            args: %{label: param, value: val}, body: []}
      end)
      Farmbot.CeleryScript.Command.config_update(%{package: "arduino_firmware"},
        config_pairs)
      :ok
    end
  end

  def handle_call({:get_pin, pin_number}, _from, %State{} = state) do
    dispatch Map.get(state.pins, Integer.to_string(pin_number)), state
  end

  def handle_call(:get_current_pos, _from, %State{} = state) do
    dispatch state.location, state
  end

  def handle_call(:get_all_mcu_params, _from, %State{} = state) do
    dispatch state.mcu_params, state
  end

  def handle_call({:get_param, param}, _from, %State{} = state) do
    dispatch Map.get(state.mcu_params, param), state
  end

  def handle_call(event, _from, %State{} = state) do
    Logger.error ">> got an unhandled call in " <>
                 "Hardware tracker: #{inspect event}"
    dispatch :unhandled, state
  end

  def handle_cast({:set_pos, {x, y, z}}, %State{} = state) do
    dispatch %State{state | location: [x,y,z]}
  end

  def handle_cast({:set_pin_value, {pin, value}}, %State{} = state) do
    pin_state = state.pins
    new_pin_value =
    case Map.get(pin_state, Integer.to_string(pin)) do
      nil                     ->
        %{mode: -1,   value: value}
      %{mode: mode, value: _} ->
        %{mode: mode, value: value}
    end
    Logger.debug ">> set pin: #{pin}: #{new_pin_value.value}"
    new_pin_state = Map.put(pin_state, Integer.to_string(pin), new_pin_value)
    dispatch %State{state | pins: new_pin_state}
  end

  def handle_cast({:set_pin_mode, {pin, mode}}, %State{} = state) do
    pin_state = state.pins
    new_pin_value =
    case Map.get(pin_state, Integer.to_string(pin)) do
      nil                      -> %{mode: mode, value: -1}
      %{mode: _, value: value} -> %{mode: mode, value: value}
    end
    new_pin_state = Map.put(pin_state, Integer.to_string(pin), new_pin_value)
    dispatch %State{state | pins: new_pin_state}
  end

  def handle_cast({:set_param, {param_string, value}}, %State{} = state) do
    new_params = Map.put(state.mcu_params, param_string, value)
    put_config("params", new_params)
    dispatch %State{state | mcu_params: new_params}
  end

  def handle_cast({:set_end_stops, {xa,xb,ya,yb,za,zc}}, %State{} = state) do
    dispatch %State{state | end_stops: {xa,xb,ya,yb,za,zc}}
  end

  # catch all.
  def handle_cast(event, %State{} = state) do
    Logger.error ">> got an unhandled cast " <>
                 "in Hardware tracker: #{inspect event}"
    dispatch state
  end
end
