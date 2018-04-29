defmodule FarmbotIrc.AmqpConnection do
  use GenServer
  use AMQP
  @exchange "amq.topic"
  require Logger

  def start_link(token) when is_binary(token) do
    GenServer.start_link(__MODULE__, [token, self()])
  end

  defmodule State do
    defstruct [:conn, :chan, :queue_name, :bot, :pid]
  end

  def init([token, pid]) do
    import Farmbot.Jwt, only: [decode: 1]

    with {:ok, %{bot: device, mqtt: mqtt_host, vhost: vhost}} <- decode(token),
         {:ok, conn} <- open_connection(token, device, mqtt_host, vhost),
         {:ok, chan} <- AMQP.Channel.open(conn),
         true <- Process.link(conn.pid),
         true <- Process.link(chan.pid),
         q_name <- Enum.join([device, "IRCCLIENT", UUID.uuid1()], "-"),
         :ok <- Basic.qos(chan, global: true),
         {:ok, _} <- AMQP.Queue.declare(chan, q_name, auto_delete: true),
         from_device <- [routing_key: "bot.#{device}.from_device"],
         logs <- [routing_key: "bot.#{device}.logs"],
         status <- [routing_key: "bot.#{device}.status"],
         :ok <- AMQP.Queue.bind(chan, q_name, @exchange, from_device),
         :ok <- AMQP.Queue.bind(chan, q_name, @exchange, logs),
         :ok <- AMQP.Queue.bind(chan, q_name, @exchange, status),
         {:ok, _tag} <- Basic.consume(chan, q_name, self(), no_ack: true),
         opts <- [conn: conn, chan: chan, queue_name: q_name, bot: device, pid: pid],
         state <- struct(State, opts) do
      {:ok, state}
    else
      err -> {:stop, err}
    end
  end

  defp open_connection(token, device, mqtt_server, vhost) do
    opts = [host: mqtt_server, username: device, password: token, virtual_host: vhost]
    AMQP.Connection.open(opts)
  end

  def handle_info({:basic_consume_ok, _}, state) do
    Logger.debug("Connected to Farmbot: #{state.bot}")
    {:noreply, state}
  end

  # Sent by the broker when the consumer is
  # unexpectedly cancelled (such as after a queue deletion)
  def handle_info({:basic_cancel, info}, state) do
    IO.inspect(info, label: "basic_cancel")
    {:stop, :normal, state}
  end

  # Confirmation sent by the broker to the consumer process after a Basic.cancel
  def handle_info({:basic_cancel_ok, _}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, %{routing_key: key}}, state) do
    device = state.bot
    route = String.split(key, ".")
    payload = Poison.decode!(payload)

    case route do
      ["bot", ^device, "from_device"] ->
        handle_from_device(payload, state)

      ["bot", ^device, "logs"] ->
        handle_logs(payload, state)

      ["bot", ^device, "status"] ->
        handle_status(payload, state)

      _ ->
        Logger.warn("got unknown routing key: #{key} for device: #{device}")
        {:noreply, [], state}
    end
  end

  def handle_from_device(payload, state) do
    send(state.pid, {state.bot, :from_device, payload})
    {:noreply, state}
  end

  def handle_logs(payload, state) do
    send(state.pid, {state.bot, :log, payload})
    {:noreply, state}
  end

  def handle_status(payload, state) do
    send(state.pid, {state.bot, :state, payload})
    {:noreply, state}
  end
end
