-module(networkmanager).
-export([start/0, start_server/1, start_server/2, start_clients/9, client_start/0, peer_client_start/0, rclient_start/0, rpeer_client_start/0, client_send_attach_req/3, client_send_detach_req/1,client_receive_process/6,peer_client_receive_process_loop/8, openports/1]).
-include("nm_message_types.hrl").

%%% Local installation of the server on localhost:
%%% networkmanager:start_server(1440,1441).
%%% networkmanager:client_start().
%%% networkmanager:peer_client_start().
%%% networkmanager:client_receive_process(<<"miller">>, <<"123">>,3456, "localhost", 1440, 1441).
%%% networkmanager:peer_client_receive_process_loop(<<"mayer">>, <<"234">>, <<"miller">>, <<"123">>, 3457, "localhost", 1440, 1441).

%%% Remote installation on a server in the internet: 
%%% networkmanager:rclient_start().
%%% networkmanager:rpeer_client_start().
%%% networkmanager:start_client(<<"Username">>, <<"Password">>, 2345, <<"PeerUsername">>, <<"PeerUserPassword">>, 2346, "localhost", 1440, 1441).

%%% networkmanager:client_receive_process(<<"miller">>, <<"123">>,3456, {178,77,97,125}, 1440 ,1441).
%%% networkmanager:peer_client_receive_process_loop(<<"mayer">>, <<"234">>, <<"miller">>, <<"123">>, 3457, {178,77,97,125}, 1440, 1441).

start() ->
    start_server(1440, 1441).

start_server([ServerUDPPortAtom, ServerTCPPortAtom]) ->
    start_server(list_to_integer(atom_to_list(ServerUDPPortAtom)), list_to_integer(atom_to_list(ServerTCPPortAtom))).


start_server(ServerUDPPort, ServerTCPPort) ->
    spawn_link(fun() -> nm_udp_connector:init(ServerUDPPort) end),
    io:format("Server:  Listening on UDP Port: ~p, TCP Port: ~p ~n",[ServerUDPPort, ServerTCPPort]),
    nm_user_store:init(),
    {ok,Listen} = gen_tcp:listen(ServerTCPPort, [binary, {packet,4}, {reuseaddr,true},{active,once}, {keepalive,true}]),
    parallel_connect(Listen).

parallel_connect(Listen) ->
    {ok, Socket} = gen_tcp:accept(Listen),
    ServerReceiveProcessPid = spawn(fun() -> nm_tcp_connection:server_receive_process_loop(Socket) end),    
    gen_tcp:controlling_process(Socket, ServerReceiveProcessPid),
    parallel_connect(Listen).


start_clients(Username, Password, Port, PeerUsername, PeerUserPassword,PeerPort, ServerIPAddress, ServerUDPPort, ServerTCPPort) ->
    spawn(fun()-> client_receive_process(Username, Password,Port, ServerIPAddress, ServerUDPPort, ServerTCPPort)end),
    spawn(fun()-> peer_client_receive_process_loop(PeerUsername, PeerUserPassword, Username, Password, PeerPort, ServerIPAddress, ServerUDPPort, ServerTCPPort)end).


client_start()->
    client_receive_process(<<"miller">>, <<"123">>,3456, "localhost", 1440,1441).

peer_client_start() ->
    peer_client_receive_process_loop(<<"mayer">>, <<"234">>, <<"miller">>, <<"123">>, 3455, "localhost", 1440, 1441).

rclient_start()->
    client_receive_process(<<"miller">>, <<"123">>,3456, {178,77,97,125}, 1440,1441).

rpeer_client_start() ->
    peer_client_receive_process_loop(<<"mayer">>, <<"234">>, <<"miller">>, <<"123">>, 3455, {178,77,97,125}, 1440, 1441).


client_receive_process(Username, Password, ClientUDPPort, ServerIPAddress, ServerUDPPort, ServerTCPPort)->
    {ok, Socket} = 
	gen_tcp:connect(ServerIPAddress, ServerTCPPort, [binary, {packet, 4}, {active,false}]),
    client_attach_process_loop(Socket, ClientUDPPort, ServerUDPPort, 0, Username, Password).


