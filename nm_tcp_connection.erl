
%% communicate over tcp in order to start hole punching

-module(nm_tcp_connection).
-export([server_receive_process_loop/1 ]).
-include("nm_message_types.hrl").

server_receive_process_loop(Socket) ->
    Nm_tcp_connection_Pid = self(), 
    Nm_udp_link_ProcessPid = 
	spawn_link(fun() -> nm_udp_link_statemachine:server_state_udp_link_unlocked(Nm_tcp_connection_Pid) end),
    Nm_tcp_send_ProcessPid =
	spawn_link(fun() -> nm_tcp_send_process:tcp_send_process_loop(Socket) end),
    server_state_detached(Nm_udp_link_ProcessPid, Socket, Nm_tcp_send_ProcessPid, unlocked, 0, 0).

server_state_detached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, LockStatus, IP, PortNo) ->
    inet:setopts(Socket, [{active,once}, {keepalive,true}]),
    receive
	{tcp, Socket, Bin} ->
	    io:format("Server received binary = ~p~n",[Bin]),
	    case Bin of
		<<?DETACH_REQ:16>> ->
		    detach_resp(Nm_tcp_send_ProcessPid),
		    server_state_detached(Nm_udp_link_ProcessPid, Socket, Nm_tcp_send_ProcessPid, LockStatus, IP, PortNo);


		<<?ATTACH_REQ:16,UsernameSize:8,Username:UsernameSize/binary,
		  PasswordSize:8, Password:PasswordSize/binary>> ->
		    %% check if user alredy exists:
		    case nm_user_store:user_exists(Username) of 
			{ok, userIsAvailable} -> 
			    attach_rej(Nm_tcp_send_ProcessPid,alreadyAttachedError),
			    server_state_detached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, LockStatus, IP, PortNo);
			{error, userIsNotAvailable} -> 
			    %% create user and store password and pid.
			    nm_user_store:create_user(Username, Password, self(),Nm_udp_link_ProcessPid),
			    attach_resp(Nm_tcp_send_ProcessPid,Username, Password),
			    server_state_attached(Nm_udp_link_ProcessPid, Socket, Nm_tcp_send_ProcessPid, Username, LockStatus, IP, PortNo)
		    end;

		<<?SETUP_REQ:16,
		  PeerUsernameSize:8, _PeerUsername:PeerUsernameSize/binary,
		  PeerUserPasswordSize:8, _PeerUserPassword:PeerUserPasswordSize/binary>> ->	
		    io:format("Server: Error, setup failed, as not yet attached",[]),
		    setup_rej(Nm_tcp_send_ProcessPid, notAttachedError),
		    server_state_detached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, LockStatus, IP, PortNo);

		<<?RELEASE_REQ>> ->
		    release_rej(Nm_tcp_send_ProcessPid, notConnectedError),
		    server_state_detached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, LockStatus, IP, PortNo);

		InvalidMessage ->
		    io:format("Invalid message received ~p~n", [InvalidMessage]),		    
		    server_state_detached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, LockStatus, IP, PortNo)

	    end;
	{udp_link_establish_request, ConnectionInitiatorPID}->
	    ConnectionInitiatorPID!{udp_link_establish_reject, connectionResponderIsDetachedError},
	    io:format("Server: Link establishment to this connection impossible, as this connection is detached",[]),
	    server_state_detached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, LockStatus, IP, PortNo);

	{tcp_closed,Socket} ->
	    %% tcp connection was released
	    io:format("Server socket closed ~n"),
            exit(all);

	{link_lock_indication,IP,PortNo} ->
	    server_state_detached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, locked, IP, PortNo);

	link_unlock_indication ->
	    server_state_detached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, unlocked, 0, 0);

	release_request->
	    link_stop_ind(Nm_tcp_send_ProcessPid),
	    server_state_detached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, LockStatus, IP, PortNo)
    end.

