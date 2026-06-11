defmodule Auto.Sources.Idle do
  @moduledoc """
  Reports user idle time on the `"idle"` PubSub topic as `{:idle_ms, ms}`.

  KWin on Wayland does not implement `org.freedesktop.ScreenSaver.GetSessionIdleTime`
  (it returns `org.freedesktop.DBus.Error.NotSupported`), so the previous D-Bus polling
  approach always reported `0`. Instead we drive `swayidle`, which speaks the KDE /
  `ext-idle-notify-v1` Wayland idle protocol that KWin does support.

  swayidle fires its `timeout` command once the session has been idle for
  `@detect_seconds`, and its `resume` command when activity returns. Those are edge
  events, so between them we reconstruct a continuously growing idle time (seeded from
  a monotonic clock) and re-broadcast it every `@tick_interval`. Downstream consumers
  (e.g. `Auto.Sinks.KillTeleport`) keep their existing threshold logic unchanged.
  """
  use GenServer
  require Logger

  # How long the session must be idle before swayidle first notifies us.
  @detect_seconds 60
  # How often we re-broadcast the growing idle time while still idle.
  @tick_interval 60_000
  # Retry cadence if swayidle is missing or exits.
  @retry_interval 30_000

  @idle_start "__AUTO_IDLE_START__"
  @idle_end "__AUTO_IDLE_END__"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    send(self(), :start_swayidle)
    {:ok, %{port: nil, idle_since: nil, tick_ref: nil}}
  end

  def handle_info(:start_swayidle, state) do
    case System.find_executable("swayidle") do
      nil ->
        Logger.error("swayidle not found; idle detection disabled. Retrying in #{div(@retry_interval, 1000)}s.")
        Process.send_after(self(), :start_swayidle, @retry_interval)
        {:noreply, state}

      path ->
        port =
          Port.open({:spawn_executable, path}, [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            {:line, 1024},
            args: [
              "-w",
              "timeout",
              Integer.to_string(@detect_seconds),
              "printf '#{@idle_start}\\n'",
              "resume",
              "printf '#{@idle_end}\\n'"
            ]
          ])

        Logger.info("Started swayidle for idle detection (notifies after #{@detect_seconds}s idle)")
        {:noreply, %{state | port: port}}
    end
  end

  # swayidle (and its child commands) write line-buffered output to the port.
  def handle_info({port, {:data, {_eol, line}}}, %{port: port} = state) do
    line = String.trim(line)

    cond do
      String.contains?(line, @idle_start) ->
        # We only learn about idleness once the @detect_seconds threshold is crossed,
        # so seed idle_since that far in the past.
        idle_since = System.monotonic_time(:millisecond) - @detect_seconds * 1000
        broadcast(current_idle_ms(idle_since))
        {:noreply, %{state | idle_since: idle_since, tick_ref: schedule_tick()}}

      String.contains?(line, @idle_end) ->
        cancel_tick(state.tick_ref)
        broadcast(0)
        {:noreply, %{state | idle_since: nil, tick_ref: nil}}

      line == "" ->
        {:noreply, state}

      true ->
        Logger.debug("swayidle: #{line}")
        {:noreply, state}
    end
  end

  def handle_info(:tick, %{idle_since: nil} = state), do: {:noreply, state}

  def handle_info(:tick, %{idle_since: idle_since} = state) do
    broadcast(current_idle_ms(idle_since))
    {:noreply, %{state | tick_ref: schedule_tick()}}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("swayidle exited (status #{status}); restarting idle detection in #{div(@retry_interval, 1000)}s")
    cancel_tick(state.tick_ref)
    Process.send_after(self(), :start_swayidle, @retry_interval)
    {:noreply, %{state | port: nil, idle_since: nil, tick_ref: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp current_idle_ms(idle_since), do: System.monotonic_time(:millisecond) - idle_since

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_interval)

  defp cancel_tick(nil), do: :ok
  defp cancel_tick(ref), do: Process.cancel_timer(ref)

  defp broadcast(idle_ms) do
    Phoenix.PubSub.broadcast(Auto.PubSub, "idle", {:idle_ms, idle_ms})
  end
end