client_attach_process_loop(Socket, ClientUDPPort, ServerUDPPort, Count, Username, Password) ->
    client_send_attach_req(Socket, Username, Password),
    case gen_tcp:recv(Socket,0) of
	{ok, Bin} ->
	    io:format("Client:  received binary = ~p~n",[Bin]),
	    case Bin of 
		<<?ATTACH_RESP:16>> ->
		    client_wait_link_started_loop(Socket,ClientUDPPort, ServerUDPPort);

		<<?KEEP_ALIVE_IND:16>> ->
			io:format("Client (TCP): Keep alive received ~n"),
			client_attach_process_loop(Socket, ClientUDPPort, ServerUDPPort, Count, Username, Password);

		InvalidMessage ->
		    io:format("Client: Invalid message received ~p~n", [InvalidMessage]),
		    client_attach_process_loop(Socket, ClientUDPPort, ServerUDPPort, Count, Username, Password)
	    end,
	    client_attach_process_loop(Socket, ClientUDPPort, ServerUDPPort, Count, Username, Password);
	{error, closed} ->
	    io:format("Client: Connection closed by server!!!!~n")
    end.

client_wait_link_started_loop(Socket, ClientUDPPort, ServerUDPPort)->
    case gen_tcp:recv(Socket,0) of
	{ok, Bin} ->
	    io:format("Client:  received binary = ~p~n",[Bin]),
	    case Bin of 
		<<?LINK_START_IND:16, BinRef:33/binary>> ->
		    {ok,{Peername,_port}}  = inet:peername(Socket),
		    io:format("Peername ~p ~n", [Peername]),
		    io:format("BinRef ~p ~n", [BinRef]),
		    UDPAddress = Peername,

		    {A1,A2,A3} = now(),
		    random:seed(A1, A2, A3),
		    %% generate random Client ports to make sure:
		    %% - different on this applications can use different ports
		    %% generate more than one port, since any choosen port may already be allocated by another PC behind the same firewall and 
  		    %% thus cause trouble as translating this port.

 	  	    PortSocketList = openports([(1024+random:uniform(4096)),(1024+random:uniform(4096)),(1024+random:uniform(4096)),(1024+random:uniform(4096)),(1024+random:uniform(4096))]),

                    %% ClientUDPPort0 =ClientUDPPort+0,
                    %% ClientUDPPort1 =ClientUDPPort+1,
                    %% ClientUDPPort2 =ClientUDPPort+2,
                    %% ClientUDPPort3 =ClientUDPPort+3,
                    %% ClientUDPPort4 =ClientUDPPort+4,
                    ClientUDPPort5 =ClientUDPPort+5,
		    %% io:format("ClientUDPPort0: ~p ~n", [ClientUDPPort0]),
                    %% {ok,UDPSocket0} = gen_udp:open(ClientUDPPort0,[binary]),
		    %% udp_port_info_ind_msg(UDPSocket0, ClientUDPPort0, {0,0,0,0}, ServerUDPPort, BinRef),
		    %% udp_port_info_ind_msg(UDPSocket0, ClientUDPPort0, UDPAddress, ServerUDPPort, BinRef),
		    %% io:format("ClientUDPPort1: ~p ~n", [ClientUDPPort1]),
                    %% {ok,UDPSocket1} = gen_udp:open(ClientUDPPort1,[binary]),
		    %% udp_port_info_ind_msg(UDPSocket1, ClientUDPPort1, {0,0,0,0}, ServerUDPPort, BinRef),
		    %% udp_port_info_ind_msg(UDPSocket1, ClientUDPPort1, UDPAddress, ServerUDPPort, BinRef),
		    %% io:format("ClientUDPPort2: ~p ~n", [ClientUDPPort2]),
                    %% {ok,UDPSocket2} = gen_udp:open(ClientUDPPort2,[binary]),
		    %% udp_port_info_ind_msg(UDPSocket2, ClientUDPPort2, {0,0,0,0}, ServerUDPPort, BinRef),
		    %% udp_port_info_ind_msg(UDPSocket2, ClientUDPPort2, UDPAddress, ServerUDPPort, BinRef),
		    %% io:format("ClientUDPPort3: ~p ~n", [ClientUDPPort3]),
                    %% {ok,UDPSocket3} = gen_udp:open(ClientUDPPort3,[binary]),
		    %% udp_port_info_ind_msg(UDPSocket3, ClientUDPPort3, {0,0,0,0}, ServerUDPPort, BinRef),
		    %% udp_port_info_ind_msg(UDPSocket3, ClientUDPPort3, UDPAddress, ServerUDPPort, BinRef),
		    %% io:format("ClientUDPPort4: ~p ~n", [ClientUDPPort4]),
                    %% {ok,UDPSocket4} = gen_udp:open(ClientUDPPort4,[binary]),
		    %% udp_port_info_ind_msg(UDPSocket4, ClientUDPPort4, {0,0,0,0}, ServerUDPPort, BinRef),
		    %% udp_port_info_ind_msg(UDPSocket4, ClientUDPPort4, UDPAddress, ServerUDPPort, BinRef),
		    %% io:format("ClientUDPPort5: ~p ~n", [ClientUDPPort5]),
                    {ok,UDPSocket5} = gen_udp:open(ClientUDPPort5,[binary]),
		    %% udp_port_info_ind_msg(UDPSocket5, ClientUDPPort5, {0,0,0,0}, ServerUDPPort, BinRef),
		    udp_port_info_ind_msg(UDPSocket5, ClientUDPPort5, UDPAddress, ServerUDPPort, BinRef),


		    client_link_started_loop(Socket,UDPSocket5, ClientUDPPort5, UDPAddress, ServerUDPPort, BinRef);

		<<?KEEP_ALIVE_IND:16>> ->
			io:format("Client (TCP): Keep alive received ~n"),
			client_wait_link_started_loop(Socket, ClientUDPPort, ServerUDPPort);

		InvalidMessage ->
		    io:format("Client: Invalid message received ~p~n", [InvalidMessage]),
			client_wait_link_started_loop(Socket, ClientUDPPort, ServerUDPPort)
	    end,
	    client_wait_link_started_loop(Socket, ClientUDPPort, ServerUDPPort);
	{error, closed} ->
	    io:format("Client: Connection closed by server!!!!~n")
    end.