server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, LockStatus, IP, PortNo) ->
    inet:setopts(Socket, [{active,once}, {keepalive,true}]),
    receive
	{tcp, Socket, Bin} ->
	    io:format("Server received binary = ~p~n",[Bin]),
	    case Bin of
		<<?DETACH_REQ>> ->
		    nm_user_store:delete_by_username(Username),
		    detach_resp(Nm_tcp_send_ProcessPid),
		    server_state_detached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, LockStatus, IP, PortNo);

		<<?ATTACH_REQ:16,UsernameSize:8,_Username:UsernameSize/binary,
		  PasswordSize:8, _Password:PasswordSize/binary>> ->
		    io:format("Server: Error. Already attached!!!", []),
		    attach_rej(Nm_tcp_send_ProcessPid,alreadyAttachedError),
		    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, LockStatus, IP, PortNo);


		<<?SETUP_REQ:16,
                  PeerUsernameSize:8, PeerUsername:PeerUsernameSize/binary,
		  PeerUserPasswordSize:8, PeerUserPassword:PeerUserPasswordSize/binary>> ->
		    io:format("Server: Received setup request to peer user ~p with peer user password ~p~n", [PeerUsername, PeerUserPassword]),

		    %% Step 1: Check if peer user is currently attached
		    %% Step 1a): If peer user is not attached, send setup_rej message with error code peerNotAttached
		    %% Step 1b): If peer user is attached and given password is not correct, send setup_rej with 
		    %%           error code passwordIncorrect.
		    case nm_user_store:is_user_attached(PeerUsername) of
			false ->
			    setup_rej(Nm_tcp_send_ProcessPid,peerNotAttachedError),
			    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, LockStatus, IP, PortNo);
			true -> 
			    case nm_user_store:check_password(PeerUsername, PeerUserPassword) of
				{error, incorrectPassword} ->
				    setup_rej(Nm_tcp_send_ProcessPid,passwordIncorrectError),
				    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, LockStatus, IP, PortNo);   
				ok ->
				    case nm_user_store:get_pid(PeerUsername) of
					{error, pidIsNotAvailable}->
					    setup_rej(Nm_tcp_send_ProcessPid, pidIsNotAvailableError),
					    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, LockStatus, IP, PortNo);

					{ok, ConnectionResponderPID}->
					    %% Step 2): Otherwise lookup peer PID from datastore and 
					    %%          forward setup_request-message to process of peer user. 
					    io:format("Server: ConnectionResponderPID ~p~n", [ConnectionResponderPID]),
					    ConnectionResponderPID!{udp_link_establish_request,self()},

					    setup_resp(Nm_tcp_send_ProcessPid, Username, PeerUsername),
					    {ok,Ref} =  nm_user_store:get_ref(Username),					    
					    link_start_ind(Nm_tcp_send_ProcessPid, Ref),
					    receive
						{udp_link_establish_response, ok}->
						    %% This user has requested link establishment to peer user.
						    case LockStatus of
							locked ->
							    InitiatorIP =IP,
							    InitiatorPortNo = PortNo,
							    server_state_connection_initiator_link_locked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, InitiatorIP, InitiatorPortNo);
							unlocked  ->
							    server_state_connection_initiator_link_unlocked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID)
						    end;
						{udp_link_establish_response, peerAlreadyConnectedError}->
						    setup_rej(Nm_tcp_send_ProcessPid, peerAlreadyConnectedError),
						    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, LockStatus, IP, PortNo);

						{udp_link_establish_reject, connectionResponderIsDetachedError}->
						    setup_rej(Nm_tcp_send_ProcessPid, peerIsDetachedError),
						    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, LockStatus, IP, PortNo)
					    end

				    end
			    end
		    end;

		<<?RELEASE_REQ>> ->
		    release_rej(Nm_tcp_send_ProcessPid, notConnectedError),
		    link_stop_ind(Nm_tcp_send_ProcessPid),
		    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, LockStatus, IP, PortNo);

		InvalidMessage ->
		    io:format("Invalid message received ~p~n", [InvalidMessage]),
		    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, LockStatus, IP, PortNo)
	    end;

	{udp_link_establish_request, ConnectionInitiatorPID}->
	    %% A peer user has requested link establishment to this user.
	    ConnectionInitiatorPID!{udp_link_establish_response, ok},
	    {ok,Ref} =  nm_user_store:get_ref(Username),					    
	    link_start_ind(Nm_tcp_send_ProcessPid, Ref),
	    case LockStatus of
		locked ->
		    ResponderIpAddress = IP,
		    ResponderPortNo = PortNo,
		    server_state_connection_responder_link_locked_initiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, ResponderIpAddress, ResponderPortNo);
		unlocked  ->
		    server_state_connection_responder_link_unlocked_intiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID)
	    end;

	{tcp_closed,Socket} ->
	    %% tcp connection was released
	    io:format("Server socket closed ~n"),
	    nm_user_store:delete_by_username(Username),
            exit(all);

	{link_lock_indication,IP,PortNo} ->
	    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, locked, IP, PortNo);

	link_unlock_indication ->
	    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, unlocked, 0, 0);

	release_request->
	    link_stop_ind(Nm_tcp_send_ProcessPid),
	    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, LockStatus, IP, PortNo)
    end.

server_state_connection_initiator_link_unlocked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID) ->
    %% Lock client.
    %% If locked, go to state locked
    %% link_lock_req(Nm_tcp_send_ProcessPid),
    inet:setopts(Socket, [{active,once}, {keepalive,true}]), 
    receive 
	{tcp, Socket, Bin} ->
	    io:format("Server received binary = ~p~n",[Bin]),
	    case Bin of
		<<?DETACH_REQ>> ->
		    nm_user_store:delete_by_username(Username),
		    detach_resp(Nm_tcp_send_ProcessPid),
		    server_state_detached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, unlocked, 0, 0);

		<<?ATTACH_REQ:16,UsernameSize:8,_Username:UsernameSize/binary,
		  PasswordSize:8, _Password:PasswordSize/binary>> ->
		    io:format("Server: Error. Already attached!!!", []),
		    attach_rej(Nm_tcp_send_ProcessPid,alreadyAttachedError),
		    server_state_connection_initiator_link_unlocked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID);

		<<?SETUP_REQ:16,
                  PeerUsernameSize:8, _PeerUsername:PeerUsernameSize/binary,
		  PeerUserPasswordSize:8, _PeerUserPassword:PeerUserPasswordSize/binary>> ->
		    io:format("Server: Error, setup failed, as already setup",[]),
		    setup_rej(Nm_tcp_send_ProcessPid, alreadySetupError),
		    server_state_connection_initiator_link_unlocked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID);

		<<?RELEASE_REQ>> ->
		    release_resp(Nm_tcp_send_ProcessPid),
		    %% release connection
		    ConnectionResponderPID!release_request,
		    link_stop_ind( Nm_tcp_send_ProcessPid),
		    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, unlocked, 0, 0);

		InvalidMessage ->
		    io:format("Invalid message received ~p~n", [InvalidMessage]),		    
		    server_state_connection_initiator_link_unlocked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID)
	    end;

	{udp_link_establish_request,ConnectionInitiatorPID}->
	    ConnectionInitiatorPID!{udp_link_establish_response, peerAlreadyConnectedError},
	    server_state_connection_initiator_link_unlocked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID);

	{tcp_closed,Socket} ->
	    %% tcp connection was released
	    io:format("Server socket closed ~n"),
	    ConnectionResponderPID!release_request,
	    link_stop_ind( Nm_tcp_send_ProcessPid),
	    nm_user_store:delete_by_username(Username),
            exit(all);


	{link_lock_indication,InitiatorIP,InitiatorPortNo}->
	    %% Step 4): Inform this user about ip-address and port for UDP of peer
	    ConnectionResponderPID!{initiator_connection_indication,InitiatorIP,InitiatorPortNo},
	    server_state_connection_initiator_link_locked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, InitiatorIP, InitiatorPortNo);

	link_unlock_indication ->
	    %% peer side failed setting up the UDP link
	    ConnectionResponderPID!initiator_no_connection_indication,
	    server_state_connection_initiator_link_unlocked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID);

	{responder_connection_indication,ResponderIpAddress,ResponderPortNo} ->
	    punch_start_ind(Nm_tcp_send_ProcessPid, ResponderIpAddress, ResponderPortNo),
	    server_state_connection_initiator_link_unlocked_responder_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, ResponderIpAddress, ResponderPortNo);

	responder_no_connection_indication ->
	    punch_stop_ind(Nm_tcp_send_ProcessPid),
	    server_state_connection_initiator_link_unlocked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID);


	release_request->

	    link_stop_ind( Nm_tcp_send_ProcessPid),
	    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, unlocked, 0, 0)

    end.

