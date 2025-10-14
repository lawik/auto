defmodule Auto.Devices.Cameras do
  use GenServer

  @check_interval 1000
  @times 2
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  def init(opts) do
    send(self(), :check_cameras)
    Phoenix.PubSub.subscribe(Auto.PubSub, "input")
    {:ok, %{in_use?: false, times: 0, control_lights?: true}}
  end

  def handle_info(:check_cameras, state) do
    {output, 0} = System.shell("lsmod | grep uvcvideo")

    camera_usage =
      output
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, "uvcvideo"))

    in_use? =
      case camera_usage do
        nil ->
          false

        string ->
          not (string
               |> String.trim()
               |> String.ends_with?("0"))
      end

    times =
      case {in_use?, state.in_use?} do
        {false, _} -> 0
        {true, false} -> 1
        {true, true} -> state.times + 1
      end

    case {state.in_use?, in_use?, times} do
      {true, false, _} ->
        if state.control_lights? do
          Phoenix.PubSub.broadcast(Auto.PubSub, "cameras", :cameras_stopped)
        end

      {_, true, times} when times >= @times ->
        if state.control_lights? do
          Phoenix.PubSub.broadcast(Auto.PubSub, "cameras", :cameras_started)
        end

      _ ->
        :ok
    end

    Process.send_after(self(), :check_cameras, @check_interval)
    {:noreply, %{state | in_use?: in_use?, times: times}}
  end

  def handle_info({:plus, %{event: :button, part: :keys, states: states}}, state) do
    case Enum.at(states, 4) do
      :down ->
        control_lights? = !state.control_lights?
        Phoenix.PubSub.broadcast(Auto.PubSub, "cameras", {:control_lights?, control_lights?})
        {:noreply, %{state | control_lights?: control_lights?}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(_, state) do
    {:noreply, state}
  end
end
