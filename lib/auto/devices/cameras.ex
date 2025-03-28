defmodule Auto.Devices.Cameras do
  use GenServer

  @check_interval 1000
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  def init(opts) do
    send(self(), :check_cameras)
    {:ok, %{in_use?: false}}
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
               |> IO.inspect(label: "camera status")
               |> String.ends_with?("0"))
      end

    case {state.in_use?, in_use?} |> IO.inspect(label: "camera change?") do
      {true, false} ->
        Phoenix.PubSub.broadcast(Auto.PubSub, "cameras", :cameras_stopped)

      {false, true} ->
        Phoenix.PubSub.broadcast(Auto.PubSub, "cameras", :cameras_started)

      _ ->
        :ok
    end

    Process.send_after(self(), :check_cameras, @check_interval)
    {:noreply, %{state | in_use?: in_use?}}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end
end
