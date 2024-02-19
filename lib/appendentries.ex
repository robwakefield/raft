
# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2

defmodule AppendEntries do

  # Handle an AppendEntries Request
  def handle_request(server, body) do
    case body do
      %{
        term: term,
        leaderId: leaderId,
        prevLogIndex: prevLogIndex,
        prevLogTerm: prevLogTerm,
        entries: entries,
        leaderCommit: leaderCommit,
        sender: q
      } ->

        server
        |> debug_filter_heartbeat(entries, body, q)
        |> ServerLib.stepdown_if_behind(term)
        |> notify_term_is_behind(term, q)
        |> send_reply(term, prevLogIndex, prevLogTerm, entries, leaderId, leaderCommit, q)
        |> reset_timers(q)

      unexpected ->
        Helper.node_halt("***** Server: unexpected message #{inspect(unexpected)}")

    end
  end

  def handle_reply(server, q, term, success, index) do
    server = server |> ServerLib.stepdown_if_behind(term)

    if server.role == :LEADER and term == server.curr_term do
      server = if success do
        # Increase next index for q
        server = if index >= Map.get(server.next_index, q) do
          server
          |> State.next_index(q, index + 1)
          |> State.match_index(q, index)
          |> Debug.message("arep", ":APPEND_ENTRIES_REPLY, term:#{inspect(term)} #{inspect(success)} #{inspect(index)}")
        else
          server
          |> Debug.message("hb", "HEARTBEAT REPLY from #{inspect(q)}")
        end

        # Count in how many logs the entry is replicated
        count = Enum.reduce(server.match_index, 0,
        fn {_pid, match_index}, count ->
          if match_index > server.last_applied do count + 1 else count end
        end)

        # Commit the log to DB if it is replicated in a majority of logs
        if count >= server.majority do
          newly_applied = server.last_applied + 1
          Debug.assert(server, newly_applied <= Log.last_index(server),
            "last_applied is greater than size of log!")
          req = Log.request_at(server, newly_applied)
          send server.databaseP, { :DB_REQUEST, req }
          server
          |> State.commit_index(newly_applied)
          |> State.last_applied(newly_applied)
          |> State.applied(newly_applied,
            %{cmd: req.cmd, cid: req.cid, clientP: req.clientP})
        else
          server
        end
      else
        # Append RPC failed, decrement next_index and try again
        server
        |> Debug.message("arep", ":APPEND_ENTRIES_REPLY, term:#{inspect(term)} #{inspect(success)} #{inspect(index)}")
        |> State.next_index(q, max(1, Map.get(server.next_index, q) - 1))
      end
      # If q has more logs to receive, send them
      server = if Map.get(server.next_index, q) <= Log.last_index(server) do
        server |> sendAppendEntries(q)
      else
        server
      end
      server
    else
      server
    end
  end

  def handle_timeout(server, term, q) do
    unless term < server.curr_term do
      if server.role == :CANDIDATE do
        server |> Vote.send_request(q)
      else
        if server.role == :LEADER and q == server.selfP do
          # Sendout heartbeat
          # TODO: check if this should use send_heartbeat() function instead
          server |> ServerLib.send_heartbeat()
        else # :FOLLOWER
          server
        end
      end
    else
      server
    end
  end

  # Send an AppendEntries request to q
  def sendAppendEntries(server, q) do
    lastLogIndex = get_lastLogIndex(server, q)

    server = server
    |> Timer.restart_append_entries_timer(q)
    |> State.next_index(q, lastLogIndex)

    # TODO: DEBUG currently sending all of log
    send q, {:APPEND_ENTRIES_REQUEST, %{
      term: server.curr_term,
      leaderId: server.leaderP,
      #prevLogIndex: lastLogIndex - 1,
      #prevLogTerm: Log.term_at(server, lastLogIndex - 1),
      #entries: Log.get_entries(server, lastLogIndex..Log.last_index(server)),

      prevLogIndex: 0,
      prevLogTerm: Log.term_at(server, 0),
      entries: Log.get_entries(server, 1..server.commit_index),
      leaderCommit: server.commit_index,
      sender: server.selfP
    }}

    server
  end

  # Print correct debug message to filter out heartbeats
  defp debug_filter_heartbeat(server, entries, body, q) do
    unless entries == [] do
      server |> Debug.message("areq", ":APPEND_ENTRIES_REQUEST, #{inspect(body)}")
    else
      server |> Debug.message("hb", ":HEARTBEAT from #{inspect(q)}")
    end
  end

  # Perform action based on an incorrect term
  defp notify_term_is_behind(server, term, q) do
    if term < server.curr_term do
        send q, { :APPEND_ENTRIES_REPLY, server.curr_term, false, 0, server.selfP} # 0?
        server
    else
        server
    end
  end

  # If term is correct, reply to an AppendEntries request
  defp send_reply(server, term, prevLogIndex, prevLogTerm, entries, leaderId, leaderCommit, q) do
    if term == server.curr_term do
      # Send a reply with the highest index in our log
      index = 0
      # true if our log matches the leaders
      success = prevLogIndex == 0 or
        (prevLogIndex <= Log.last_index(server) and
          Log.term_at(server, prevLogIndex) == prevLogTerm)

      {server, index} = if success do
        # Update our log and possibly store to DB
        storeEntries(server, prevLogIndex, entries, leaderCommit)
      else
        {server, index}
      end

      send q, {:APPEND_ENTRIES_REPLY, server.curr_term, success, index, server.selfP}

      server
      |> State.leaderP(leaderId)
    else
      server
    end
  end

  # Restart RPC and election timers as we have heard from the leader/server
  defp reset_timers(server, q) do
    if q == server.leaderP or server.leaderP == nil do
      server
      |> State.leaderP(q)
      |> Timer.restart_election_timer()
    else
      server
    end
    |> Timer.restart_append_entries_timer(q)
  end

  # Get the index of the last log for server, ignoring nils
  defp get_lastLogIndex(server, q) do
    if is_nil(Map.get(server.next_index, q)) do
      Log.last_index(server)
    else
      max(Map.get(server.next_index, q), Log.last_index(server))
    end
  end

  # Update our log and DB based on information from an AppendEntries request
  defp storeEntries(server, prevLogIndex, entries, c) do
    index = prevLogIndex

    # Repair and append our log to match the log from the request
    # Return the index of the last correct log we now have
    {server, _index} = Enum.reduce(entries, {server, index},
    fn {_, e}, {server, index} ->
      Debug.assert(server, server != nil, "(storeEntries) server is nil")
      index = index + 1
      if index > Log.last_index(server) or Log.term_at(server, index) != e.term do
        server = server
          |> Log.new(Log.get_entries(server, 1..(index-1)))
          |> Log.append_entry(e)
        {server, index}
      else
        {server, index}
      end
    end)

    # TODO: setting the log to be the same as leader for debugging
    server = Log.new(server)
    server = Enum.reduce(entries, server,
    fn {_, e}, server ->
      Log.append_entry(server, e)
    end)
    index = Log.last_index(server)
    # END OF DEBUGGING CHANGES

    # Update commit index that we can safely commit to DB
    server = server
    |> State.commit_index(min(c, index))

    # Store the committed entries to the db
    server = if server.last_applied < server.commit_index do
      Enum.reduce(
        Log.get_entries(server, (server.last_applied + 1)..server.commit_index),
        server,
      fn {_, entry}, server ->
        req = entry.request
        send server.databaseP, { :DB_REQUEST, req }
        server
        |> State.last_applied(server.last_applied + 1)
        |> State.applied(server.last_applied + 1,
          %{cmd: req.cmd, cid: req.cid, clientP: req.clientP})
      end)
    else
      server
    end

    {server, index}
  end

end # AppendEntries
