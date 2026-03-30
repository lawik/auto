defmodule Auto.Sources.Idle do
  use GenServer
  require Logger

  @check_interval 60_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    send(self(), :check_idle)
    {:ok, %{idle_ms: 0}}
  end

  def handle_info(:check_idle, state) do
    idle_ms =
      case System.cmd("qdbus", ~w(org.freedesktop.ScreenSaver /ScreenSaver GetSessionIdleTime)) do
        {output, 0} ->
          output |> String.trim() |> String.to_integer()

        {error, _code} ->
          Logger.error("Failed to get idle time: #{inspect(error)}")
          0
      end

    Phoenix.PubSub.broadcast(Auto.PubSub, "idle", {:idle_ms, idle_ms})

    Process.send_after(self(), :check_idle, @check_interval)
    {:noreply, %{state | idle_ms: idle_ms}}
  end
end
