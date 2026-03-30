defmodule Auto.Sinks.KillTeleport do
  use GenServer
  require Logger

  @idle_threshold_ms 30 * 60 * 1000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    Phoenix.PubSub.subscribe(Auto.PubSub, "idle")
    {:ok, %{killed: false}}
  end

  def handle_info({:idle_ms, idle_ms}, state) when idle_ms >= @idle_threshold_ms do
    if state.killed do
      {:noreply, state}
    else
      Logger.info("Idle for #{div(idle_ms, 60_000)} min, killing Wifiman Desktop")

      case System.cmd("sudo", ~w(killall /usr/lib/wi-fiman-desktop/wifiman-desktopd),
             stderr_to_stdout: true
           ) do
        {_, 0} ->
          Logger.info("Wifiman Desktop killed")

        {output, _code} ->
          Logger.warning("Failed to kill Wifiman Desktop: #{output}")
      end

      {:noreply, %{state | killed: true}}
    end
  end

  def handle_info({:idle_ms, _idle_ms}, state) do
    {:noreply, %{state | killed: false}}
  end
end
