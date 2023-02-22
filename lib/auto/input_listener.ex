defmodule Auto.InputListener do
  use GenServer

  @check_interval 10_000
  @poll_interval 100
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  def init(opts) do
    send(self(), :check_devices)
    send(self(), :poll)
    {:ok, %{pedal: nil, plus: nil}}
  end

  # Detect new devices, ensure started
  def handle_info(:check_devices, state) do
    devices = Streamdex.devices()

    pedal =
      Enum.find(devices, fn d ->
        d.config.name == "Stream Deck Pedal"
      end)

    plus =
      Enum.find(devices, fn d ->
        d.config.name == "Stream Deck +"
      end)

    new_pedal =
      if is_nil(state.pedal) and pedal do
        Streamdex.start(pedal)
      else
        state.pedal
      end

    new_plus =
      if is_nil(state.plus) and plus do
        Streamdex.start(plus)
      else
        state.plus
      end

    Process.send_after(self(), :check_devices, @check_interval)
    {:noreply, %{state | plus: new_plus, pedal: new_pedal}}
  end

  def handle_info(:poll, state) do
    if state.plus do
      state.plus
      |> state.plus.module.poll()
      |> broadcast(:plus)
    end

    if state.pedal do
      state.pedal
      |> state.pedal.module.poll()
      |> broadcast(:pedal)
    end

    Process.send_after(self(), :poll, @poll_interval)
    {:noreply, state}
  end

  defp broadcast(nil, _), do: nil

  defp broadcast(result, device_type) do
    IO.inspect({device_type, result})
    Phoenix.PubSub.broadcast(Auto.PubSub, "input", {device_type, result})
  end
end
