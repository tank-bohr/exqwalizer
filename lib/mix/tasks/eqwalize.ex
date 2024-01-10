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
    app = Keyword.fetch!(config, :app)
    name = to_string(app)
    compile_path = Mix.Project.compile_path()
    prepare_app(name, compile_path)
  end

  defp build_dep_info(%Mix.Dep{app: app, opts: _opts} = dep) do
    name = to_string(app)
    [load_path] = Mix.Dep.load_paths(dep)
    prepare_app(name, load_path)
  end

  defp elixir_info() do
    for app <- ~w[logger elixir]a do
      name = to_string(app)

      ebin =
        app
        |> Application.app_dir("ebin")
        |> Path.expand()

      prepare_app(name, ebin)
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

  defp prepare_app(app, compile_path) do
    build_path = Mix.Project.build_path()
    dest_dir = Path.join([build_path, "eqwalizer-fakelib", app])
    beam_files = Path.wildcard("#{compile_path}/*.beam")
    ebin_path = dest_dir |> Path.join("ebin") |> tap(&File.mkdir_p!/1)
    src_path = dest_dir |> Path.join("src") |> tap(&File.mkdir_p!/1)

    Enum.each(beam_files, fn file_path ->
      module = module_name_by_beam_file_path(file_path)
      new_beam_path = Path.join(ebin_path, "#{module}.beam")

      if String.starts_with?(module, "Elixir.") do
        {:ok, beam} = replace_debug_chunk(file_path)
        File.write!(new_beam_path, beam)
      else
        File.cp!(file_path, new_beam_path)
      end

      src_path
      |> Path.join("#{module}.erl")
      |> File.touch!()
    end)

    %{
      name: app,
      dir: dest_dir,
      ebin: ebin_path,
      src_dirs: ["src"],
      extra_src_dirs: [],
      include_dirs: [],
      macros: []
    }
  end

  defp module_name_by_beam_file_path(file_path) do
    file_path
    |> Path.basename()
    |> Path.rootname(".beam")
  end

  defp replace_debug_chunk(file_path) do
    file_path = String.to_charlist(file_path)
    {:ok, module, all_chunks} = :beam_lib.all_chunks(file_path)

    new_chunks =
      case :lists.keytake(~c"Dbgi", 1, all_chunks) do
        {:value, {~c"Dbgi", debug_chunk}, chunks} ->
          {:debug_info_v1, backend, data} = :erlang.binary_to_term(debug_chunk)
          {:elixir_v1, %{compile_opts: compile_opts}, _specs} = data
          {:ok, abstract_code} = backend.debug_info(:erlang_v1, module, data, [])
          :exqwalizer_erl_parse_transform.parse_transform(abstract_code, [])
          new_chunk =
            :erlang.term_to_binary(
              {:debug_info_v1, :erl_abstract_code, {abstract_code, compile_opts}}
            )

          [{~c"Dbgi", new_chunk} | chunks]

        false ->
          all_chunks
      end

    :beam_lib.build_module(new_chunks)
  end
end
