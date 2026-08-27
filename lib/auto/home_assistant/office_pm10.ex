defmodule Auto.HomeAssistant.OfficePM10 do
  use Homex.Entity.Sensor,
    name: "office-pm10",
    unit_of_measurement: "µg/m³",
    device_class: "pm10",
    state_class: "measurement",
    retain: true

  def handle_init(entity) do
    Phoenix.PubSub.subscribe(Auto.PubSub, "airquality")
    entity
  end

  # A missing reading is left alone rather than published as a value.
  def handle_message({:air_quality_data, %{pm10: nil}}, entity), do: entity

  def handle_message({:air_quality_data, data}, entity) do
    entity |> set_value(data.pm10)
  end
end
