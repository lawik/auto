defmodule Auto.Sinks.KillTeleport do
  use GenServer
  require Logger

  @idle_threshold_ms 30 * 60 * 1000
  @service "wifiman-desktop.service"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    Phoenix.PubSub.subscribe(Auto.PubSub, "idle")
    {:ok, %{stopped: false}}
  end

  def handle_info({:idle_ms, idle_ms}, %{stopped: false} = state)
      when idle_ms >= @idle_threshold_ms do
    Logger.info("Idle for #{div(idle_ms, 60_000)} min, stopping #{@service}")
    {:noreply, %{state | stopped: systemctl("stop")}}
  end

  def handle_info({:idle_ms, idle_ms}, %{stopped: true} = state)
      when idle_ms < @idle_threshold_ms do
    Logger.info("Activity resumed, starting #{@service}")
    {:noreply, %{state | stopped: not systemctl("start")}}
  end

  def handle_info({:idle_ms, _idle_ms}, state) do
    {:noreply, state}
  end

  # Returns true when the systemctl command succeeded.
  defp systemctl(action) do
    case System.cmd("sudo", ["-n", "systemctl", action, @service], stderr_to_stdout: true) do
      {_, 0} ->
        Logger.info("#{@service} #{action} ok")
        true

      {output, code} ->
        Logger.warning("Failed to #{action} #{@service} (exit #{code}): #{String.trim(output)}")
        false
    end
  end
end
