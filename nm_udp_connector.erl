-module(nm_udp_connector).
-export([init/1]).
-include("nm_message_types.hrl").

init(Port)->
    {ok,Socket} = gen_udp:open(Port,[binary,{active, true}]),
    io:format("UDP-socket opend ~p~n",[Socket]),
    udp_server_loop(Socket,0).

udp_server_loop(Socket,N)->
    receive 
	{udp, Socket, Ip, PortNo, Bin}->
	    io:format("UDP Server received binary = ~p~n",[Bin]),
	    case Bin of
		<<?UDP_PORT_INFO_IND:16, RefBin:33/binary, ClientUDPPort:16>> ->
		    Ref = binary_to_term(RefBin),
		    io:format("UDP Server: Port info: Ip ~p, Port No. ~p, Ref: ~p ~n", [Ip, PortNo,Ref]),
		    case  nm_user_store:get_udp_process_pid_by_ref(Ref) of 
			{ok, UDPProcessPid} ->
			    io:format("UDP Server: Port info: ClientUDPPort ~p, Ip ~p, Port No. ~p, Ref: ~p, TCPConnectionPid ~p ~n", [ClientUDPPort, Ip, PortNo,Ref,UDPProcessPid]),
			    UDPProcessPid!{udp_port_info_indication, Ip, PortNo, ClientUDPPort},
			    udp_server_loop(Socket,N+1);
			{error, unknownReference}->
			    io:format("UDP Server: Port info message with unkown referenece received!! ~n", []),
			    udp_server_loop(Socket,N+1)
		    end;
		InvalidMessage ->
		    io:format("UDP server: Invalid message received ~p~n", [InvalidMessage]),		    
		    udp_server_loop(Socket,N+1)
	    end
    end.
