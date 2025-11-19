defmodule Auto.HomeAssistant.OfficeTemperature do
  use Homex.Entity.Sensor,
    name: "office-temperature",
    unit_of_measurement: "°C",
    device_class: "temperature",
    retain: true

  def handle_init(entity) do
    Phoenix.PubSub.subscribe(Auto.PubSub, "airquality")
    entity
  end

  def handle_message({:air_quality_data, data}, entity) do
    entity |> set_value(data.temperature)
  end
end