server_state_connection_initiator_link_unlocked_responder_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, ResponderIpAddress, ResponderPortNo)->
    inet:setopts(Socket, [{active,once}, {keepalive,true}]), 
    receive 
	{tcp, Socket, Bin} ->
	    io:format("Server received binary = ~p~n",[Bin]),
	    case Bin of
		<<?DETACH_REQ>> ->
		    nm_user_store:delete_by_username(Username),
		    detach_resp(Nm_tcp_send_ProcessPid),
		    server_state_detached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, unlocked, 0, 0);

		<<?ATTACH_REQ:16,
		  UsernameSize:8,_Username:UsernameSize/binary,
		  PasswordSize:8, _Password:PasswordSize/binary>> ->
		    io:format("Server: Error. Already attached!!!", []),
		    attach_rej(Nm_tcp_send_ProcessPid,alreadyAttachedError),
		    server_state_connection_initiator_link_unlocked_responder_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, ResponderIpAddress, ResponderPortNo);

		<<?SETUP_REQ:16,
                  PeerUsernameSize:8, _PeerUsername:PeerUsernameSize/binary,
		  PeerUserPasswordSize:8, _PeerUserPassword:PeerUserPasswordSize/binary>> ->
		    io:format("Server: Error, setup failed, as not yet attached",[]),
		    setup_rej(Nm_tcp_send_ProcessPid, alreadySetupError),
		    server_state_connection_initiator_link_unlocked_responder_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, ResponderIpAddress, ResponderPortNo);

		<<?RELEASE_REQ>> ->
		    release_resp(Nm_tcp_send_ProcessPid),
		    %% release connection
		    ConnectionResponderPID!release_request,
		    link_stop_ind( Nm_tcp_send_ProcessPid),
		    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, unlocked, 0, 0);

		InvalidMessage ->
		    io:format("Invalid message received ~p~n", [InvalidMessage]),		    
		    server_state_connection_initiator_link_unlocked_responder_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, ResponderIpAddress, ResponderPortNo)
	    end;

	{udp_link_establish_request,ConnectionInitiatorPID}->
	    ConnectionInitiatorPID!{udp_link_establish_response, peerAlreadyConnectedError},
	    server_state_connection_initiator_link_unlocked_responder_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, ResponderIpAddress, ResponderPortNo);

	{tcp_closed,Socket} ->
	    %% tcp connection was released
	    io:format("Server socket closed ~n"),
	    ConnectionResponderPID!release_request,
	    link_stop_ind( Nm_tcp_send_ProcessPid),
	    nm_user_store:delete_by_username(Username),
            exit(all);

	{link_lock_indication,UpdatedInitiatorIpAddress,UpdatedInitiatorPortNo}->
	    ConnectionResponderPID!{initiator_connection_indication, UpdatedInitiatorIpAddress, UpdatedInitiatorPortNo},
	    server_state_connection_initiator_link_locked_responder_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, UpdatedInitiatorIpAddress, UpdatedInitiatorPortNo, ResponderIpAddress, ResponderPortNo);

	link_unlock_indication ->
	    %% peer side failed setting up the UDP link
	    ConnectionResponderPID!initiator_no_connection_indication,
	    server_state_connection_initiator_link_unlocked_responder_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, ResponderIpAddress, ResponderPortNo);

	{responder_connection_indication,UpdatedResponderIpAddress,UpdatedResponderPortNo} ->
	    punch_start_ind(Nm_tcp_send_ProcessPid, UpdatedResponderIpAddress, UpdatedResponderPortNo),
	    server_state_connection_initiator_link_unlocked_responder_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, UpdatedResponderIpAddress, UpdatedResponderPortNo);

	responder_no_connection_indication ->
	    punch_stop_ind(Nm_tcp_send_ProcessPid),
	    server_state_connection_initiator_link_unlocked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID);

	release_request->

	    link_stop_ind( Nm_tcp_send_ProcessPid),
	    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, unlocked, 0, 0)
    end.

