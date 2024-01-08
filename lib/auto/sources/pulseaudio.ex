defmodule Auto.Sources.Pulseaudio do
    use GenServer

    alias Auto.Pulseaudio, as: PA

    @check_interval 20_000
    def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, opts)
    end

    def init(_opts) do
        Phoenix.PubSub.subscribe(Auto.PubSub, "input")
        send(self(), :check_volumes)
        {:ok, %{}}
    end

    def handle_info(:check_volumes, state) do
        input_percent =
            PA.default_source()
            |> PA.find_source()
            |> PA.device_volume_percent()

        output_percent =
            PA.default_sink()
            |> PA.find_sink()
            |> PA.device_volume_percent()

        Phoenix.PubSub.broadcast(Auto.PubSub, "volumes", {:volumes, %{source: input_percent, sink: output_percent}})
        Process.send_after(self(), :check_volumes, @check_interval)
        {:noreply, state}
    end

  def handle_info({:plus, message}, state) do
    # TODO: Emit events about the changes
    case message do
      %{event: :turn, part: :knobs, states: [_, _, change_out, change_in]} ->
        IO.inspect(change_in, label: "input change")
        IO.inspect(change_out, label: "output change")
        handle_input(change_in)
        handle_output(change_out)
        send(self(), :check_volumes)
      _ ->
        nil
    end

    {:noreply, state}
  end

  def handle_input({:none, 0}), do: nil
  def handle_input({:left, steps}), do: Auto.Pulseaudio.change_default_source_volume(-steps * 10)
  def handle_input({:right, steps}), do: Auto.Pulseaudio.change_default_source_volume(steps * 10)

  def handle_output({:none, 0}), do: nil
  def handle_output({:left, steps}), do: Auto.Pulseaudio.change_default_sink_volume(-steps * 10)
  def handle_output({:right, steps}), do: Auto.Pulseaudio.change_default_sink_volume(steps * 10)
end