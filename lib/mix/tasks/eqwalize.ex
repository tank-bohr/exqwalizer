defmodule Mix.Tasks.Eqwalize do
  @shortdoc "Eqwalize all modules in a project"
  @requirements ["compile"]

  use Mix.Task

  alias Exqwalizer.EqwalizerClient

  @impl Mix.Task
  def run(_args) do
    eqwalizer_path = System.fetch_env!("ELP_EQWALIZER_PATH")
    build_info = build_info()
    modules = project_modules()

    EqwalizerClient.new(eqwalizer_path, build_info, modules)
  end

  defp build_info() do
    %{
      apps: List.wrap(build_app_info()),
      deps: Enum.map(Mix.Dep.cached(), &build_dep_info/1) ++ elixir_info(),
      otp_lib_dir: to_string(:code.lib_dir()),
      source_root: File.cwd!()
    }
  end

  defp build_app_info() do
    config = Mix.Project.config()
    name = Keyword.fetch!(config, :app)
    build_path = Mix.Project.build_path()
    dir = Path.join([build_path, "lib", Atom.to_string(name)])
    populate_with_fake_erl_sources(dir)

    %{
      name: to_string(name),
      dir: dir,
      ebin: "ebin",
      src_dirs: ["src"],
      extra_src_dirs: [],
      include_dirs: [],
      macros: []
    }
  end

  defp build_dep_info(%Mix.Dep{app: name, opts: opts}) do
    dir = Keyword.fetch!(opts, :build)
    populate_with_fake_erl_sources(dir)

    %{
      name: to_string(name),
      dir: dir,
      ebin: "ebin",
      src_dirs: ["src"],
      extra_src_dirs: [],
      include_dirs: [],
      macros: []
    }
  end

  defp elixir_info() do
    for app <- ~w[logger elixir]a do
      dir =
        app
        |> Application.app_dir()
        |> Path.expand()

      ebin =
        app
        |> Application.app_dir("ebin")
        |> Path.expand()

      src_dir =
        System.tmp_dir!()
        |> Path.join("exqwalizer-fake-sources-for-#{app}")
        |> tap(&populate_with_fake_erl_sources(&1, ebin))

      %{
        name: to_string(app),
        dir: dir,
        ebin: ebin,
        src_dirs: [src_dir],
        extra_src_dirs: [],
        include_dirs: [],
        macros: []
      }
    end
  end

  defp project_modules() do
    compile_path = Mix.Project.compile_path()
    modules_from(compile_path)
  end

  defp modules_from(compile_path) do
    "#{compile_path}/*.beam"
    |> Path.wildcard()
    |> Enum.map(fn beam ->
      beam
      |> Path.basename()
      |> Path.rootname(".beam")
    end)
    |> Enum.sort
  end

  defp populate_with_fake_erl_sources(dir) do
    sources_path = Path.join(dir, "src")
    compile_path = Path.join(dir, "ebin")
    populate_with_fake_erl_sources(sources_path, compile_path)
  end

  defp populate_with_fake_erl_sources(sources_path, compile_path) do
    File.mkdir_p!(sources_path)

    compile_path
    |> modules_from()
    |> Enum.each(fn module ->
      sources_path
      |> Path.join("#{module}.erl")
      |> File.touch!()
    end)
  end
end
