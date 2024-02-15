
# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2

defmodule ClientRequest do

def handle_request(server, req) do
  unless server.role == :LEADER do
    server |> forward(req)
  else
    case req do
      %{cmd: cmd, clientP: clientP, cid: cid} ->
        server

      unexpected ->
        Helper.node_halt("***** Server: unexpected message #{inspect(unexpected)}")
    end
    server
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

end # ClientRequest
