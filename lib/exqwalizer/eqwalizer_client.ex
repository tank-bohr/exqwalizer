defmodule Exqwalizer.EqwalizerClient do
  def new(eqwalizer_path, build_info, modules) do
    {cmd, base_args} = eqwalizer_cmd(eqwalizer_path)

    port_opts = [
      :hide,
      :binary,
      :use_stdio,
      line: 65_536,
      cd: File.cwd!(),
      env: env(build_info),
      args: base_args ++ ["ipc" | modules]
    ]

    port = Port.open({:spawn_executable, cmd}, port_opts)
    loop(port)
  end

  defp loop(port) do
    with {:ok, data} <- receive_line(port),
         {:ok, request} <- Jason.decode(data, keys: :atoms) do
      loop_command(request, port)
    end
  end

  defp loop_command(%{tag: "EqwalizingStart", content: %{module: module}}, port) do
    IO.puts("EqwalizingStart #{module}")
    loop(port)
  end

  defp loop_command(%{tag: "GetAstBytes", content: %{module: module}}, port) do
    IO.puts("GetAstBytes #{module}")
    compile_path = Mix.Project.compile_path()
    beam_path = Path.join(compile_path, "#{module}.beam")
    {:ok, beam} = File.read(beam_path)
    {:ok, {_mod, chunks}} = :beam_lib.chunks(beam, [:abstract_code])
    {_, abstract_code} = chunks[:abstract_code]
    send_ast_bytes(port, abstract_code)
    loop(port)
  end

  defp loop_command(%{tag: "EqwalizingDone", content: %{module: module}}, port) do
    IO.puts("EqwalizingDone #{module}")
    loop(port)
  end

  defp loop_command(%{tag: "Done", content: %{diagnostics: diagnostics}}, port) do
    if Enum.any?(diagnostics) do
      print_diagnostics(diagnostics)
    else
      IO.puts("Congratulations! No errors")
    end
    Port.close(port)
  end

  defp print_diagnostics(diagnostics) do
    for {module, results} <- diagnostics do
      IO.puts("Diagnostics for module #{module}:")
      for result <- results do
        %{message: message, uri: uri, expressionOrNull: expressionOrNull} = result
        IO.puts(message)
        IO.puts("see: #{uri}")
        if expressionOrNull do
          expressionOrNull
          |> Erlex.pretty_print()
          |> IO.puts()
        end
        |> IO.puts()
      end
    end
  end

  defp env(build_info) do
    build_info_path = dump_build_info(build_info)

    Enum.map(%{
      "EQWALIZER_BUILD_INFO" => build_info_path,
      "EQWALIZER_ELP_AST_DIR" => "elp-ast",
      "EQWALIZER_GRADUAL_TYPING" => "true",
      "EQWALIZER_EQWATER" => "true",
      "EQWALIZER_TOLERATE_ERRORS" => "true",
      "EQWALIZER_CHECK_REDUNDANT_GUARDS" => "false",
      "EQWALIZER_MODE" => "mini_elp",
      "EQWALIZER_ERROR_DEPTH" => "4"
    }, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
  end

  defp dump_build_info(build_info) do
    content = :erlang.term_to_binary(build_info)

    System.tmp_dir!()
    |> Path.join(gen_tmp_name())
    |> tap(&File.write!(&1, content))
  end

  defp eqwalizer_cmd(eqwalizer_path) do
    case Path.extname(eqwalizer_path) do
      ".jar" ->
        java_path = :os.find_executable('java') || :erlang.error(:enoent)
        {java_path, ["-Xss10M", "-jar", eqwalizer_path]}

      _non_jar_ext ->
        {String.to_charlist(eqwalizer_path), []}
    end
  end

  defp receive_line(port), do: receive_line(port, [])

  defp receive_line(port, buffer) do
    receive do
      {^port, {:data, {:noeol, data}}} ->
        receive_line(port, [data | buffer])

      {^port, {:data, {:eol, data}}} ->
        data = [data | buffer] |> Enum.reverse() |> IO.iodata_to_binary()
        {:ok, data}
    end
  end

  defp send_ast_bytes(port, abstract_code) do
    content = :erlang.term_to_binary({:ok, abstract_code})
    ast_bytes_len = byte_size(content)
    reply = Jason.encode!(%{
      tag: "GetAstBytesReply",
      content: %{ast_bytes_len: ast_bytes_len}
    })
    Port.command(port, reply)
    send_newline(port)
    {:ok, ""} = receive_line(port)
    Port.command(port, content)
  end

  defp send_newline(port) do
    Port.command(port, "\n")
  end

  defp gen_tmp_name() do
    7
    |> :crypto.strong_rand_bytes()
    |> Base.encode64(padding: false)
    |> String.replace("/", "")
    |> then(fn key -> "tmp" <> key end)
  end
end
