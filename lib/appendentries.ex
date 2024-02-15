
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
        server = if term > server.curr_term do
          # Accept that a newer leader exists
          ServerLib.stepdown(server, term)
          |> State.leaderP(leaderId)
        else
          server
        end
        # Send a reply telling a server they are behind
        if term < server.curr_term do
          send q, { :APPEND_ENTRIES_REPLY, server.curr_term, false}
        end
        server = if term == server.curr_term do
          server
          |> State.leaderP(leaderId)
        else
          server
        end
        # Log does not contain the previous entry
        # server = if Log.last_index(server) < prevLogIndex do
        #   send q, { :APPEND_ENTRIES_REPLY, server.curr_term, false }
        #   server
        # else
        #   # Conflicting entries
        #   server = unless Log.entry_at(server, prevLogIndex) == prevLogTerm do
        #     send q, { :APPEND_ENTRIES_REPLY, server.curr_term, false }
        #     server |> Log.delete_entries_from(prevLogIndex)
        #   else
        #     server
        #   end
        #   server
        # end
        # Append new entries

        # if leaderCommit > server.commit_index do
        #   server
        #   |> State.commit_index(min(leaderCommit, Log.last_index(server)))
        # end

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

  def reply(server, term, msg) do
    server
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

end # AppendEntries