client_link_started_loop(Socket,UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef)->
    Timeout = 10 * 1000,
    inet:setopts(Socket, [{active,once}]),
    inet:setopts(UDPSocket, [{active,once}]),
    receive
	{tcp, Socket, Bin} ->
	    io:format("Client:  received binary = ~p~n",[Bin]),
	    case Bin of
		<<?LINK_STOP_IND:16>> ->
		    gen_udp:close(UDPSocket),
		    client_wait_link_started_loop(Socket, ClientUDPPort, ServerUDPPort);

		<<?PUNCH_START_IND:16, IP1:16, IP2:16, IP3:16, IP4:16, ToPort:16>> ->
		    ToIP={IP1,IP2,IP3,IP4},
		    %%client_send_peer2peer_msg(UDPSocket, ClientUDPPort, BinRef, ToIP, ToPort),
                    client_send_peer2peer_msg_salve(2, 2,UDPSocket, ClientUDPPort, BinRef, ToIP, ToPort),
		    client_link_started_loop(Socket,UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef);
		
		<<?KEEP_ALIVE_IND:16>> ->
			io:format("Client (TCP): Keep alive received ~n"),
			client_link_started_loop(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef);

		InvalidMessage ->
		    io:format("Client: Invalid message received ~p~n", [InvalidMessage]),		    
		    client_link_started_loop(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef)
	    end;
	{udp, UDPSocket, FromIP, FromPort, Bin} ->
	    io:format("Client: received binary = ~p~n",[Bin]),
	    case Bin of
		<<?UDP_PEER2PEER_IND:16, ReceivedBinRef:33/binary, PeerClientUDPPort:16>> ->
		    io:format("Client (UDP): Received udp_peer2peer_ind Port info: PeerClientUDPPort ~p, FromIP ~p, FromPort ~p, ~n BinRef: ~p ~n", [PeerClientUDPPort, FromIP, FromPort,ReceivedBinRef]),
		    client_send_peer2peer_pushback_msg (UDPSocket, ClientUDPPort, BinRef, FromIP,FromPort), 
		    client_link_started_loop(Socket,UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef);

		<<?UDP_PEER2PEER_PUSHBACK_IND:16, ReceivedBinRef:33/binary, PeerClientUDPPort:16>> ->
		    io:format("Client (UDP) : Received udp_peer2peer_punchback_ind Port info: PeerClientUDPPort ~p, FromIP ~p, FromPort ~p, ~n BinRef: ~p ~n", [PeerClientUDPPort, FromIP, FromPort,ReceivedBinRef]),
    		    client_send_peer2peer_pushback_msg (UDPSocket, ClientUDPPort, BinRef, FromIP,FromPort),
		    client_link_locked(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef, FromIP, FromPort);

		InvalidMessage ->
		    io:format("Client (UDP): Invalid message received ~p~n", [InvalidMessage]),		    
		    client_link_started_loop(Socket,UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef)
	    end
    after
	Timeout ->
	    io:format("Client: udp_port_info_ind_msg BinRef: ~p ~n", [BinRef]),
	    udp_port_info_ind_msg(UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef)
    end,
    client_link_started_loop(Socket,UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef).

