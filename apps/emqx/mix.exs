defmodule EMQX.MixProject do
  use Mix.Project

  alias EMQXUmbrella.MixProject, as: UMP

  def project do
    [
      app: :emqx,
      version: "6.0.0",
      build_path: "../../_build",
      erlc_paths: erlc_paths(),
      erlc_options: [
        {:i, "src"},
        :warn_unused_vars,
        :warn_shadow_vars,
        :warn_unused_import,
        :warn_obsolete_guard,
        :compressed
        | UMP.erlc_options()
      ],
      compilers: Mix.compilers() ++ [:copy_srcs],
      # used by our `Mix.Tasks.Compile.CopySrcs` compiler
      extra_dirs: extra_dirs(),
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications
  def application do
    [
      extra_applications:
        [:public_key, :ssl, :os_mon, :mnesia, :sasl, :mria] ++ UMP.extra_applications(),
      mod: {:emqx_app, []}
    ]
  end

  def deps() do
    [
      {:emqx_mix_utils, in_umbrella: true, runtime: false},
      {:emqx_utils, in_umbrella: true},
      {:emqx_bpapi, in_umbrella: true},
      {:emqx_durable_storage, in_umbrella: true},
      {:emqx_ds_backends, in_umbrella: true},
      UMP.common_dep(:gproc),
      UMP.common_dep(:gen_rpc),
      UMP.common_dep(:ekka),
      UMP.common_dep(:esockd),
      UMP.common_dep(:cowboy),
      UMP.common_dep(:lc),
      UMP.common_dep(:hocon),
      UMP.common_dep(:ranch),
      UMP.common_dep(:bcrypt),
      UMP.common_dep(:emqx_http_lib),
      UMP.common_dep(:typerefl),
      UMP.common_dep(:snabbkaffe),
      UMP.common_dep(:recon)
    ] ++ UMP.quicer_dep()
  end

  defp erlc_paths() do
    paths = UMP.erlc_paths()

    if UMP.test_env?() do
      ["integration_test" | paths]
    else
      paths
    end
  end

  defp extra_dirs() do
    dirs = ["src", "etc"]

    if UMP.test_env?() do
      ["test", "integration_test" | dirs]
    else
      dirs
    end
  end
end