server_state_connection_initiator_link_locked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, InitiatorIpAddress, InitiatorPortNo) ->
    %% Wait for reception of IP-address & port from connection responderRequest client to lock
    %%  and request its IP-Address & port
    %% Step 3): Wait for ip-address and port from peer, reject upon timeout
    inet:setopts(Socket, [{active,once}, {keepalive,true}]), 
    receive 
	{tcp, Socket, Bin} ->
	    io:format("Server received binary = ~p~n",[Bin]),
	    case Bin of
		<<?DETACH_REQ>> ->
		    nm_user_store:delete_by_username(Username),
		    detach_resp(Nm_tcp_send_ProcessPid),
		    server_state_detached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, unlocked, 0, 0);

		<<?ATTACH_REQ:16,
  		  UsernameSize:8,_Username:UsernameSize/binary,
		  PasswordSize:8, _Password:PasswordSize/binary>> ->
		    io:format("Server: Error. Already attached!!!", []),
		    attach_rej(Nm_tcp_send_ProcessPid,alreadyAttachedError),
		    server_state_connection_initiator_link_locked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, InitiatorIpAddress, InitiatorPortNo);

		<<?SETUP_REQ:16,
                  PeerUsernameSize:8, _PeerUsername:PeerUsernameSize/binary,
		  PeerUserPasswordSize:8, _PeerUserPassword:PeerUserPasswordSize/binary>> ->
		    io:format("Server: Error, setup failed, as not yet attached",[]),
		    setup_rej(Nm_tcp_send_ProcessPid, alreadySetupError),
		    server_state_connection_initiator_link_locked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, InitiatorIpAddress, InitiatorPortNo);

		<<?RELEASE_REQ>> ->
		    release_resp(Nm_tcp_send_ProcessPid),
		    %% release connection
		    ConnectionResponderPID!release_request,
		    link_stop_ind( Nm_tcp_send_ProcessPid),
		    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, locked, InitiatorIpAddress, InitiatorPortNo);

		InvalidMessage ->
		    io:format("Invalid message received ~p~n", [InvalidMessage]),		    
		    server_state_connection_initiator_link_locked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, InitiatorIpAddress, InitiatorPortNo)
	    end;

	{udp_link_establish_request,ConnectionInitiatorPID}->
	    ConnectionInitiatorPID!{udp_link_establish_response, peerAlreadyConnectedError},
	    server_state_connection_initiator_link_locked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, InitiatorIpAddress, InitiatorPortNo);

	{tcp_closed,Socket} ->
	    %% tcp connection was released
	    io:format("Server socket closed ~n"),
	    ConnectionResponderPID!release_request,
	    link_stop_ind( Nm_tcp_send_ProcessPid),
	    nm_user_store:delete_by_username(Username),
            exit(all);

	{link_lock_indication,UpdatedInitiatorIpAddress,UpdatedInitiatorPortNo}->
	    %% Step 4): Inform this user about ip-address and port for UDP of peer
	    ConnectionResponderPID!{initiator_connection_indication,UpdatedInitiatorIpAddress,UpdatedInitiatorPortNo},
	    server_state_connection_initiator_link_locked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, UpdatedInitiatorIpAddress, UpdatedInitiatorPortNo);

	link_unlock_indication ->
	    %% peer side failed setting up the UDP link
	    ConnectionResponderPID!initiator_no_connection_indication,
	    server_state_connection_initiator_link_unlocked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID);

	{responder_connection_indication,ResponderIpAddress,ResponderPortNo} ->
	    punch_start_ind(Nm_tcp_send_ProcessPid, ResponderIpAddress, ResponderPortNo),
	    server_state_connection_initiator_link_locked_responder_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, InitiatorIpAddress, InitiatorPortNo, ResponderIpAddress, ResponderPortNo);

	responder_no_connection_indication ->
	    punch_stop_ind(Nm_tcp_send_ProcessPid),
	    server_state_connection_initiator_link_locked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, InitiatorIpAddress, InitiatorPortNo);

	release_request->
	    link_stop_ind( Nm_tcp_send_ProcessPid),
	    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, locked, InitiatorIpAddress, InitiatorPortNo)
    end.

