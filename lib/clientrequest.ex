
# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2

defmodule ClientRequest do

def handle_request(server, req) do
  unless server.role == :LEADER do
    server |> forward(req)
  else
    case req do
      %{cmd: _, clientP: _, cid: _} ->
        if Log.last_index(server) != 0 and Log.request_at(server, Log.last_index(server)) == req do
          server
        else
          server = server
          |> Log.append_request(server.curr_term, req)

          server = server |> State.commit_index(Log.last_index(server))

          Enum.reduce(server.servers -- [server.selfP], server,
          fn q, server ->
            server |> AppendEntries.sendAppendEntries(q)
          end)
        end

      unexpected ->
        Helper.node_halt("***** Server: unexpected message #{inspect(unexpected)}")
    end
  end
end

# Forward the client request to the leader
def forward(server, req) do
  dest = unless server.leaderP == nil do server.leaderP else self() end
  send dest, { :CLIENT_REQUEST, req }
  if dest == self() do
    server
  else
    server |> Debug.message("client", "Forwarding to leader(#{inspect(dest)}) #{inspect(req)}")
  end
end

def reply(server, index, response) do
  req =  Map.get(server.applied, index)
  send req.clientP, { :CLIENT_REPLY, %{cid: req.cid, reply: response, leaderP: server.selfP} }
  server
end

end # ClientRequest
