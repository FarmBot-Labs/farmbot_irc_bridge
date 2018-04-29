defmodule FarmbotIrc.IrcConnection do
  @moduledoc "IrcConnection to the IRC server"
  use GenServer
  require Logger

  @host "176.58.89.200"
  @port 6667

  @pass ""
  @nick "FarmbotBot"
  @user @nick
  @name "Farmbot"
  @channel "#farmbot"

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def terminate(_, state) do
    # Quit the channel and close the underlying client connection when the process is terminating
    ExIrc.Client.quit(state.client, "Goodbye, cruel world.")
    ExIrc.Client.stop!(state.client)
    :ok
  end

  def init(_args) do
    {:ok, client} = ExIrc.start_link!()
    ExIrc.Client.add_handler(client, self())
    ExIrc.Client.connect!(client, @host, @port)
    {:ok, %{client: client, devices: %{}}}
  end

  def handle_info({:connected, _ip, _port}, state) do
    Logger.debug("Connected!")
    ExIrc.Client.logon(state.client, @pass, @nick, @user, @name)
    {:noreply, state}
  end

  def handle_info(:logged_in, state) do
    Logger.debug("Logged in!")
    ExIrc.Client.join(state.client, @channel)
    {:noreply, state}
  end

  def handle_info(:disconnected, state) do
    {:stop, state, :disconnected}
  end

  def handle_info({:joined, @channel}, state) do
    Logger.debug("Connected to #{@channel}")
    {:noreply, state}
  end

  def handle_info({:names_list, @channel, _str_list}, state) do
    {:noreply, state}
  end

  def handle_info({:mentioned, data, %ExIrc.SenderInfo{nick: nick}, @channel}, state) do
    Logger.debug("Mentioned by #{nick}: '#{data}'")
    {:noreply, state}
  end

  def handle_info({:received, msg, %ExIrc.SenderInfo{nick: nick}}, state) do
    Logger.debug("Got private message from #{nick}: '#{msg}'")

    case String.split(msg, " ") do
      ["connect", username, password, server] ->
        try do
          tkn = Farmbot.Jwt.fetch_token!(username, password, server)
          %{bot: bot} = Farmbot.Jwt.decode!(tkn)
          {:ok, pid} = FarmbotIrc.AmqpConnection.start_link(tkn)

          {:noreply,
           %{state | devices: Map.put(state.devices, bot, %{nick: nick, pid: pid, bot: bot})}}
        rescue
          excp ->
            ExIrc.Client.msg(
              state.client,
              :privmsg,
              nick,
              "Failed to connect: #{Exception.message(excp)}"
            )

            {:noreply, state}
        end

      _ ->
        ExIrc.Client.msg(state.client, :privmsg, nick, "Unhandled message: #{msg}")
        {:noreply, state}
    end
  end

  # Receive a message on a channel.
  def handle_info({:received, _msg, _sender_info, @channel}, state) do
    {:noreply, state}
  end

  def handle_info({bot, :from_device, _payload}, state) do
    case state.devices[bot] do
      %{nick: _nick} ->
        :ok

      _ ->
        Logger.warn("Unhandled rpc response from bot: #{bot}")
    end

    {:noreply, state}
  end

  def handle_info({bot, :log, payload}, state) do
    case state.devices[bot] do
      %{nick: nick} ->
        ExIrc.Client.msg(state.client, :privmsg, nick, payload["message"])

      _ ->
        Logger.warn("Unhandled message from bot: #{bot}")
    end

    {:noreply, state}
  end

  def handle_info({bot, :state, _payload}, state) do
    case state.devices[bot] do
      %{nick: _nick} ->
        :ok

      _ ->
        Logger.warn("Unhandled state update from bot: #{bot}")
    end

    {:noreply, state}
  end

  def handle_info(info, state) do
    IO.inspect(info, label: "Unexpected info")
    {:noreply, state}
  end
end
