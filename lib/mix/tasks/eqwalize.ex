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
    maybe_populate_with_fake_erl_sources(dir)

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
    maybe_populate_with_fake_erl_sources(dir)

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
      %{
        name: to_string(app),
        dir: Application.app_dir(app),
        ebin: Application.app_dir(app, "ebin"),
        src_dirs: ["src"],
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

  defp maybe_populate_with_fake_erl_sources(dir) do
    src_path = Path.join(dir, "src")
    unless File.exists?(src_path) do
      File.mkdir!(src_path)
      populate_with_fake_erl_sources(dir)
    end
  end

  defp populate_with_fake_erl_sources(dir) do
    dir
    |> Path.join("ebin")
    |> modules_from()
    |> Enum.each(fn module ->
      [dir, "src", "#{module}.erl"]
      |> Path.join()
      |> File.touch!()
    end)
  end
end
