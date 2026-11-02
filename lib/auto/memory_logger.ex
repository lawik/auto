defmodule Auto.MemoryLogger do
  @moduledoc """
  Periodically logs VM memory usage so slow leaks can be traced after the fact.

  Every `@log_interval` it logs a summary line (`:erlang.memory/0` categories, OS RSS,
  process/port/atom counts) followed by the top processes by heap memory, the top
  processes by refc binaries held, any process with a long message queue, and the
  largest ETS tables. All lines are prefixed with `[memory]` for easy grepping:

      journalctl --user -u auto -g '\\[memory\\]'
  """
  use GenServer
  require Logger

  @log_interval :timer.minutes(5)
  @top 5
  @long_queue 1_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    send(self(), :log)
    {:ok, %{}}
  end

  def handle_info(:log, state) do
    log_summary()
    log_processes()
    log_ets()
    Process.send_after(self(), :log, @log_interval)
    {:noreply, state}
  end

  defp log_summary do
    mem = :erlang.memory()

    Logger.info(
      "[memory] total=#{mb(mem[:total])} rss=#{mb(os_rss())} processes=#{mb(mem[:processes])} " <>
        "binary=#{mb(mem[:binary])} ets=#{mb(mem[:ets])} code=#{mb(mem[:code])} " <>
        "atom=#{mb(mem[:atom])} system=#{mb(mem[:system])} " <>
        "procs=#{:erlang.system_info(:process_count)} ports=#{:erlang.system_info(:port_count)} " <>
        "atoms=#{:erlang.system_info(:atom_count)}"
    )
  end

  defp log_processes do
    infos =
      for pid <- Process.list(),
          info = Process.info(pid, [:memory, :message_queue_len, :binary, :registered_name]),
          info != nil do
        binary = info[:binary] |> Enum.map(&elem(&1, 1)) |> Enum.sum()
        %{pid: pid, memory: info[:memory], queue: info[:message_queue_len], binary: binary, name: info[:registered_name]}
      end

    infos
    |> Enum.sort_by(& &1.memory, :desc)
    |> Enum.take(@top)
    |> Enum.each(fn p ->
      Logger.info("[memory] top heap #{mb(p.memory)} queue=#{p.queue} bin=#{mb(p.binary)} #{describe(p)}")
    end)

    infos
    |> Enum.sort_by(& &1.binary, :desc)
    |> Enum.take(@top)
    |> Enum.each(fn p ->
      Logger.info("[memory] top binary #{mb(p.binary)} heap=#{mb(p.memory)} #{describe(p)}")
    end)

    infos
    |> Enum.filter(&(&1.queue >= @long_queue))
    |> Enum.each(fn p ->
      Logger.warning("[memory] long queue #{p.queue} heap=#{mb(p.memory)} #{describe(p)}")
    end)
  end

  defp log_ets do
    word_size = :erlang.system_info(:wordsize)

    :ets.all()
    |> Enum.map(fn tab -> {tab, :ets.info(tab, :memory), :ets.info(tab, :size), :ets.info(tab, :owner)} end)
    |> Enum.reject(fn {_, memory, _, _} -> memory == :undefined end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.take(@top)
    |> Enum.each(fn {tab, words, size, owner} ->
      Logger.info("[memory] top ets #{mb(words * word_size)} rows=#{size} table=#{inspect(tab)} owner=#{inspect(owner)}")
    end)
  end

  defp describe(%{pid: pid, name: name}) do
    label =
      case name do
        name when is_atom(name) -> inspect(name)
        _ -> pid |> :proc_lib.translate_initial_call() |> format_mfa()
      end

    "#{inspect(pid)} #{label}"
  end

  defp format_mfa({m, f, a}), do: "#{inspect(m)}.#{f}/#{a}"
  defp format_mfa(other), do: inspect(other)

  defp os_rss do
    with {:ok, status} <- File.read("/proc/self/status"),
         [_, kb] <- Regex.run(~r/VmRSS:\s+(\d+) kB/, status) do
      String.to_integer(kb) * 1024
    else
      _ -> 0
    end
  end

  defp mb(bytes), do: "#{Float.round(bytes / 1_048_576, 1)}M"
end
