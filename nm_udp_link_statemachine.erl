-module(nm_udp_link_statemachine).
-export([server_state_udp_link_unlocked/1]).


%% this is the data link layer.
%% purpose is to capture the the state of the udp link in direction client to server. 
%% if continually ip packets from the client are received, the link is considered as locked, otherwise unlocked.

server_state_udp_link_unlocked(NetworkLayerPID) ->
    receive
	{udp_port_info_indication,IP,PortNo, ClientUDPPort}->
	    %% udp link had been established, store udp IP address and port number
	    NetworkLayerPID!{link_lock_indication,IP,PortNo},
	    io:format("Server: Sending link_lock_indication NetworkLayerPID: ~p, IP: ~p ,PortNo: ~p ~n", [NetworkLayerPID, IP, PortNo]),
	    server_state_udp_link_locked(NetworkLayerPID)

	    %%    after timeout of e.g. 120 s optionally a udp_link_loss_indication message might here be sent to the udp 
	    %%    client in order to increase the udp message frequency from the client on the link.

	    %%    clarify, whether the ip-address and port number shall become invalidated after a certain link timeout e.g. 10 minutes
    end.

server_state_udp_link_locked(NetworkLayerPID) ->
    Timeout = 30 * 1000,
    receive
	{udp_port_info_indication,IP,PortNo, ClientUDPPort}->
	    %% udp link had been established, store udp IP address and port number
	    %% inform network layer
	    NetworkLayerPID!{link_lock_indication,IP,PortNo},
	    io:format("Server: Sending link_lock_indication NetworkLayerPID: ~p, IP: ~p ,PortNo: ~p ~n", [NetworkLayerPID, IP, PortNo]),
	    server_state_udp_link_locked(NetworkLayerPID)

    after
	Timeout ->
	    %% indicate udp link loss timeout
	    %% if no udp_port_info_indication message from client had been received within the expected time period
	    NetworkLayerPID!link_unlock_indication,
	    io:format("Server: Sending link_unlock_indication NetworkLayerPID: ~p ~n", [NetworkLayerPID]),
	    server_state_udp_link_unlocked(NetworkLayerPID)
    end.