client_link_locked(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef, FromIP, FromPort)->
    Timeout = 10 * 1000,
    inet:setopts(Socket, [{active,once}]),
    inet:setopts(UDPSocket, [{active,once}]),
    receive
	{tcp, Socket, Bin} ->
	    io:format("Client:  received binary = ~p~n",[Bin]),
	    case Bin of
		<<?LINK_STOP_IND:16>> ->
		    gen_udp:close(UDPSocket),
		    client_wait_link_started_loop(Socket, ClientUDPPort, ServerUDPPort);
		
		<<?KEEP_ALIVE_IND:16>> ->
			io:format("Client (TCP): Keep alive received ~n"),
			client_link_locked(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef, FromIP, FromPort);
		
		InvalidMessage ->
		    io:format("Client: Invalid message received ~p~n", [InvalidMessage]),		    
		    client_link_locked(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef, FromIP, FromPort)
	    end;
	{udp, UDPSocket, FromIP, FromPort, Bin} ->
	    io:format("Client: received binary = ~p~n",[Bin]),
	    case Bin of
		<<?UDP_PEER2PEER_PUSHBACK_IND:16, ReceivedBinRef:33/binary, PeerClientUDPPort:16>> ->
		    io:format("Client (UDP) : Received udp_peer2peer_punchback_ind Port info: PeerClientUDPPort ~p, FromIP ~p, FromPort ~p, ~n BinRef: ~p ~n", [PeerClientUDPPort, FromIP, FromPort,ReceivedBinRef]),
		    client_link_locked(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef, FromIP, FromPort);

		InvalidMessage ->
		    io:format("Client (UDP): Invalid message received ~p~n", [InvalidMessage]),		    
		    client_link_locked(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef, FromIP, FromPort)
	    end
    after
	Timeout ->
	    client_send_peer2peer_pushback_msg (UDPSocket, ClientUDPPort, BinRef, FromIP,FromPort),
	    client_link_locked(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef, FromIP, FromPort)
    end,
    client_link_locked(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef, FromIP, FromPort).


peer_client_receive_process_loop(Username, Password, CalledUsername, CalledUserPassword, ClientUDPPort, ServerIPAddress, ServerUDPPort, ServerTCPPort) ->
    {ok, Socket} = 
	gen_tcp:connect(ServerIPAddress, ServerTCPPort, [binary, {packet, 4}, {active,false}]), 
    peer_client_attach_process_loop(Socket, ClientUDPPort, ServerUDPPort, 0, Username, Password, CalledUsername, CalledUserPassword).

