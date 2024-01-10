defmodule Mix.Tasks.Eqwalize do
  @shortdoc "Eqwalize all modules in a project"
  @requirements ["compile"]

  use Mix.Task

  alias Exqwalizer.{EqwalizerClient, AppInfo}

  @impl Mix.Task
  def run(_args) do
    eqwalizer_path = System.fetch_env!("ELP_EQWALIZER_PATH")
    build_path = Mix.Project.build_path()
    dest_dir = Path.join(build_path, "eqwalizer-fakelib")
    build_info = build_info(dest_dir)
    modules = project_modules()

    EqwalizerClient.new(eqwalizer_path, build_info, modules)
  end

  defp build_info(dest_dir) do
    deps =
      Enum.map(Mix.Dep.cached(), fn dep ->
        build_dep_info(dest_dir, dep)
      end)

    %{
      apps: List.wrap(build_app_info(dest_dir)),
      deps: deps ++ elixir_info(dest_dir),
      otp_lib_dir: to_string(:code.lib_dir()),
      source_root: File.cwd!()
    }
  end

  defp build_app_info(dest_dir) do
    config = Mix.Project.config()
    app = Keyword.fetch!(config, :app)
    name = to_string(app)
    compile_path = Mix.Project.compile_path()
    AppInfo.prepare(dest_dir, name, compile_path)
  end

  defp build_dep_info(dest_dir, %Mix.Dep{app: app, opts: _opts} = dep) do
    name = to_string(app)
    [load_path] = Mix.Dep.load_paths(dep)
    AppInfo.prepare(dest_dir, name, load_path)
  end

  defp elixir_info(dest_dir) do
    for app <- ~w[logger elixir]a do
      name = to_string(app)

      ebin =
        app
        |> Application.app_dir("ebin")
        |> Path.expand()

      AppInfo.prepare(dest_dir, name, ebin)
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
    |> Enum.sort()
  end
end