server_state_connection_initiator_link_locked_responder_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, InitiatorIpAddress, InitiatorPortNo, ResponderIpAddress, ResponderPortNo)->
    inet:setopts(Socket, [{active,once}, {keepalive,true}]),
    receive
	{tcp, Socket, Bin} ->
	    io:format("Server received binary = ~p~n",[Bin]),
	    case Bin of
		<<?DETACH_REQ>> ->
		    nm_user_store:delete_by_username(Username),
		    detach_resp(Nm_tcp_send_ProcessPid),
		    server_state_detached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, locked, InitiatorIpAddress, InitiatorPortNo);

		<<?ATTACH_REQ:16,
		  UsernameSize:8,_Username:UsernameSize/binary,
		  PasswordSize:8, _Password:PasswordSize/binary>> ->
		    io:format("Server: Error. Already attached!!!", []),
		    attach_rej(Nm_tcp_send_ProcessPid,alreadyAttachedError),
		    server_state_connection_initiator_link_locked_responder_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, InitiatorIpAddress, InitiatorPortNo, ResponderIpAddress, ResponderPortNo);

		<<?SETUP_REQ:16,
                  PeerUsernameSize:8, _PeerUsername:PeerUsernameSize/binary,
		  PeerUserPasswordSize:8, _PeerUserPassword:PeerUserPasswordSize/binary>> ->
		    io:format("Server: Error, setup failed, as not yet attached",[]),
		    setup_rej(Nm_tcp_send_ProcessPid, alreadySetupError),
		    server_state_connection_initiator_link_locked_responder_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, InitiatorIpAddress, InitiatorPortNo, ResponderIpAddress, ResponderPortNo);

		<<?RELEASE_REQ>> ->
		    release_resp(Nm_tcp_send_ProcessPid),
		    %% release connection
		    ConnectionResponderPID!release_request,
		    link_stop_ind( Nm_tcp_send_ProcessPid),
		    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, locked, InitiatorIpAddress, InitiatorPortNo);

		InvalidMessage ->
		    io:format("Invalid message received ~p~n", [InvalidMessage]),
		    server_state_connection_initiator_link_locked_responder_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, InitiatorIpAddress, InitiatorPortNo, ResponderIpAddress, ResponderPortNo)
	    end;

	{udp_link_establish_request,ConnectionInitiatorPID}->
	    ConnectionInitiatorPID!{udp_link_establish_response, peerAlreadyConnectedError},
	    server_state_connection_initiator_link_locked_responder_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, InitiatorIpAddress, InitiatorPortNo, ResponderIpAddress, ResponderPortNo);

	{tcp_closed,Socket} ->
	    %% tcp connection was released
	    io:format("Server socket closed ~n"),
	    ConnectionResponderPID!release_request,
	    link_stop_ind( Nm_tcp_send_ProcessPid),
	    nm_user_store:delete_by_username(Username),
            exit(all);

	{link_lock_indication,UpdatedInitiatorIpAddress, UpdatedInitiatorPortNo} ->
	    ConnectionResponderPID!{initiator_connection_indication,UpdatedInitiatorIpAddress,UpdatedInitiatorPortNo},
	    server_state_connection_initiator_link_locked_responder_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, UpdatedInitiatorIpAddress, UpdatedInitiatorPortNo, ResponderIpAddress, ResponderPortNo);

	link_unlock_indication ->
	    ConnectionResponderPID!initiator_no_connection_indication,
	    server_state_connection_initiator_link_unlocked_responder_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, ResponderIpAddress, ResponderPortNo);

	{responder_connection_indication,UpdatedResponderIpAddress,UpdatedResponderPortNo} ->
	    punch_start_ind(Nm_tcp_send_ProcessPid, UpdatedResponderIpAddress, UpdatedResponderPortNo),
	    server_state_connection_initiator_link_locked_responder_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, InitiatorIpAddress, InitiatorPortNo, UpdatedResponderIpAddress, UpdatedResponderPortNo);

	responder_no_connection_indication ->
	    punch_stop_ind(Nm_tcp_send_ProcessPid),
	    server_state_connection_initiator_link_locked_responder_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionResponderPID, InitiatorIpAddress, InitiatorPortNo);


	release_request->

	    link_stop_ind( Nm_tcp_send_ProcessPid),
	    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, locked, InitiatorIpAddress, InitiatorPortNo)

    end.

server_state_connection_responder_link_unlocked_intiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID) ->
    %% Lock client.
    %% If locked, go to state locked:
    %%          Provide IP-Address and PortNo to connection initiator
    %% link_lock_req(Nm_tcp_send_ProcessPid),
    inet:setopts(Socket, [{active,once}, {keepalive,true}]), 
    receive 
	{tcp, Socket, Bin} ->
	    io:format("Server received binary = ~p~n",[Bin]),
	    case Bin of
		<<?DETACH_REQ>> ->
		    nm_user_store:delete_by_username(Username),
		    detach_resp(Nm_tcp_send_ProcessPid),
		    server_state_detached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, unlocked, 0, 0);

		<<?ATTACH_REQ:16,
		  UsernameSize:8,_Username:UsernameSize/binary,
		  PasswordSize:8, _Password:PasswordSize/binary>> ->
		    io:format("Server: Error. Already attached!!!", []),
		    attach_rej(Nm_tcp_send_ProcessPid,alreadyAttachedError),
		    server_state_connection_responder_link_unlocked_intiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID);

		<<?SETUP_REQ:16,
                  PeerUsernameSize:8, _PeerUsername:PeerUsernameSize/binary,
		  PeerUserPasswordSize:8, _PeerUserPassword:PeerUserPasswordSize/binary>> ->
		    io:format("Server: Error, setup failed, as not yet attached",[]),
		    setup_rej(Nm_tcp_send_ProcessPid, alreadySetupError),
		    server_state_connection_responder_link_unlocked_intiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID);

		<<?RELEASE_REQ>> ->
		    release_resp(Nm_tcp_send_ProcessPid),
		    ConnectionInitiatorPID!release_request,
		    link_stop_ind( Nm_tcp_send_ProcessPid),
		    %% release connection
		    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, unlocked, 0, 0);

		InvalidMessage ->
		    io:format("Invalid message received ~p~n", [InvalidMessage]),
		    server_state_connection_responder_link_unlocked_intiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID)
	    end;

	{udp_link_establish_request,ConnectionInitiatorPID}->
	    ConnectionInitiatorPID!{udp_link_establish_response, peerAlreadyConnectedError},
	    server_state_connection_responder_link_unlocked_intiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID);

	{tcp_closed,Socket} ->
	    %% tcp connection was released
	    io:format("Server socket closed ~n"),
	    ConnectionInitiatorPID!release_request,
	    link_stop_ind( Nm_tcp_send_ProcessPid),
	    nm_user_store:delete_by_username(Username),
            exit(all);

	{link_lock_indication,ResponderIpAddress,ResponderPortNo}->
	    %% Step 4): Inform this user about ip-address and port for UDP of peer
	    ConnectionInitiatorPID!{responder_connection_indication, ResponderIpAddress, ResponderPortNo},
	    server_state_connection_responder_link_locked_initiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, ResponderIpAddress, ResponderPortNo);

	link_unlock_indication ->
	    %% peer side failed setting up the UDP link
	    ConnectionInitiatorPID!responder_no_connection_indication,
	    server_state_connection_responder_link_unlocked_intiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID);

	{initiator_connection_indication, InitiatorIP, InitiatorPortNo} ->
	    punch_start_ind(Nm_tcp_send_ProcessPid, InitiatorIP, InitiatorPortNo),
	    server_state_connection_responder_link_unlocked_intiator_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, InitiatorIP, InitiatorPortNo); 

	initiator_no_connection_indication ->
	    punch_stop_ind(Nm_tcp_send_ProcessPid),
	    server_state_connection_responder_link_unlocked_intiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID);

	release_request->

	    link_stop_ind( Nm_tcp_send_ProcessPid),
	    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, unlocked, 0, 0)

    end.