peer_client_attach_process_loop(Socket, ClientUDPPort, ServerUDPPort, Count, Username, Password, CalledUsername, CalledUserPassword) ->
    client_send_attach_req(Socket, Username, Password),
    case gen_tcp:recv(Socket,0) of
	{ok, Bin} ->
	    io:format("Client: received binary = ~p~n",[Bin]),
	    case Bin of 
		<<?ATTACH_RESP:16>> ->
		    sleep(10),
		    client_send_setup_request(Socket, CalledUsername, CalledUserPassword),
		    peer_client_setup_process_loop(Socket, ClientUDPPort, ServerUDPPort, Count, Username, Password, CalledUsername, CalledUserPassword);

		<<?KEEP_ALIVE_IND:16>> ->
			io:format("Client (TCP): Keep alive received ~n"),
			peer_client_attach_process_loop(Socket, ClientUDPPort, ServerUDPPort, Count, Username, Password, CalledUsername, CalledUserPassword);

		InvalidMessage ->
		    io:format("Client: Invalid message received ~p~n", [InvalidMessage]),	
      			peer_client_attach_process_loop(Socket, ClientUDPPort, ServerUDPPort, Count, Username, Password, CalledUsername, CalledUserPassword)

	    end,
	    peer_client_attach_process_loop(Socket, ClientUDPPort, ServerUDPPort, Count, Username, Password, CalledUsername, CalledUserPassword);
	{error, closed} ->
	    io:format("Client: Connection closed by server!!!!~n")
    end.

peer_client_setup_process_loop(Socket, ClientUDPPort, ServerUDPPort, Count, Username, Password, CalledUsername, CalledUserPassword) ->
    case gen_tcp:recv(Socket,0) of
	{ok, Bin} ->
	    io:format("Client: received binary = ~p~n",[Bin]),
	    case Bin of 
		<<?SETUP_RESP:16>> ->
		    peer_client_wait_link_started_loop(Socket, ClientUDPPort, ServerUDPPort);
		
		<<?KEEP_ALIVE_IND:16>> ->
			io:format("Client (TCP): Keep alive received ~n"),
			peer_client_setup_process_loop(Socket, ClientUDPPort, ServerUDPPort, Count, Username, Password, CalledUsername, CalledUserPassword);

		InvalidMessage ->
		    io:format("Client: Invalid message received ~p~n", [InvalidMessage]),
			peer_client_setup_process_loop(Socket, ClientUDPPort, ServerUDPPort, Count, Username, Password, CalledUsername, CalledUserPassword)
	    end,
	    peer_client_setup_process_loop(Socket, ClientUDPPort, ServerUDPPort, Count, Username, Password, CalledUsername, CalledUserPassword);
	{error, closed} ->
	    io:format("Client: Connection closed by server!!!!~n")
    end.

peer_client_wait_link_started_loop(Socket, ClientUDPPort, ServerUDPPort)->
    case gen_tcp:recv(Socket,0) of
	{ok, Bin} ->
	    io:format("Client: received binary = ~p~n",[Bin]),
	    case Bin of 
		<<?LINK_START_IND:16, BinRef:33/binary>> ->
		    {ok,{Peername,_port}}  = inet:peername(Socket),
		    io:format("Peername ~p ~n", [Peername]),
		    io:format("BinRef ~p ~n", [BinRef]),
		    UDPAddress = Peername,
		    %%io:format("ClientUDPPort: ~p ~n", [ClientUDPPort]),
		    {ok,UDPSocket} = gen_udp:open(ClientUDPPort, [binary]),   
		    udp_port_info_ind_msg(UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef),
		    peer_client_link_started_loop(Socket,UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef);

		<<?KEEP_ALIVE_IND:16>> ->
			io:format("Client (TCP): Keep alive received ~n"),
			peer_client_wait_link_started_loop(Socket, ClientUDPPort, ServerUDPPort);

		InvalidMessage ->
		    io:format("Client: Invalid message received ~p~n", [InvalidMessage]),
			peer_client_wait_link_started_loop(Socket, ClientUDPPort, ServerUDPPort)	

	    end,
	    peer_client_wait_link_started_loop(Socket, ClientUDPPort, ServerUDPPort);
	{error, closed} ->
	    io:format("Client: Connection closed by server!!!!~n")
    end.

