defmodule Exqwalizer.AppInfo do
  def prepare(dest_dir, app, compile_path) do
    dest_dir = Path.join(dest_dir, app)
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
          abstract_code = :exqwalizer_erl_parse_transform.parse_transform(abstract_code, [])

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
