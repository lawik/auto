defmodule Auto.HomeAssistant.Rest do
  @moduledoc """
  Home Assistant REST API client authenticated as a regular HA user.

  HA's REST API takes bearer tokens only, so this runs the same login flow as
  the web UI with the username and password: the access token it gets lasts 30
  minutes and is renewed with the refresh token. A full login only happens on
  the first request and when the refresh token is rejected, so each boot adds
  one refresh token (client "http://auto/") to the user's HA profile.

  The process only hands out tokens; requests run in the caller.
  """
  use GenServer

  require Logger

  @client_id "http://auto/"
  @timeout 10_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Current state of an entity, as HA returns it from /api/states/<entity_id>."
  def get_state(entity_id), do: request(:get, "/api/states/#{entity_id}")

  @doc "Calls `domain.service` with `data` (e.g. `%{entity_id: \"switch.x\"}`)."
  def call_service(domain, service, data),
    do: request(:post, "/api/services/#{domain}/#{service}", json: data)

  defp request(method, path, extra \\ [], retry? \\ true) do
    with {:ok, url, token} <- GenServer.call(__MODULE__, :token, 5 * @timeout) do
      opts =
        [
          method: method,
          url: url <> path,
          auth: {:bearer, token},
          receive_timeout: @timeout,
          retry: false
        ] ++ extra

      case Req.request(opts) do
        {:ok, %{status: 401}} when retry? ->
          GenServer.cast(__MODULE__, {:invalidate, token})
          request(method, path, extra, false)

        {:ok, %{status: status, body: body}} when status in 200..299 ->
          {:ok, body}

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, %{status: status, body: body}} ->
          {:error, {:http, status, body}}

        {:error, exception} ->
          {:error, {:transport, Exception.message(exception)}}
      end
    end
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       url: String.trim_trailing(Keyword.fetch!(opts, :url), "/"),
       username: Keyword.fetch!(opts, :username),
       password: Keyword.fetch!(opts, :password),
       access: nil,
       refresh: nil,
       expires_at: 0
     }}
  end

  @impl true
  def handle_call(:token, _from, state) do
    case ensure_token(state) do
      {:ok, state} -> {:reply, {:ok, state.url, state.access}, state}
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:invalidate, token}, %{access: token} = state),
    do: {:noreply, %{state | access: nil, expires_at: 0}}

  def handle_cast({:invalidate, _stale}, state), do: {:noreply, state}

  defp ensure_token(state) do
    cond do
      state.access && now() < state.expires_at - 60 ->
        {:ok, state}

      state.refresh ->
        case refresh(state) do
          {:ok, state} ->
            {:ok, state}

          {:error, reason} ->
            Logger.info("HA token refresh failed (#{inspect(reason)}), logging in again")
            login(%{state | refresh: nil})
        end

      true ->
        login(state)
    end
  end

  defp refresh(state) do
    with {:ok, tokens} <-
           token_request(state, grant_type: "refresh_token", refresh_token: state.refresh) do
      {:ok, store(state, tokens)}
    end
  end

  defp login(state) do
    result =
      with {:ok, %{"flow_id" => flow}} <-
             post(state, "/auth/login_flow", %{
               client_id: @client_id,
               handler: ["homeassistant", nil],
               redirect_uri: @client_id
             }),
           {:ok, %{"type" => "create_entry", "result" => code}} <-
             post(state, "/auth/login_flow/#{flow}", %{
               client_id: @client_id,
               username: state.username,
               password: state.password
             }),
           {:ok, tokens} <- token_request(state, grant_type: "authorization_code", code: code) do
        {:ok, tokens}
      else
        {:ok, %{"errors" => errors}} -> {:error, {:login_rejected, errors}}
        {:ok, other} -> {:error, {:login_unexpected, other}}
        {:error, reason} -> {:error, reason}
      end

    case result do
      {:ok, tokens} ->
        Logger.info("Logged in to Home Assistant at #{state.url}")
        {:ok, store(state, tokens)}

      {:error, reason} ->
        Logger.warning("Home Assistant login failed: #{inspect(reason)}")
        {:error, {:auth, reason}, state}
    end
  end

  defp store(state, tokens) do
    %{
      state
      | access: tokens["access_token"],
        refresh: tokens["refresh_token"] || state.refresh,
        expires_at: now() + (tokens["expires_in"] || 1800)
    }
  end

  defp token_request(state, form) do
    form = Keyword.put(form, :client_id, @client_id)

    case Req.post(state.url <> "/auth/token", form: form, receive_timeout: @timeout, retry: false) do
      {:ok, %{status: 200, body: %{"access_token" => _} = body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
      {:error, exception} -> {:error, {:transport, Exception.message(exception)}}
    end
  end

  defp post(state, path, body) do
    case Req.post(state.url <> path, json: body, receive_timeout: @timeout, retry: false) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
      {:error, exception} -> {:error, {:transport, Exception.message(exception)}}
    end
  end

  defp now, do: System.monotonic_time(:second)
end