peer_client_link_started_loop(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef)->
    Timeout = 10 * 1000,
    inet:setopts(Socket, [{active,once}]),
    inet:setopts(UDPSocket, [{active,once}]),

    receive
	{tcp, Socket, Bin} ->
	    io:format("Client: received binary = ~p~n",[Bin]),
	    case Bin of
		<<?LINK_STOP_IND:16>> ->
		    gen_udp:close(UDPSocket),
		    peer_client_wait_link_started_loop(Socket, ClientUDPPort, ServerUDPPort);

		<<?PUNCH_START_IND:16, IP1:16, IP2:16, IP3:16, IP4:16, ToPort:16>> ->
		    ToIP={IP1,IP2,IP3,IP4},
		    %% client_send_peer2peer_msg(UDPSocket, ClientUDPPort, BinRef, ToIP, ToPort),
                    client_send_peer2peer_msg_salve(2, 2,UDPSocket, ClientUDPPort, BinRef, ToIP, ToPort),
		    peer_client_link_started_loop(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef);

		<<?KEEP_ALIVE_IND:16>> ->
			io:format("Client (TCP): Keep alive received ~n"),
			peer_client_link_started_loop(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef);

		InvalidMessage ->
		    io:format("Client: Invalid message received ~p~n", [InvalidMessage]),		    
		    peer_client_link_started_loop(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef)
	    end;
	{udp, UDPSocket, FromIP, FromPort, Bin}->
	    io:format("Client: received binary = ~p~n",[Bin]),
	    case Bin of
		<<?UDP_PEER2PEER_IND:16, ReceivedBinRef:33/binary, PeerClientUDPPort:16>> ->
		    io:format("Client (UDP) : Received udp_peer2peer_ind Port info: PeerClientUDPPort ~p FromIP ~p, FromPort ~p, ~n BinRef: ~p ~n", [PeerClientUDPPort, FromIP, FromPort,ReceivedBinRef]),
		    client_send_peer2peer_pushback_msg (UDPSocket, ClientUDPPort, BinRef, FromIP,FromPort),
		    peer_client_link_started_loop(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef);

		<<?UDP_PEER2PEER_PUSHBACK_IND:16, ReceivedBinRef:33/binary, PeerClientUDPPort:16>> ->
		    io:format("Client (UDP) : Received udp_peer2peer_punchback_ind Port info: PeerClientUDPPort ~p, FromIP ~p, FromPort ~p, ~n BinRef: ~p ~n", [PeerClientUDPPort, FromIP, FromPort,ReceivedBinRef]),

		    client_send_peer2peer_pushback_msg (UDPSocket, ClientUDPPort, BinRef, FromIP,FromPort),
		    peer_client_link_locked(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort,BinRef, FromIP, FromPort);

		InvalidMessage ->
		    io:format("Client (UDPY): Invalid message received ~p~n", [InvalidMessage]),		    
		    peer_client_link_started_loop(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef)
	    end
    after
	Timeout ->
	    io:format("Client: udp_port_info_ind_msg BinRef: ~p ~n", [BinRef]),
	    udp_port_info_ind_msg(UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef)
    end,
    peer_client_link_started_loop(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort,BinRef).

peer_client_link_locked(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort,BinRef, FromIP, FromPort) ->
    Timeout = 10 * 1000,
    inet:setopts(Socket, [{active,once}]),
    inet:setopts(UDPSocket, [{active,once}]),

    receive
	{tcp, Socket, Bin} ->
	    io:format("Client: received binary = ~p~n",[Bin]),
	    case Bin of
		<<?LINK_STOP_IND:16>> ->
		    gen_udp:close(UDPSocket),
		    peer_client_wait_link_started_loop(Socket, ClientUDPPort, ServerUDPPort);

		<<?KEEP_ALIVE_IND:16>> ->
			io:format("Client (TCP): Keep alive received ~n"),
			peer_client_link_locked(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort,BinRef, FromIP, FromPort);

		InvalidMessage ->
		    io:format("Client: Invalid message received ~p~n", [InvalidMessage]),		    
		    peer_client_link_locked(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort,BinRef, FromIP, FromPort)
	    end;
	{udp, UDPSocket, FromIP, FromPort, Bin}->
	    io:format("Client: received binary = ~p~n",[Bin]),
	    case Bin of
		<<?UDP_PEER2PEER_PUSHBACK_IND:16, ReceivedBinRef:33/binary, PeerClientUDPPort:16>> ->
		    io:format("Client (UDP) : Received udp_peer2peer_punchback_ind Port info: PeerClientUDPPort ~p, FromIP ~p, FromPort ~p, ~n BinRef: ~p ~n", [PeerClientUDPPort, FromIP, FromPort,ReceivedBinRef]),
		    peer_client_link_locked(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort,BinRef, FromIP, FromPort);

		InvalidMessage ->
		    io:format("Client (UDP): Invalid message received ~p~n", [InvalidMessage]),		    
		    peer_client_link_locked(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort,BinRef, FromIP, FromPort)
	    end
    after
	Timeout ->
	client_send_peer2peer_pushback_msg (UDPSocket, ClientUDPPort, BinRef, FromIP,FromPort),
	    peer_client_link_locked(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort,BinRef, FromIP, FromPort)
    end,
    peer_client_link_locked(Socket, UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort,BinRef, FromIP, FromPort).    