server_state_connection_responder_link_unlocked_intiator_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID,InitiatorIP,InitiatorPortNo) ->
    %% Lock client.
    %% If locked, go to state locked:
    %%          Provide IP-Address and PortNo to connection initiator
    %% link_lock_req(Nm_tcp_send_ProcessPid),
    inet:setopts(Socket, [{active,once}, {keepalive,true}]), 
    receive 
	{tcp, Socket,  Bin} ->
	    io:format("Server received binary = ~p~n",[Bin]),
	    case Bin of
		<<?DETACH_REQ>> ->
		    nm_user_store:delete_by_username(Username),
		    detach_resp(Nm_tcp_send_ProcessPid),
		    server_state_detached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, unlocked, 0, 0);

		<<?ATTACH_REQ:16,
		  UsernameSize:8, _Username:UsernameSize/binary,
		  PasswordSize:8, _Password:PasswordSize/binary>> ->
		    io:format("Server: Error. Already attached!!!", []),
		    attach_rej(Nm_tcp_send_ProcessPid,alreadyAttachedError),
		    server_state_connection_responder_link_unlocked_intiator_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID,InitiatorIP,InitiatorPortNo);

		<<?SETUP_REQ:16,
                  PeerUsernameSize:8, _PeerUsername:PeerUsernameSize/binary,
		  PeerUserPasswordSize:8, _PeerUserPassword:PeerUserPasswordSize/binary>> ->
		    io:format("Server: Error, setup failed, as not yet attached",[]),
		    setup_rej(Nm_tcp_send_ProcessPid, alreadySetupError),
		    server_state_connection_responder_link_unlocked_intiator_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID,InitiatorIP,InitiatorPortNo);

		<<?RELEASE_REQ>> ->
		    release_resp(Nm_tcp_send_ProcessPid),
		    ConnectionInitiatorPID!release_request,
		    link_stop_ind( Nm_tcp_send_ProcessPid),
		    %% release connection
		    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, unlocked, 0, 0);

		InvalidMessage ->
		    io:format("Invalid message received ~p~n", [InvalidMessage]),
		    server_state_connection_responder_link_unlocked_intiator_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID,InitiatorIP,InitiatorPortNo)
	    end;

	{udp_link_establish_request,ConnectionInitiatorPID}->
	    ConnectionInitiatorPID!{udp_link_establish_response, peerAlreadyConnectedError},
	    server_state_connection_responder_link_unlocked_intiator_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID,InitiatorIP,InitiatorPortNo);

	{tcp_closed,Socket} ->
	    %% tcp connection was released
	    io:format("Server socket closed ~n"),
	    ConnectionInitiatorPID!release_request,
	    link_stop_ind( Nm_tcp_send_ProcessPid),
	    nm_user_store:delete_by_username(Username),
            exit(all);

	{link_lock_indication,ResponderIpAddress,ResponderPortNo}->
	    %% Step 4): Inform this user about ip-address and port for UDP of peer
	    ConnectionInitiatorPID!{responder_connection_indication, ResponderIpAddress, ResponderPortNo},
	    server_state_connection_responder_link_locked_initiator_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, ResponderIpAddress, ResponderPortNo, InitiatorIP,InitiatorPortNo) ;

	link_unlock_indication ->
	    %% peer side failed setting up the UDP link
	    ConnectionInitiatorPID!responder_no_connection_indication,
	    server_state_connection_responder_link_unlocked_intiator_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID,InitiatorIP,InitiatorPortNo);

	{initiator_connection_indication, UpdatedInitiatorIP,UpdatedInitiatorPortNo} ->
	    punch_start_ind(Nm_tcp_send_ProcessPid, UpdatedInitiatorIP, UpdatedInitiatorPortNo),
	    server_state_connection_responder_link_unlocked_intiator_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, UpdatedInitiatorIP, UpdatedInitiatorPortNo); 

	initiator_no_connection_indication ->
	    punch_stop_ind(Nm_tcp_send_ProcessPid),
	    server_state_connection_responder_link_unlocked_intiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID);

	release_request->
	    link_stop_ind( Nm_tcp_send_ProcessPid),
	    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, unlocked, 0, 0)

    end.

