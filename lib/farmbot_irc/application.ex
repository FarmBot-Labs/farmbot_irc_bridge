defmodule FarmbotIrc.Application do
  use Application

  def start(_, _) do
    children = [
      {FarmbotIrc.IrcConnection, []}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end
end
