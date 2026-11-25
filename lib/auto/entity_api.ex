defmodule Auto.EntityApi do
  @moduledoc """
  HTTP API on the tailnet address for scripting a handful of Home Assistant
  entities, e.g. power-cycling hardware under test.

  Only entities listed under `config :auto, Auto.EntityApi, entities:` are
  reachable, by their short name or their entity id. There is no auth beyond
  the bind address: anyone the tailnet ACLs let reach this host can use it.

      GET  /entities               all exposed entities and their states
      GET  /entities/:name         one entity
      POST /entities/:name/on      turn on   (switch, light, fan, input_boolean)
      POST /entities/:name/off     turn off
      POST /entities/:name/toggle  toggle

  The POSTs wait until HA reports the new state (up to 10 s, or
  `?timeout_ms=`, max 60 s) and answer 200 with it, or 504 if the device never confirmed.

      curl -fsS -X POST http://<host>:4040/entities/board-outlet-1/off
  """
  use Plug.Router

  require Logger

  alias Auto.HomeAssistant.Rest

  @switchable ~w(switch light fan input_boolean)
  @poll_ms 200
  @default_timeout_ms 10_000
  @max_timeout_ms 60_000

  def child_spec(_opts) do
    config = Application.get_env(:auto, __MODULE__, [])

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_listener, [config]},
      type: :supervisor
    }
  end

  @doc false
  def start_listener(config) do
    case Keyword.get(config, :ip) do
      nil ->
        # Never fall back to a wildcard bind: this API has no auth of its own.
        Logger.warning("Auto.EntityApi not started: no tailnet address (HOME_IP unset)")
        :ignore

      ip ->
        port = Keyword.get(config, :port, 4040)
        Logger.info("Auto.EntityApi listening on http://#{:inet.ntoa(ip)}:#{port}")
        Plug.Cowboy.http(__MODULE__, [], ip: ip, port: port)
    end
  end

  plug(Plug.Logger, log: :debug)
  plug(:match)
  plug(:dispatch)

  get "/entities" do
    entities =
      Enum.map(entities(), fn {name, entity_id} ->
        case Rest.get_state(entity_id) do
          {:ok, state} -> render(name, state)
          {:error, reason} -> %{name: name, entity_id: entity_id, error: describe(reason)}
        end
      end)

    json(conn, 200, entities)
  end

  get "/entities/:name" do
    with {:ok, name, entity_id} <- lookup(name),
         {:ok, state} <- Rest.get_state(entity_id) do
      json(conn, 200, render(name, state))
    else
      error -> error_response(conn, error)
    end
  end

  post "/entities/:name/:action" when action in ~w(on off toggle) do
    with {:ok, name, entity_id} <- lookup(name),
         {:ok, timeout} <- timeout(conn),
         {:ok, domain} <- switchable(entity_id),
         {:ok, current} <- Rest.get_state(entity_id),
         {:ok, target} <- target(action, current["state"]),
         {:ok, _changed} <- Rest.call_service(domain, service(target), %{entity_id: entity_id}) do
      case await_state(entity_id, target, deadline(timeout)) do
        {:ok, state} ->
          Logger.info("EntityApi: #{entity_id} #{action} -> #{target}")
          json(conn, 200, render(name, state))

        {:timeout, state} ->
          json(conn, 504, %{
            error: "#{entity_id} did not report #{target} within #{timeout} ms",
            last: state && render(name, state)
          })
      end
    else
      error -> error_response(conn, error)
    end
  end

  match _ do
    json(conn, 404, %{error: "not found", entities: Map.keys(entities())})
  end

  defp entities, do: Map.new(Application.get_env(:auto, __MODULE__, [])[:entities] || %{})

  # Accept either the short name or the exposed entity id.
  defp lookup(name) do
    entities = entities()

    cond do
      Map.has_key?(entities, name) -> {:ok, name, entities[name]}
      found = Enum.find(entities, fn {_, id} -> id == name end) -> {:ok, elem(found, 0), name}
      true -> {:error, :unknown_entity}
    end
  end

  defp switchable(entity_id) do
    [domain | _] = String.split(entity_id, ".", parts: 2)
    if domain in @switchable, do: {:ok, domain}, else: {:error, :not_switchable}
  end

  defp target("on", _), do: {:ok, "on"}
  defp target("off", _), do: {:ok, "off"}
  defp target("toggle", "on"), do: {:ok, "off"}
  defp target("toggle", "off"), do: {:ok, "on"}
  defp target("toggle", other), do: {:error, {:unavailable, other}}

  defp service("on"), do: "turn_on"
  defp service("off"), do: "turn_off"

  defp timeout(conn) do
    conn = Plug.Conn.fetch_query_params(conn)

    case Integer.parse(conn.query_params["timeout_ms"] || "#{@default_timeout_ms}") do
      {ms, ""} when ms >= 0 -> {:ok, min(ms, @max_timeout_ms)}
      _ -> {:error, :bad_timeout}
    end
  end

  defp deadline(ms), do: System.monotonic_time(:millisecond) + ms

  defp await_state(entity_id, target, deadline, last \\ nil) do
    case Rest.get_state(entity_id) do
      {:ok, %{"state" => ^target} = state} ->
        {:ok, state}

      result ->
        last = with({:ok, state} <- result, do: state, else: (_ -> last))

        if System.monotonic_time(:millisecond) >= deadline do
          {:timeout, last}
        else
          Process.sleep(@poll_ms)
          await_state(entity_id, target, deadline, last)
        end
    end
  end

  defp render(name, state) do
    %{
      name: name,
      entity_id: state["entity_id"],
      state: state["state"],
      friendly_name: state["attributes"]["friendly_name"],
      last_changed: state["last_changed"],
      last_updated: state["last_updated"]
    }
  end

  defp error_response(conn, {:error, :unknown_entity}),
    do: json(conn, 404, %{error: "unknown entity", entities: Map.keys(entities())})

  defp error_response(conn, {:error, :not_switchable}),
    do:
      json(conn, 422, %{error: "entity can't be switched, only #{Enum.join(@switchable, ", ")}"})

  defp error_response(conn, {:error, :bad_timeout}),
    do: json(conn, 400, %{error: "timeout_ms must be a non-negative integer"})

  defp error_response(conn, {:error, {:unavailable, state}}),
    do: json(conn, 503, %{error: "entity is #{state}, can't toggle"})

  defp error_response(conn, {:error, :not_found}),
    do: json(conn, 502, %{error: "Home Assistant doesn't know this entity"})

  defp error_response(conn, {:error, reason}),
    do: json(conn, 502, %{error: describe(reason)})

  defp describe({:auth, _}), do: "Home Assistant login failed"
  defp describe({:transport, message}), do: "Home Assistant unreachable: #{message}"
  defp describe({:http, status, _}), do: "Home Assistant answered #{status}"
  defp describe(:not_found), do: "Home Assistant doesn't know this entity"
  defp describe(other), do: inspect(other)

  defp json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end
end