server_state_connection_responder_link_locked_initiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, ResponderIpAddress, ResponderPortNo) ->
    %% If not locked, go to state unlocked:
    %%          Inform connection initiator about IP-address and port number

    ConnectionInitiatorPID!{udp_link_establish_response, ResponderIpAddress, ResponderPortNo}, 
    inet:setopts(Socket, [{active,once}, {keepalive,true}]), 
    receive 
	{tcp, Socket, Bin} ->
	    io:format("Server received binary = ~p~n",[Bin]),
	    case Bin of
		<<?DETACH_REQ>> ->
		    nm_user_store:delete_by_username(Username),
		    detach_resp(Nm_tcp_send_ProcessPid),
		    server_state_detached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, locked, ResponderIpAddress, ResponderPortNo);

		<<?ATTACH_REQ:16,
		  UsernameSize:8,_Username:UsernameSize/binary,
		  PasswordSize:8, _Password:PasswordSize/binary>> ->
		    io:format("Server: Error. Already attached!!!", []),
		    attach_rej(Nm_tcp_send_ProcessPid,alreadyAttachedError),
		    server_state_connection_responder_link_locked_initiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, ResponderIpAddress, ResponderPortNo) ;

		<<?SETUP_REQ:16,
                  PeerUsernameSize:8, _PeerUsername:PeerUsernameSize/binary,
		  PeerUserPasswordSize:8, _PeerUserPassword:PeerUserPasswordSize/binary>> ->
		    io:format("Server: Error, setup failed, as not yet attached",[]),
		    setup_rej(Nm_tcp_send_ProcessPid, alreadySetupError),
		    server_state_connection_responder_link_locked_initiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, ResponderIpAddress, ResponderPortNo);

		<<?RELEASE_REQ>>->
		    release_resp(Nm_tcp_send_ProcessPid),
		    ConnectionInitiatorPID!release_request,
		    link_stop_ind( Nm_tcp_send_ProcessPid),
		    %% release connection
		    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, locked, ResponderIpAddress, ResponderPortNo);

		InvalidMessage ->
		    io:format("Invalid message received ~p~n", [InvalidMessage]),
		    server_state_connection_responder_link_locked_initiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, ResponderIpAddress, ResponderPortNo) 
	    end;

	{udp_link_establish_request,ConnectionInitiatorPID}->
	    ConnectionInitiatorPID!{udp_link_establish_response, peerAlreadyConnectedError},
	    server_state_connection_responder_link_locked_initiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, ResponderIpAddress, ResponderPortNo);

	{tcp_closed,Socket} ->
	    %% tcp connection was released
	    io:format("Server socket closed ~n"),
	    ConnectionInitiatorPID!release_request,
	    link_stop_ind( Nm_tcp_send_ProcessPid),
	    nm_user_store:delete_by_username(Username),
            exit(all);

	{link_lock_indication,UpdatedResponderIpAddress,UpdatedResponderPortNo}->
	    %% Step 4): Inform this user about ip-address and port for UDP of peer
	    ConnectionInitiatorPID!{responder_connection_indication,UpdatedResponderIpAddress,UpdatedResponderPortNo},
	    server_state_connection_responder_link_locked_initiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, UpdatedResponderIpAddress, UpdatedResponderPortNo);

	link_unlock_indication ->
	    %% peer side failed setting up the UDP link
	    ConnectionInitiatorPID!responder_no_connection_indication,
	    server_state_connection_responder_link_unlocked_intiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID);

	{initiator_connection_indication,InitiatorIP,InitiatorPortNo} ->
	    punch_start_ind(Nm_tcp_send_ProcessPid, InitiatorIP, InitiatorPortNo),
	    server_state_connection_responder_link_locked_initiator_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, ResponderIpAddress, ResponderPortNo, InitiatorIP,InitiatorPortNo); 

	initiator_no_connection_indication ->
	    punch_stop_ind(Nm_tcp_send_ProcessPid),
	    server_state_connection_responder_link_locked_initiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, ResponderIpAddress, ResponderPortNo);

	release_request->
	    link_stop_ind( Nm_tcp_send_ProcessPid),
	    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, locked, ResponderIpAddress, ResponderPortNo)
    end.

