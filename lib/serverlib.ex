
# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2

defmodule ServerLib do

# Library of functions called by other server-side modules

# Stepdown from LEADER if our term is behind
def stepdown_if_behind(server, term) do
  if term > server.curr_term do
    server |> stepdown(term)
  else
    server
  end
end

# Stepdown from LEADER
def stepdown(server, term) do
  server
  |> State.curr_term(term)
  |> State.role(:FOLLOWER)
  |> State.voted_for(nil)
  |> Timer.restart_election_timer()
end

# Send empty AppendEntries request to each server every 'delay' ms
def send_heartbeat(server, delay \\ 5) do
  Enum.each(server.servers -- [server.selfP],
  fn s ->
    AppendEntries.sendAppendEntries(server, s)
  end)
  Process.send_after(self(), { :APPEND_ENTRIES_TIMEOUT, %{term: server.curr_term, followerP: server.selfP} }, delay)
  server
  |> Timer.cancel_append_entries_timer(server.selfP)
end

end # ServerLib
