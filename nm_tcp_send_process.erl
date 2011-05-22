-module(nm_tcp_send_process).
-export([tcp_send_process_loop/1]).
-include("nm_message_types.hrl").


tcp_send_process_loop(Socket) ->
    Timeout = 180 * 1000,
    receive
	detach_resp->
	    io:format("Server: Detached ~n", []),
	    Reply = nm_messages:detach_resp(),
	    io:format("Server replying = ~p~n",[Reply]),
	    gen_tcp:send(Socket, Reply);

	{attach_resp, Username, Password}->
	    io:format("Server: Client attached with name ~p and  password ~p ~n", [Username, Password]),
	    Reply = nm_messages:attach_resp(),
	    io:format("Server: sends ~p~n",[Reply]),
	    gen_tcp:send(Socket, Reply);

	{setup_resp, Username, PeerUsername}->
	    io:format("Server: Client ~p successfully connects to client ~p ~n", [Username, PeerUsername]),
	    Reply = nm_messages:setup_resp(),
	    io:format("Server: sends ~p~n",[Reply]),
	    gen_tcp:send(Socket, Reply);

	{attach_rej,ErrorReason} ->
	    Reply = nm_messages:attach_rej(ErrorReason),
	    io:format("Server replying = ~p~n",[Reply]),
	    gen_tcp:send(Socket, Reply);

	{setup_rej,ErrorReason} ->
	    Reply = nm_messages:setup_rej(ErrorReason),
	    io:format("Server replying = ~p~n",[Reply]),
	    gen_tcp:send(Socket, Reply);

	link_lock_req ->
	    Reply = nm_messages:link_lock_req(),
	    io:format("Server initiating = ~p~n",[Reply]),
	    gen_tcp:send(Socket, Reply);

	release_resp ->
	    Reply = nm_messages:release_resp(),
	    io:format("Server: sends ~p~n",[Reply]),
	    gen_tcp:send(Socket, Reply);

	{release_rej, ErrorReason} ->
	    Reply = nm_messages:release_rej(ErrorReason),
	    io:format("Server replying = ~p~n",[Reply]),
	    gen_tcp:send(Socket, Reply);

	{link_start_ind, Ref}->
	    io:format("Server: Start link with ref ~p ~n", [Ref]),
	    Reply = nm_messages:link_start_ind(Ref),
	    io:format("Server: sends ~p~n",[Reply]),
	    gen_tcp:send(Socket, Reply);

	link_stop_ind->
	    io:format("Server: Stop link ~n"),
	    Reply = nm_messages:link_stop_ind(),
	    io:format("Server: sends ~p~n",[Reply]),
	    gen_tcp:send(Socket, Reply);

	{punch_start_ind,ToIP, ToPort}->
	    io:format("Server: Punch_start_ind  to IP ~p, to Port ~p~n", [ToIP,ToPort]),
	    Reply = nm_messages:punch_start_ind(ToIP, ToPort),
	    io:format("Server: sends ~p~n",[Reply]),
	    gen_tcp:send(Socket, Reply);

	punch_stop_ind->
	    io:format("Server: Punch_stop_ind ~n", []),
	    Reply = nm_messages:punch_stop_ind(),
	    io:format("Server: sends ~p~n",[Reply]),
	    gen_tcp:send(Socket, Reply)

    after
	Timeout ->
	    Reply = nm_messages:keep_alive_ind(),
	    io:format("Server: sends ~p ~n",[Reply]),
	    gen_tcp:send(Socket, Reply)
    end,
    tcp_send_process_loop(Socket).
