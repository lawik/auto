defmodule Auto.Devices.Keylights do
  use GenServer

  @check_interval 10_000
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  def init(_opts) do
    Phoenix.PubSub.subscribe(Auto.PubSub, "input")
    Phoenix.PubSub.subscribe(Auto.PubSub, "cameras")
    send(self(), :check_devices)
    {:ok, %{keylights: []}}
  end

  def handle_info(:check_devices, state) do
    devices = Keylight.discover()
    Process.send_after(self(), :check_devices, @check_interval)
    {:noreply, %{state | keylights: devices}}
  end

  def handle_info(:cameras_stopped, state) do
    IO.puts("keylights received cameras stopped")
    Keylight.off(state.keylights)
    {:noreply, state}
  end

  def handle_info(:cameras_started, state) do
    IO.puts("keylights received cameras started")
    Keylight.on(state.keylights)
    {:noreply, state}
  end

  def handle_info({:plus, message}, state) do
    # TODO: Emit events about the changes
    case message do
      %{event: :button, part: :keys, states: [:down | _]} ->
        Keylight.on(state.keylights)

      %{event: :button, part: :keys, states: [_ | [:down | _]]} ->
        Keylight.off(state.keylights)

      %{event: :button, part: :knobs, states: [:down | _]} ->
        state.keylights
        |> Enum.each(fn {_, k} ->
          {:ok, %{"lights" => [%{"on" => on}]}} = Keylight.status(k)

          if on == 1 do
            Keylight.off(k)
          else
            Keylight.on(k)
          end
        end)

      %{event: :button, part: :knobs, states: [_ | [:down | _]]} ->
        # Default temp
        state.keylights
        |> Keylight.set(temperature: 181)

      %{event: :turn, part: :knobs, states: [{:left, steps} | _]} ->
        state.keylights
        |> Enum.each(fn {_, k} ->
          {:ok, %{"lights" => [%{"brightness" => current}]}} = Keylight.status(k)
          new = max(current - steps, 0)
          Keylight.set(k, brightness: new)
        end)

      %{event: :turn, part: :knobs, states: [{:right, steps} | _]} ->
        state.keylights
        |> Enum.each(fn {_, k} ->
          {:ok, %{"lights" => [%{"brightness" => current}]}} = Keylight.status(k)
          new = min(current + steps, 100)
          Keylight.set(k, brightness: new)
        end)

      %{event: :turn, part: :knobs, states: [_ | [{:left, steps} | _]]} ->
        state.keylights
        |> Enum.each(fn {_, k} ->
          {:ok, %{"lights" => [%{"temperature" => current}]}} = Keylight.status(k)
          new = max(current - steps, 0)
          Keylight.set(k, temperature: new)
        end)

      %{event: :turn, part: :knobs, states: [_ | [{:right, steps} | _]]} ->
        state.keylights
        |> Enum.each(fn {_, k} ->
          {:ok, %{"lights" => [%{"temperature" => current}]}} = Keylight.status(k)
          new = current + steps
          Keylight.set(k, temperature: new)
        end)

      _ ->
        nil
    end

    {:noreply, state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end
end
