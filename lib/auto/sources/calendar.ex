defmodule Auto.Sources.Calendars do
  use GenServer
  require Logger

  @check_interval 60_000
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  def init(opts) do
    send(self(), :check_calendars)
    {:ok, %{calendar_urls: opts[:calendars], calendar_events: %{}}}
  end

  def handle_info(:check_calendars, state) do
    calendar_events =
      for url <- state.calendar_urls, into: %{} do
        events =
          url
          |> download()
          |> to_events()

        {url, events}
      end

    now = DateTime.utc_now()

    current_events =
      calendar_events
      |> Enum.flat_map(&elem(&1, 1))
      |> Enum.uniq_by(&Map.take(&1, [:dtstart, :dtend, :name]))
      |> sort_by_start()
      |> Enum.filter(fn event ->
        DateTime.compare(now, event.dtstart) == :gt
      end)

    next_events =
      calendar_events
      |> Enum.flat_map(&elem(&1, 1))
      |> Enum.uniq_by(&Map.take(&1, [:dtstart, :dtend, :name]))
      |> sort_by_start()
      |> Enum.reject(fn event ->
        DateTime.compare(now, event.dtstart) == :gt
      end)
      |> Enum.take(5)

    if current_events != [] do
      broadcast_current(current_events)
    end

    if next_events != [] do
      broadcast_upcoming(next_events)
    end

    Process.send_after(self(), :check_calendars, @check_interval)
    {:noreply, %{state | calendar_events: calendar_events}}
  end

  defp download(calendar_url) do
    response =
      :get
      |> Finch.build(calendar_url)
      |> Finch.request(Auto.Finch)

    case response do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      error_response ->
        Logger.error("Could not download URL: #{inspect(error_response)}")
        :skip
    end
  end

  defp to_events({:ok, data}) do
    data
    |> ICalendar.from_ics()
    |> expand_recurrence()
    |> reject_past_events()
    |> sort_by_start()
  end

  defp to_events(:skip) do
    []
  end

  defp expand_recurrence(events, weeks_from_now \\ 1) do
    now = DateTime.utc_now()
    end_date = now |> Date.add(weeks_from_now * 7)

    events
    |> Enum.filter(fn %{rrule: rule} ->
      not is_nil(rule)
    end)
    |> Enum.flat_map(fn event ->
      event
      |> ICalendar.Recurrence.get_recurrences(end_date)
      |> Enum.to_list()
    end)
    |> Enum.concat(events)
  end

  defp reject_past_events(events) do
    now = DateTime.utc_now()

    Enum.reject(events, fn %{dtend: dtend} ->
      is_nil(dtend) or DateTime.compare(now, dtend) == :gt
    end)
  end

  defp sort_by_start(events) do
    Enum.sort_by(events, & &1.dtstart, DateTime)
  end

  defp broadcast_current(events) do
    Phoenix.PubSub.broadcast(Auto.PubSub, "calendar", {:current_events, events})
  end

  defp broadcast_upcoming(events) do
    Phoenix.PubSub.broadcast(Auto.PubSub, "calendar", {:upcoming_events, events})
  end
end
