
# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2

defmodule AppendEntries do

  def request(server, body) do
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
        server = unless entries == [] do
          server |> Debug.message("areq", ":APPEND_ENTRIES_REQUEST, #{inspect(body)}")
        else
          server |> Debug.message("hb", ":HEARTBEAT from #{inspect(q)}")
        end


        # Accept that a newer leader exists and we are behind
        server = if term > server.curr_term do
          ServerLib.stepdown(server, term)
          |> State.leaderP(leaderId)
        else
          server
        end

        server = if term < server.curr_term do # Send a reply telling a server they are behind
          send q, { :APPEND_ENTRIES_REPLY, server.curr_term, false, 0, server.selfP} # 0?
          server
        else
          index = 0
          success = prevLogIndex == 0 or
            (prevLogIndex <= Log.last_index(server) and
              Log.term_at(server, prevLogIndex) == prevLogTerm)

          {server, index} = if success do
            storeEntries(server, prevLogIndex, entries, leaderCommit)
          else
            {server, index}
          end

          send q, {:APPEND_ENTRIES_REPLY, server.curr_term, success, index, server.selfP}

          server
          |> State.leaderP(leaderId)
        end

        # Restart RPC and election timers as we have heard from the leader/server
        if q == server.leaderP and server.leaderP != nil do
          server
          |> Timer.restart_election_timer()
        else
          server
        end
        |> Timer.restart_append_entries_timer(q)

      unexpected ->
        Helper.node_halt("***** Server: unexpected message #{inspect(unexpected)}")

    end
  end

  def reply(server, q, term, success, index) do
    if term > server.curr_term do
      server |> ServerLib.stepdown(term)
    else
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
          count = Enum.reduce(server.match_index, 0,
          fn {_pid, match_index}, count ->
            if match_index > server.last_applied do count + 1 else count end
          end)
          if count >= server.majority do
            req = Log.request_at(server, server.last_applied + 1)
            send server.databaseP, { :DB_REQUEST, req }
            server
            |> State.commit_index(server.last_applied + 1)
            |> State.last_applied(server.last_applied + 1)
            |> Map.put(:applied, Map.put(server.applied, server.last_applied + 1,
              %{cmd: req.cmd, cid: req.cid, clientP: req.clientP}))
          else
            server
          end
        else
          # Append RPC failed, decrement next_index and try again
          server
          |> Debug.message("arep", ":APPEND_ENTRIES_REPLY, term:#{inspect(term)} #{inspect(success)} #{inspect(index)}")
          |> State.next_index(q, max(1, Map.get(server.next_index, q) - 1))
        end
        server = if Map.get(server.next_index, q) <= Log.last_index(server) do
          sendAppendEntries(server, q)
        else
          server
        end
        server
      else
        server
      end
    end
  end

  def timeout(server, _term, q) do
    if server.role == :CANDIDATE do
      server |> Vote.send_request(q)
    else
      if server.role == :LEADER do
        server |> ServerLib.send_heartbeat()
      else # :FOLLOWER
        server
      end
    end
  end

def sendAppendEntries(server, q) do
  # TODO: refactor this
  lastLogIndex =
    if is_nil(Map.get(server.next_index, q)) do
      Log.last_index(server)
    else
      max(Map.get(server.next_index, q), Log.last_index(server))
    end

  Debug.assert(server, lastLogIndex != nil, "(sendAppendEntries) lastLogIndex is nil")

  server = server
  |> Timer.restart_append_entries_timer(q)
  |> State.next_index(q, lastLogIndex)

  send q, {:APPEND_ENTRIES_REQUEST, %{
    term: server.curr_term,
    leaderId: server.leaderP,
    prevLogIndex: lastLogIndex - 1,
    prevLogTerm: Log.term_at(server, lastLogIndex - 1),
    entries: Log.get_entries(server, lastLogIndex..Log.last_index(server)),
    leaderCommit: server.commit_index,
    sender: server.selfP
  }}

  server
end

defp storeEntries(server, prevLogIndex, entries, c) do
  index = prevLogIndex
  {server, index} = Enum.reduce(entries, {server, index},
  fn {_, e}, {server, index} ->
    Debug.assert(server, server != nil, "(storeEntries) server is nil")
    index = index + 1
    if index > Log.last_index(server) or Log.term_at(server, index) != e.term do
      server = server
        #|> Log.new(Log.get_entries(server, [1..index-1]))
        #TODO: change this to allow for deleting invalid entries
        |> Log.append_entry(e)
      {server, index}
    else
      {server, index}
    end
  end)

  server = server
  |> State.commit_index(min(c, index))

  # Store the committed entries to the db
  server = if server.last_applied < server.commit_index do
    Enum.reduce(Log.get_entries(server, (server.last_applied + 1)..server.commit_index), server,
    fn {_, entry}, server ->
      req = entry.request
      send server.databaseP, { :DB_REQUEST, req }
      server
      |> State.last_applied(server.last_applied + 1)
      |> Map.put(:applied, Map.put(server.applied, server.last_applied + 1,
        %{cmd: req.cmd, cid: req.cid, clientP: req.clientP}))
    end)
  else
    server
  end

  {server, index}
end

end # AppendEntries