udp_port_info_ind_msg(UDPSocket, ClientUDPPort, UDPAddress, ServerUDPPort, BinRef) ->
    Msg = nm_messages:udp_port_info_ind(BinRef, ClientUDPPort),
    io:format("Client: Sending  ~p~n",[Msg]),
    ok = gen_udp:send(UDPSocket, UDPAddress, ServerUDPPort, Msg).

client_send_peer2peer_msg (UDPSocket, ClientUDPPort, BinRef, ToIP,ToPort) ->
    Msg = nm_messages:udp_peer2peer_ind(BinRef, ClientUDPPort),
    io:format("Client: Sending ~p to ~p, ~p ~n",[Msg, ToIP, ToPort]),
    ok = gen_udp:send(UDPSocket, ToIP, ToPort, Msg).

client_send_peer2peer_pushback_msg (UDPSocket, ClientUDPPort, BinRef, ToIP,ToPort) ->
    Msg = nm_messages:udp_peer2peer_pushback_ind(BinRef, ClientUDPPort),
    io:format("Client: Sending ~p to ~p, ~p ~n",[Msg, ToIP, ToPort]),
    ok = gen_udp:send(UDPSocket, ToIP, ToPort, Msg).

client_send_attach_req(Socket, Username,Password) ->
    Msg = nm_messages:attach_req(Username, Password),
    io:format("Client: Sending ~p~n",[Msg]),
    ok = gen_tcp:send(Socket, Msg).

client_send_detach_req(Socket) ->
    Msg = nm_messages:detach_req(),
    io:format("Client: Sending ~p~n",[Msg]),
    ok = gen_tcp:send(Socket, Msg).

client_send_setup_request(Socket, PeerUsername, PeerUserPassword) ->
    Msg = nm_messages:setup_req(PeerUsername, PeerUserPassword),
    io:format("Client: Sending ~p~n",[Msg]),
    ok = gen_tcp:send(Socket, Msg).

openports([]) -> [];			       

openports([ClientUDPPort | ClientUDPPortListTail]) ->
    {ok,UDPSocket} = gen_udp:open(ClientUDPPort,[binary]), 
    openports(ClientUDPPortListTail)++[{ClientUDPPort,UDPSocket}].


client_send_peer2peer_msg_salve(ToPortOffset, MinMaxOffSet,UDPSocket, ClientUDPPort, BinRef, ToIP, ToPort) ->
    ToPortWithOffset = ToPort + ToPortOffset,
    io:format("ToPortWithOffset ~w ToPortOffset ~w ~n",[ToPortWithOffset, ToPortOffset]),	
    if 
	(ToPortWithOffset > 1024) and 
	(ToPortOffset > -MinMaxOffSet)->
	    client_send_peer2peer_msg(UDPSocket, ClientUDPPort, BinRef, ToIP, ToPort),
	    client_send_peer2peer_msg_salve(ToPortOffset-1, MinMaxOffSet,UDPSocket, ClientUDPPort, BinRef, ToIP, ToPort);
	true -> 
	    _A=0 %% dummy
    end.

sleep(Time) ->
    receive
    after
	Time ->
	    true
    end.