server_state_connection_responder_link_locked_initiator_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, ResponderIpAddress, ResponderPortNo, InitiatorIP,InitiatorPortNo) ->
    %% If not locked, go to state unlocked:
    %%          Inform connection initiator about IP-address and port number

    ConnectionInitiatorPID!{udp_link_establish_response, ResponderIpAddress, ResponderPortNo}, 
    inet:setopts(Socket, [{active,once}, {keepalive,true}]), 
    receive 
	{tcp, Socket, Bin} ->
	    io:format("Server received binary = ~p~n",[Bin]),
	    case Bin of
		<<?DETACH_REQ>> ->
		    nm_user_store:delete_by_username(Username),
		    detach_resp(Nm_tcp_send_ProcessPid),
		    server_state_detached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, locked, ResponderIpAddress, ResponderPortNo);

		<<?ATTACH_REQ:16,
		  UsernameSize:8,_Username:UsernameSize/binary,
		  PasswordSize:8, _Password:PasswordSize/binary>> ->
		    io:format("Server: Error. Already attached!!!", []),
		    attach_rej(Nm_tcp_send_ProcessPid,alreadyAttachedError),
		    server_state_connection_responder_link_locked_initiator_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, ResponderIpAddress, ResponderPortNo, InitiatorIP,InitiatorPortNo);

		<<?SETUP_REQ:16,
                  PeerUsernameSize:8, _PeerUsername:PeerUsernameSize/binary,
		  PeerUserPasswordSize:8, _PeerUserPassword:PeerUserPasswordSize/binary>> ->
		    io:format("Server: Error, setup failed, as not yet attached",[]),
		    setup_rej(Nm_tcp_send_ProcessPid, alreadySetupError),
		    server_state_connection_responder_link_locked_initiator_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, ResponderIpAddress, ResponderPortNo, InitiatorIP,InitiatorPortNo);

		<<?RELEASE_REQ>> ->
		    release_resp(Nm_tcp_send_ProcessPid),
		    ConnectionInitiatorPID!release_request,
		    link_stop_ind( Nm_tcp_send_ProcessPid),
		    %% release connection
		    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, locked, ResponderIpAddress, ResponderPortNo);

		InvalidMessage ->
		    io:format("Invalid message received ~p~n", [InvalidMessage]),
		    server_state_connection_responder_link_locked_initiator_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, ResponderIpAddress, ResponderPortNo, InitiatorIP,InitiatorPortNo)
	    end;

	{udp_link_establish_request,ConnectionInitiatorPID}->
	    ConnectionInitiatorPID!{udp_link_establish_response, peerAlreadyConnectedError},
	    server_state_connection_responder_link_locked_initiator_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, ResponderIpAddress, ResponderPortNo, InitiatorIP,InitiatorPortNo);

	{tcp_closed,Socket} ->
	    %% tcp connection was released
	    io:format("Server socket closed ~n"),
	    ConnectionInitiatorPID!release_request,
	    link_stop_ind( Nm_tcp_send_ProcessPid),
	    nm_user_store:delete_by_username(Username),
            exit(all);

	{link_lock_indication,UpdatedResponderIpAddress,UpdatedResponderPortNo}->
	    %% Step 4): Inform this user about ip-address and port for UDP of peer
	    ConnectionInitiatorPID!{responder_connection_indication,UpdatedResponderIpAddress,UpdatedResponderPortNo},
	    server_state_connection_responder_link_locked_initiator_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, UpdatedResponderIpAddress, UpdatedResponderPortNo, InitiatorIP,InitiatorPortNo) ;

	link_unlock_indication ->
	    %% peer side failed setting up the UDP link
	    ConnectionInitiatorPID!responder_no_connection_indication,
	    server_state_connection_responder_link_unlocked_intiator_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID,InitiatorIP,InitiatorPortNo);

	{initiator_connection_indication,UpdatedInitiatorIP,UpdatedInitiatorPortNo} ->
	    punch_start_ind(Nm_tcp_send_ProcessPid, UpdatedInitiatorIP, UpdatedInitiatorPortNo),
	    server_state_connection_responder_link_locked_initiator_locked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, ResponderIpAddress, ResponderPortNo, UpdatedInitiatorIP, UpdatedInitiatorPortNo); 

	initiator_no_connection_indication ->
	    punch_stop_ind(Nm_tcp_send_ProcessPid),
	    server_state_connection_responder_link_locked_initiator_unlocked(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, ConnectionInitiatorPID, ResponderIpAddress, ResponderPortNo);

	release_request->
	    link_stop_ind( Nm_tcp_send_ProcessPid),
	    server_state_attached(Nm_udp_link_ProcessPid,Socket, Nm_tcp_send_ProcessPid, Username, locked, ResponderIpAddress, ResponderPortNo)
    end.




detach_resp(Nm_tcp_send_ProcessPid)->
    io:format("Server: Detached ~n", []),
    Nm_tcp_send_ProcessPid!detach_resp.

attach_resp(Nm_tcp_send_ProcessPid, Username, Password)->
    io:format("Server: Client attached with name ~p and  password ~p ~n", [Username, Password]),
    Nm_tcp_send_ProcessPid!{attach_resp, Username, Password}.

setup_resp(Nm_tcp_send_ProcessPid, Username, PeerUsername)->
    io:format("Server: Client ~p successfully connects to client ~p ~n", [Username, PeerUsername]),
    Nm_tcp_send_ProcessPid!{setup_resp, Username, PeerUsername}.

attach_rej(Nm_tcp_send_ProcessPid,ErrorReason) ->
    io:format("Server: attach_rej ~n", []),
    Nm_tcp_send_ProcessPid!{attach_rej, ErrorReason}.

setup_rej(Nm_tcp_send_ProcessPid,ErrorReason) ->
    io:format("Server: setup_rej ~n", []),
    Nm_tcp_send_ProcessPid! {setup_rej, ErrorReason}.

link_lock_req(Nm_tcp_send_ProcessPid) ->
    io:format("Server: link_lock_req ~n", []),
    Nm_tcp_send_ProcessPid!link_lock_req.

release_resp(Nm_tcp_send_ProcessPid)->
    io:format("Server: release_resp ~n", []),
    Nm_tcp_send_ProcessPid!release_resp.

release_rej(Nm_tcp_send_ProcessPid,ErrorReason) ->
    io:format("Server: release_rej ~n", []),
    Nm_tcp_send_ProcessPid!{release_rej,ErrorReason}.

link_start_ind(Nm_tcp_send_ProcessPid, Ref)->
    io:format("Server: link_start_ind ~n", []),
    Nm_tcp_send_ProcessPid! {link_start_ind, Ref}.

link_stop_ind( Nm_tcp_send_ProcessPid)->
    io:format("Server: link_stop_ind ~n", []),
    Nm_tcp_send_ProcessPid!link_stop_ind.

punch_start_ind(Nm_tcp_send_ProcessPid, ToIP, ToPort)->
    io:format("Server: punch_start_ind ~n", []),
    Nm_tcp_send_ProcessPid!{punch_start_ind, ToIP, ToPort}.

punch_stop_ind(Nm_tcp_send_ProcessPid)->
    io:format("Server: punch_stop_ind ~n", []),
    Nm_tcp_send_ProcessPid!punch_stop_ind.

