# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2

defmodule Server do
  # _________________________________________________________ Server.start()
  def start(config, server_num) do
    config =
      config
      |> Configuration.node_info("Server", server_num)
      |> Debug.node_starting()

    receive do
      {:BIND, servers, databaseP} ->
        config
        |> State.initialise(server_num, servers, databaseP)
        |> Timer.restart_election_timer()
        |> Server.next()
    end

    # receive
  end

  # start

  # _________________________________________________________ next()
  def next(server) do
    # invokes functions in AppendEntries, Vote, ServerLib etc
    server =
      receive do
        {:APPEND_ENTRIES_REQUEST, body} ->
        server
          |> AppendEntries.handle_request(body)

        {:APPEND_ENTRIES_REPLY, term, success, index, sender} ->
          server
          |> AppendEntries.handle_reply(sender, term, success, index)

        {:APPEND_ENTRIES_TIMEOUT, %{term: term, followerP: sender}} ->
          server
          |> Debug.received(":APPEND_ENTRIES_TIMEOUT, #{inspect(sender)}")
          |> AppendEntries.handle_timeout(term, sender)

        {:VOTE_REQUEST, term, sender, lastLogIndex, lastLogTerm} ->
          server
          |> Debug.received(":VOTE_REQUEST, #{term}, #{inspect(sender)}, #{lastLogIndex}, #{lastLogTerm}")
          |> Vote.handle_request(term, sender, lastLogIndex, lastLogTerm)

        {:VOTE_REPLY, term, sender, vote} ->
          server
          |> Debug.received(":VOTE_REPLY #{term} #{inspect(sender)} #{inspect(vote)}")
          |> Vote.handle_reply(term, sender, vote)

        {:ELECTION_TIMEOUT, %{term: term, election: election} = body} ->
          server
          |> Debug.received(":ELECTION TIMEOUT #{inspect(body)}")
          |> Vote.election_timeout(term, election)

        {:CLIENT_REQUEST, body} ->
          server
          |> ClientRequest.handle_request(body)

        { :DB_REPLY, db_result } ->
          server
          |> Debug.received(":DB_REPLY #{inspect(db_result)}")
          |> ClientRequest.send_reply(server.last_applied, db_result)

        {:LEADER_CRASH} ->
          unless server.role == :LEADER do
            server
          else
            crash_delay = server.config.crash_leaders_duration
            Debug.info(server, "I have CRASHED for #{crash_delay}ms!")
            :timer.sleep(crash_delay)
            Debug.info(server, "I am back ONLINE!")
          end

        {:SERVER_CRASH, duration} ->
          Debug.info(server, "I have CRASHED for #{duration}ms!")
          :timer.sleep(duration)
          Debug.info(server, "I am back ONLINE!")

        {:SHOW_LOG, from} ->
          from = if from == 0 do
            Log.last_index(server) - 2
          else
            from
          end
          log = Enum.map(Log.get_entries(server, max(from - 3, 1)..min(from + 3, Log.last_index(server))),
          fn {_, e} ->
            e.request.cid
          end)
          server
          |> Debug.message("showlog", "#{server.server_num}@#{from} #{inspect(log)}")

        unexpected ->
          Helper.node_halt("***** Server: unexpected message #{inspect(unexpected)}")
      end

    server |> Server.next()
  end

  # next
end

# Server
