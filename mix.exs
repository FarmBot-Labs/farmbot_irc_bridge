defmodule FarbotIrc.MixProject do
  use Mix.Project

  def project do
    [
      app: :farbot_irc,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {FarmbotIrc.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:exirc, "~> 1.0"},
      {:amqp, "~> 1.0"},
      {:uuid, "~> 1.1"},
      {:poison, "~> 3.1"},
      {:httpoison, "~> 1.1"}
    ]
  end
end
