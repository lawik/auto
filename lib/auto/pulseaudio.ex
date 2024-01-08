defmodule Auto.Pulseaudio do
    @cmd "pactl"
    @format "--format=json"

    def default_source do
        run("get-default-source")
    end

    def default_sink do
        run("get-default-sink")
    end

    def find_source(device) when is_binary(device) do
        devices = run_formatted("list")
        Enum.find(devices["sources"], & &1["name"] == device)
    end

    def find_sink(device) when is_binary(device) do
        devices = run_formatted("list")
        Enum.find(devices["sinks"], & &1["name"] == device)
    end

    def device_volume_percent(%{} = device) do
        [percent] =
            device["volume"]
            |> Enum.map(fn {_element, settings} ->
                settings["value_percent"]
            end)
            |> Enum.uniq

        percent
    end

    def change_default_source_volume(percent) do
        source = default_source()
        change =
            if percent > 0 do
                "+#{percent}%"
            else
                "#{percent}%"
            end

        run(["set-source-volume", source, change])
    end

    def change_default_sink_volume(percent) do
        source = default_sink()
        change =
            if percent > 0 do
                "+#{percent}%"
            else
                "#{percent}%"
            end

        run(["set-sink-volume", source, change])
    end

    defp run(cmds) do
        cmds = if is_binary(cmds) do
            [cmds]
        else
            cmds
        end
        case System.cmd(@cmd, cmds) do
            {txt, 0} ->
                txt
                |> String.trim
            other ->
                IO.inspect({cmds, other}, label: "run error")
                {:error, {:result, other}}
        end
    end

    defp run_formatted(cmds) do
        cmds = if is_binary(cmds) do
            [cmds]
        else
            cmds
        end
        case System.cmd(@cmd, [@format | cmds]) do
            {json, 0} ->
                json
                |> Jason.decode!()
            other ->
                IO.inspect({cmds, other}, label: "run formatted error")
                {:error, {:result, other}}
        end
    end
end