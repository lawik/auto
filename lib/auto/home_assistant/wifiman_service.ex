defmodule Auto.HomeAssistant.WifimanService do
  @moduledoc """
  Home Assistant switch for `wifiman-desktop.service` on this machine.

  ON starts the service, OFF stops it. Stopping triggers the unit's
  ExecStopPost cleanup (priv/wifiman/teleport-down.sh) which tears down the
  Teleport WireGuard tunnel and its `~.` DNS capture. Without that, stopping
  mid-tunnel black-holes DNS on this host.

  The state is polled from systemd so Home Assistant reflects reality even
  when `Auto.Sinks.KillTeleport` toggles the service on idle/activity.

  The MQTT broker is reached by IP, so this switch keeps working as a recovery
  control even while wifiman has broken DNS on this host.
  """
  use Homex.Entity.Switch,
    name: "wifiman-desktop",
    update_interval: 10_000,
    retain: true

  require Logger

  @service "wifiman-desktop.service"

  def handle_init(entity), do: reflect_state(entity)

  def handle_timer(entity), do: reflect_state(entity)

  def handle_on(entity) do
    systemctl("start")
    entity
  end

  def handle_off(entity) do
    systemctl("stop")
    entity
  end

  # Report the real systemd state so HA stays in sync.
  defp reflect_state(entity) do
    if active?(), do: set_on(entity), else: set_off(entity)
  end

  defp active? do
    match?({_, 0}, sh("systemctl", ["is-active", "--quiet", @service]))
  end

  defp systemctl(action) do
    case sh("sudo", ["-n", "systemctl", action, @service]) do
      {_, 0} ->
        Logger.info("#{@service} #{action} ok")

      {out, code} ->
        Logger.warning("Failed to #{action} #{@service} (exit #{code}): #{String.trim(out)}")
    end
  end

  # Run a command in an unlinked process. The Homex entity traps exits, so
  # calling System.cmd here directly leaves a stray {:EXIT, port, :normal} in
  # the mailbox that the generated handle_info/2 clauses don't match, crashing
  # the entity. Spawning keeps the port's link out of this process.
  defp sh(cmd, args) do
    parent = self()
    ref = make_ref()
    spawn(fn -> send(parent, {ref, System.cmd(cmd, args, stderr_to_stdout: true)}) end)

    receive do
      {^ref, result} -> result
    after
      15_000 -> {"timed out", 1}
    end
  end
end
