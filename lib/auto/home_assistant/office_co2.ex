defmodule Auto.HomeAssistant.OfficeCO2 do
  use Homex.Entity.Sensor,
    name: "office-co2",
    unit_of_measurement: "",
    device_class: "co2",
    retain: true

  def handle_init(entity) do
    Phoenix.PubSub.subscribe(Auto.PubSub, "airquality")
    entity
  end

  def handle_message({:air_quality_data, data}, entity) do
    entity |> set_value(data.co2)
  end
end
